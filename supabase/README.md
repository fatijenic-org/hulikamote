# Online mode (Supabase): what is left for you

Everything else is built. This is the only manual work, about 10 minutes, once.

## How it works (so you can explain it)
Confirm a ticket on the laptop -> the laptop copies the ticket, its photos and the notice into your Supabase project (using the
secret key) -> the phone app, signed in as the motorist, reads only its own rows and photos -> the laptop also sends a push
through Firebase. No Edge Function is needed: the laptop is the only writer, so it pushes right after it publishes.

## A. In Supabase (supabase.com, free account)
1. **New project** (any name; keep the database password somewhere). Leave **Enable Data API**, **Automatically expose new tables** and **Enable automatic RLS** all **ON**:
   the app talks to the Data API, `schema.sql` relies on the default table access and then removes what it must (and turns RLS on itself, so the third switch is only a second lock).
   Wait until it is ready.
2. **SQL Editor -> New query**, paste **all** of `supabase/schema.sql`, **Run**. "Success. No rows returned" is the right answer.
   It is safe to run again later.
3. **Authentication -> Providers (or Sign In / Providers) -> Email**: turn **Confirm email OFF**, Save.
   The demo accounts do not need this; motorists who sign up in the app do (the app uses a made-up address per plate).
4. **Project Settings -> API (or API Keys)**: copy three things: the **Project URL**, the **anon** key (public), the **service_role** key (secret).

## B. On the laptop (dashboard -> Motorists -> Online)
5. Paste the **Project address** and the **service key** -> **Save cloud** -> **Test cloud**.
   It must say *"Connected, and the setup is complete."* Anything else names what is missing (run the SQL again, turn off Confirm email).
6. **Create demo accounts**: Juan, Maria and Pedro appear in the cloud with all the plates they own on the laptop
   (password `password123`, sign in with `ABC 1234`, `DEF 5678`, `GHI 9012`).
7. **Push** (a closed phone): the laptop needs `hulikamote_backend/firebase-service-account.json` of Firebase project **hulikamote-001**
   (the project the app is built for). Press **Check push**; once a phone has signed in, **Send test push**.
   If you rotated the Firebase key, download the new one (Firebase console -> Project settings -> Service accounts) and replace that file.

## C. On the phone
8. Tell the app the project, either way:
   - once at build time: `flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=...` (in `hulikamote_app`), or
   - in the app: sign-in page -> **Change** -> **Online** -> paste the Project URL and the **anon** key (never the service key).
9. Sign in as Juan, then confirm a ticket for one of his plates on the laptop. The notice, photos and a push arrive.

## What was checked, and what could not be
- `schema.sql` was parsed with PostgreSQL's own parser and linted for the safety rules (`tools/check_schema.py`): every table
  has row-level security, security-definer functions fix their search path, only `plate_taken` is public, and the file can be re-run.
- Both sides were tested against a stand-in for Supabase (requests, answers, errors), and the app's sign-up, sign-in, token
  renewal, appeals and push registration against recorded replies.
- **Not possible here: talking to a real Supabase project.** Step 5 ("Test cloud") is that proof, and it tells you exactly
  what to fix if something differs.

## Safety notes
- Phones cannot edit their plate, cannot write tickets or notices, and can only read their own rows and photo folder.
- The service key lives only in `hulikamote_backend/.env` (git ignores it). Never put it in the app or in git.
- Use a project made for HULI-KAMOTE: the sign-up trigger in `schema.sql` runs for every account in the project.
