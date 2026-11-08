-- HULI-KAMOTE online mode. Run this ONCE in Supabase: SQL Editor -> New query -> paste everything -> Run.
-- Safe to run again (it never deletes data). Use a project made for HULI-KAMOTE: the sign-up trigger below runs for every
-- account in the project.
--
-- Who writes what:
--   the laptop   uses the secret service_role key, which ignores row-level security (it publishes tickets and notices);
--   the phone    signs in as a motorist and can only read its own rows. It cannot edit its plate, and it can only
--                add an appeal for one of its own tickets.

-- ─── helpers ────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.plate_key_of(p text) returns text
language sql immutable as $$ select regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g') $$;

-- ─── tables ─────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.profiles (        -- one per motorist account
  user_id    uuid primary key references auth.users on delete cascade,
  plate_key  text not null,                         -- the plate the account was made with, capitals and digits only
  plate      text not null,
  name       text not null,
  email      text not null default '',              -- where notices are also e-mailed (optional)
  created_at timestamptz not null default now()
);

create table if not exists public.plates (          -- every plate an account owns (a plate belongs to one account)
  plate_key  text primary key,
  plate      text not null,
  user_id    uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists plates_user on public.plates (user_id);

create table if not exists public.tickets (         -- a confirmed violation
  id          text primary key,                     -- the violation id on the laptop
  user_id     uuid not null references auth.users on delete cascade,
  plate_key   text not null,
  cls         text not null,
  confidence  real not null default 1,
  occurred_at timestamptz not null,
  frames      text[] not null default '{}',         -- photo paths in the 'evidence' bucket
  created_at  timestamptz not null default now()
);

create table if not exists public.notices (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users on delete cascade,
  ticket_id  text references public.tickets(id) on delete set null,
  subject    text not null,
  body       text not null,
  frames     text[] not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists notices_user_time on public.notices (user_id, created_at desc);

create table if not exists public.appeals (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  text not null unique references public.tickets(id) on delete cascade,
  user_id    uuid not null references auth.users on delete cascade,
  reason     text not null check (char_length(reason) between 1 and 1000),
  status     text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.device_tokens (   -- phones that can receive a push
  token      text primary key,
  user_id    uuid not null references auth.users on delete cascade,
  updated_at timestamptz not null default now()
);

-- Older versions of this file kept the plate only on the profile: carry those plates over.
insert into public.plates (plate_key, plate, user_id)
  select plate_key, plate, user_id from public.profiles on conflict (plate_key) do nothing;

-- ─── a profile is made together with the account (so a sign-up can never be left half done) ───────────────────────
-- The phone signs up with user data {name, plate, contact_email}; an account without a plate gets no profile.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  k text := public.plate_key_of(new.raw_user_meta_data ->> 'plate');
  shown text := upper(trim(coalesce(new.raw_user_meta_data ->> 'plate', '')));
begin
  if k = '' then
    return new;
  end if;
  insert into public.profiles (user_id, plate_key, plate, name, email)
  values (new.id, k, shown,
          coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''), 'Motorist'),
          coalesce(trim(new.raw_user_meta_data ->> 'contact_email'), ''));
  insert into public.plates (plate_key, plate, user_id) values (k, shown, new.id);   -- fails if the plate is taken
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─── functions the phone may call ───────────────────────────────────────────────────────────────────────────────
-- Is this plate already used by an account? (lets the sign-up page say so before anything is created)
create or replace function public.plate_taken(p_plate text) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.plates where plate_key = public.plate_key_of(p_plate))
$$;
revoke all on function public.plate_taken(text) from public;
grant execute on function public.plate_taken(text) to anon, authenticated;

-- Remember this phone for push. A phone used by another account before moves to this one.
create or replace function public.register_device(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  insert into public.device_tokens (token, user_id) values (p_token, auth.uid())
  on conflict (token) do update set user_id = auth.uid(), updated_at = now();
end $$;
revoke all on function public.register_device(text) from public;
grant execute on function public.register_device(text) to authenticated;

-- Stop pushes to this phone for this account (called when the motorist signs out).
create or replace function public.forget_device(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from public.device_tokens where token = p_token and user_id = auth.uid()
$$;
revoke all on function public.forget_device(text) from public;
grant execute on function public.forget_device(text) to authenticated;

-- ─── row-level security ─────────────────────────────────────────────────────────────────────────────────────────
alter table public.profiles       enable row level security;
alter table public.plates         enable row level security;
alter table public.tickets        enable row level security;
alter table public.notices        enable row level security;
alter table public.appeals        enable row level security;
alter table public.device_tokens  enable row level security;

drop policy if exists "own profile"        on public.profiles;       -- the old rule allowed editing the plate
drop policy if exists "own profile read"   on public.profiles;
drop policy if exists "own profile edit"   on public.profiles;
drop policy if exists "own plates"         on public.plates;
drop policy if exists "own tickets"        on public.tickets;
drop policy if exists "own notices"        on public.notices;
drop policy if exists "own appeals read"   on public.appeals;
drop policy if exists "own appeals add"    on public.appeals;
drop policy if exists "own tokens"         on public.device_tokens;
drop policy if exists "own tokens read"    on public.device_tokens;

create policy "own profile read" on public.profiles      for select using (auth.uid() = user_id);
create policy "own profile edit" on public.profiles      for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own plates"       on public.plates        for select using (auth.uid() = user_id);
create policy "own tickets"      on public.tickets       for select using (auth.uid() = user_id);
create policy "own notices"      on public.notices       for select using (auth.uid() = user_id);
create policy "own appeals read" on public.appeals       for select using (auth.uid() = user_id);
create policy "own appeals add"  on public.appeals       for insert with check (
  auth.uid() = user_id and exists (select 1 from public.tickets t where t.id = ticket_id and t.user_id = auth.uid()));
create policy "own tokens read"  on public.device_tokens for select using (auth.uid() = user_id);

-- The phone may change only its name and contact e-mail, never its plate; tokens are changed through the functions above.
revoke insert, update, delete on public.profiles      from anon, authenticated;
grant  update (name, email)   on public.profiles      to authenticated;
revoke insert, update, delete on public.plates        from anon, authenticated;
revoke insert, update, delete on public.device_tokens from anon, authenticated;
revoke update, delete         on public.appeals       from anon, authenticated;
revoke insert, update, delete on public.tickets       from anon, authenticated;
revoke insert, update, delete on public.notices       from anon, authenticated;

-- ─── photos: a private bucket; each motorist can only read the folder named after their own user id ─────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('evidence', 'evidence', false, 10485760, array['image/jpeg', 'image/png'])
  on conflict (id) do update set public = false, file_size_limit = 10485760, allowed_mime_types = array['image/jpeg', 'image/png'];
drop policy if exists "own evidence" on storage.objects;
create policy "own evidence" on storage.objects for select to authenticated
  using (bucket_id = 'evidence' and (storage.foldername(name))[1] = auth.uid()::text);

-- ─── self-check (the dashboard's "Test cloud" button calls this with the service key) ───────────────────────────────
create or replace function public.hulikamote_setup_check() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object(
    'tables', (select count(*) from information_schema.tables
               where table_schema = 'public' and table_name in ('profiles', 'plates', 'tickets', 'notices', 'appeals', 'device_tokens')) = 6,
    'signup_trigger', exists (select 1 from pg_trigger where tgname = 'on_auth_user_created' and not tgisinternal),
    'functions', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname in ('plate_taken', 'register_device', 'forget_device', 'handle_new_user', 'plate_key_of')) = 5,
    'bucket', exists (select 1 from storage.buckets where id = 'evidence' and not public),
    'plate_locked', not has_column_privilege('authenticated', 'public.profiles', 'plate_key', 'UPDATE')
  );
end $$;
revoke all on function public.hulikamote_setup_check() from public, anon, authenticated;
grant execute on function public.hulikamote_setup_check() to service_role;
