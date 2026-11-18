"""
git_workflow.py - the whole commit-cleaner workflow in one command, with a short summary as output.

    python tools/git_workflow.py --dry-run          show the plan only
    python tools/git_workflow.py                    commit + merge + tag + push the private repo, then sync + push the public repo
    python tools/git_workflow.py --no-public        private repo only
    python tools/git_workflow.py --no-push          do everything locally
    python tools/git_workflow.py --skip docs/project_map --skip some/other/path     keep paths out (repeatable)
    python tools/git_workflow.py --plan plan.txt    own grouping: lines "branch-name | path path ..." (rest is grouped automatically)

What it does (private repo, run from anywhere):
  1. Reads the uncommitted changes. Never commits local state (db, camera_config.json), files > 5 MB, untracked folders with > 300
     files, or anything matching --skip. Stops if a secret pattern is found in a changed text file.
  2. Groups the changes into features (dashboard: one per features/<name>, tests with it; other areas: top folder + second folder).
  3. For each feature: branch nekolaiv/<feature>-<MMDD> from dev, one commit per lowest directory ("<tag>: <message>"),
     merge back into dev with --no-ff, annotated tag v0.0.N (next free number).
  4. Pushes dev, the new branches and the tags.
  5. Public copy (../huli-kamote-public): copies the committed private dev tree with the same exclusions as the first public copy
     (no weights, videos, zips, databases, keys, _archive, dataset / run pictures), scans it for secrets, commits per top folder
     on a sync branch, merges into main with --no-ff, tags the same version, pushes.
Commit messages are generic ("feat: update <dir> (3 files)"): use --plan or reword later if you want more detail.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

PRIV = Path(__file__).resolve().parent.parent
PUB = PRIV.parent / "huli-kamote-public"
TRAILER = "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
LOCAL_STATE = {"hulikamote_backend/camera_config.json", "hulikamote_backend/hulikamote.db", "hulikamote_backend/test_hulikamote.db"}
MAX_BYTES = 5_000_000
MAX_UNTRACKED_DIR = 300
SECRET = re.compile(r'BEGIN (RSA |EC )?PRIVATE KEY|"private_key"|service_role|sb_secret_|eyJ[A-Za-z0-9_-]{20,}\.|AIza[0-9A-Za-z_-]{20}')
BINARY = {".png", ".jpg", ".jpeg", ".onnx", ".db", ".pt", ".t7", ".pb", ".mp4", ".zip", ".lock", ".gif", ".ico", ".pdf", ".exe"}
TOP = {"hulikamote_backend": "backend", "hulikamote_dashboard": "dashboard", "hulikamote_app": "app", "hulikamote_camera": "camera",
       "hulikamote_visualizer": "visualizer", "training_lab": "training-lab"}
# public copy rules (same as the first public copy)
PUB_BAD_EXT = {".onnx", ".pt", ".pth", ".t7", ".pb", ".mp4", ".avi", ".zip", ".db", ".key", ".exe"}
PUB_DATA_OK = {".md", ".yaml", ".yml", ".json", ".csv"}
PUB_KEEP_ONLY_PUBLIC = {"PUBLIC_NOTES.md"}


def git(repo, *args, check=True, raw=False):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True)
    if check and r.returncode:
        raise SystemExit(f"git {' '.join(args)} failed in {repo}:\n{r.stderr.decode('utf-8', 'replace')[-600:]}")
    return r.stdout if raw else r.stdout.decode("utf-8", "replace")


def tag_exists(name):
    return bool(git(PRIV, "tag", "--list", name).strip())


_counter = {"n": None}


def _bump():
    if _counter["n"] is None:
        tags = [t for t in git(PRIV, "tag", "--list", "v0.0.*").split() if re.fullmatch(r"v0\.0\.\d+", t)]
        _counter["n"] = max((int(t.rsplit(".", 1)[1]) for t in tags), default=0)
    _counter["n"] += 1
    return f"v0.0.{_counter['n']}"


# ── 1. collect changes ──────────────────────────────────────────────────────────
def collect(skips):
    raw = git(PRIV, "status", "--porcelain", "-z", raw=True).decode("utf-8", "replace").split("\0")
    files, notes = {}, []                       # path -> 'M' | 'D' | 'A'
    i = 0
    while i < len(raw):
        e = raw[i]; i += 1
        if len(e) < 4:
            continue
        xy, path = e[:2], e[3:]
        if "R" in xy or "C" in xy:
            i += 1                               # skip the 'from' path of a rename
        st = "D" if "D" in xy else ("A" if xy == "??" else "M")
        if path.endswith("/"):                   # an untracked folder: expand
            found = git(PRIV, "ls-files", "--others", "--exclude-standard", "-z", "--", path, raw=True).decode("utf-8").split("\0")
            found = [f for f in found if f]
            if len(found) > MAX_UNTRACKED_DIR:
                notes.append(f"skipped folder {path} ({len(found)} untracked files)")
                continue
            for f in found:
                files[f] = "A"
        else:
            files[path] = st
    keep = {}
    for p, st in files.items():
        if p in LOCAL_STATE:
            notes.append(f"local state left out: {p}"); continue
        if any(p == s or p.startswith(s.rstrip("/") + "/") for s in skips):
            notes.append(f"--skip: {p}"); continue
        f = PRIV / p
        if st != "D" and f.is_file() and f.stat().st_size > MAX_BYTES:
            notes.append(f"over 5 MB left out: {p}"); continue
        keep[p] = st
    return keep, notes


def scan_secrets(paths):
    hits = []
    for p in paths:
        f = PRIV / p
        if f.suffix.lower() in BINARY or not f.is_file() or p == "tools/git_workflow.py":   # this file holds the patterns themselves
            continue
        try:
            for n, line in enumerate(f.read_text("utf-8", "ignore").splitlines(), 1):
                if SECRET.search(line):
                    hits.append(f"{p}:{n}")
                    break
        except OSError:
            pass
    return hits


# ── 2. group ────────────────────────────────────────────────────────────────────
def feature_of(p):
    parts = p.split("/")
    top = TOP.get(parts[0], parts[0])
    if len(parts) == 1:
        return "root"
    if parts[0] == "hulikamote_dashboard":
        if len(parts) > 3 and parts[1] in ("lib", "test") and parts[2] == "features":
            return f"dashboard-{parts[3]}"
        return "dashboard-core"
    second = parts[1] if len(parts) > 2 else "files"
    return f"{top}-{second}".lower()


def is_test(p):
    n = p.rsplit("/", 1)[-1]
    return "/tests/" in "/" + p or "/test/" in "/" + p or n.startswith("test_") or n.endswith("_test.dart")


def commit_tag(paths, states):
    if all(is_test(p) for p in paths):
        return "test"
    if all(p.startswith("docs/") or p.endswith(".md") for p in paths):
        return "docs"
    if all(states[p] == "D" for p in paths):
        return "refactor"
    if all(p.split("/")[0] in ("tools", "benchmarks") or p.endswith((".yaml", ".yml", ".json", ".lock", ".gitignore", ".txt")) for p in paths):
        return "chore"
    return "feat"


def add_commit(paths, states, message):
    for k in range(0, len(paths), 80):
        git(PRIV, "add", "-A", "--", *paths[k:k + 80])
    if git(PRIV, "diff", "--cached", "--name-only").strip() == "":
        return False
    git(PRIV, "commit", "-q", "-m", message, "-m", TRAILER)
    return True


# ── private workflow ────────────────────────────────────────────────────────────
def private_workflow(args):
    if git(PRIV, "branch", "--show-current").strip() != "dev":
        raise SystemExit("not on dev: switch to dev first")
    if git(PRIV, "diff", "--cached", "--name-only").strip():
        raise SystemExit("something is already staged: commit or unstage it first")
    changes, notes = collect(args.skip)
    if not changes:
        print("private: nothing to commit"); return [], [], notes
    hits = scan_secrets(changes)
    if hits:
        raise SystemExit("secret pattern found, stopping:\n  " + "\n  ".join(hits))

    groups = defaultdict(list)
    plan_names = {}
    if args.plan:
        for line in Path(args.plan).read_text("utf-8").splitlines():
            if "|" in line:
                name, paths = line.split("|", 1)
                for pp in paths.split():
                    plan_names[pp.rstrip("/")] = name.strip()
    for p in sorted(changes):
        key = next((n for pp, n in plan_names.items() if p == pp or p.startswith(pp + "/")), None) or feature_of(p)
        groups[key].append(p)

    day = datetime.date.today().strftime("%m%d")
    plan = []
    for key, paths in sorted(groups.items()):
        by_dir = defaultdict(list)
        for p in paths:
            by_dir[os.path.dirname(p) or "."].append(p)
        plan.append((key, by_dir))
    if args.dry_run:
        for key, by_dir in plan:
            print(f"  {key}: {sum(len(v) for v in by_dir.values())} files, {len(by_dir)} commits")
        for n in notes:
            print("  note:", n)
        return [], [], notes

    branches, tags = [], []
    for key, by_dir in plan:
        name = f"nekolaiv/{re.sub('[^a-z0-9-]', '-', key.lower())}-{day}"
        base, k = name, 2
        while git(PRIV, "branch", "--list", name).strip() or git(PRIV, "ls-remote", "--heads", "origin", name).strip():
            name = f"{base}-{k}"; k += 1
        git(PRIV, "checkout", "-q", "dev")
        git(PRIV, "checkout", "-q", "-b", name)
        made = 0
        for d, paths in sorted(by_dir.items()):
            states = {p: changes[p] for p in paths}
            verb = "add" if all(s == "A" for s in states.values()) else ("remove" if all(s == "D" for s in states.values()) else "update")
            msg = f"{commit_tag(paths, states)}: {verb} {d} ({len(paths)} file{'s' if len(paths) > 1 else ''})"
            made += add_commit(paths, states, msg)
        git(PRIV, "checkout", "-q", "dev")
        if made == 0:
            git(PRIV, "branch", "-q", "-D", name); continue
        git(PRIV, "merge", "-q", "--no-ff", name, "-m", f"Merge branch '{name}' into dev")
        ver = _bump()
        git(PRIV, "tag", "-a", ver, "-m", f"{ver}: {key} ({made} commits)")
        branches.append(name); tags.append(ver)
        print(f"  {ver}  {name}  ({made} commits)")
    return branches, tags, notes


# ── public sync ────────────────────────────────────────────────────────────────
def pub_excluded(p):
    if p.startswith("_archive/") or p == "archive.zip" or p.startswith("archive.zip/"):
        return True
    name = p.rsplit("/", 1)[-1]
    ext = os.path.splitext(name)[1].lower()
    if ext in PUB_BAD_EXT or name == "google-services.json":
        return True
    if p.startswith(("training_lab/datasets/", "training_lab/runs/")):
        return not (ext in PUB_DATA_OK or name == ".gitkeep")
    return False


def public_workflow(version, args):
    if not PUB.exists():
        print("public: folder not found, skipped"); return
    if git(PUB, "status", "--porcelain").strip() and not args.resume_public:
        raise SystemExit("public repo has uncommitted changes: clean it first")
    target = {}
    for row in git(PRIV, "ls-tree", "-r", "-z", "dev", raw=True).split(b"\0"):
        if not row:
            continue
        meta, path = row.split(b"\t", 1)
        mode, kind, sha = meta.decode().split()
        path = path.decode("utf-8")
        if kind == "blob" and mode != "160000" and not pub_excluded(path):
            target[path] = sha
    tracked = set(git(PUB, "ls-files", "-z").split("\0")) - {""}
    delete = [p for p in tracked if p not in target and p not in PUB_KEEP_ONLY_PUBLIC]
    proc = subprocess.Popen(["git", "-C", str(PRIV), "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    changed = []
    for path, sha in target.items():
        proc.stdin.write(sha.encode() + b"\n"); proc.stdin.flush()
        size = int(proc.stdout.readline().split()[2])
        data = proc.stdout.read(size); proc.stdout.read(1)
        dest = PUB / path
        if dest.exists() and dest.read_bytes().replace(b"\r\n", b"\n") == data.replace(b"\r\n", b"\n"):
            continue
        if len(data) > MAX_BYTES:
            print(f"  public: over 5 MB left out: {path}"); continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data); changed.append(path)
    proc.stdin.close(); proc.wait()
    for p in delete:
        f = PUB / p
        if f.exists():
            f.unlink()
    hits = []
    for p in changed:
        f = PUB / p
        if f.suffix.lower() not in BINARY and p != "tools/git_workflow.py":   # this file holds the patterns themselves
            for line in f.read_text("utf-8", "ignore").splitlines():
                if SECRET.search(line):
                    hits.append(p); break
    if hits:
        raise SystemExit("public: secret pattern found, stopping (files are written but NOT committed):\n  " + "\n  ".join(hits))
    if not changed and not delete:
        print("public: already in sync"); return
    branch = f"nekolaiv/sync-from-private-{version}"
    git(PUB, "checkout", "-q", "-b", branch)
    by_top = defaultdict(list)
    for p in changed + delete:
        by_top[p.split("/")[0] if "/" in p else "(root)"].append(p)
    made = 0
    for top, paths in sorted(by_top.items()):
        spec = [p for p in paths] if top == "(root)" else [top]
        for k in range(0, len(spec), 80):
            git(PUB, "add", "-A", "--", *spec[k:k + 80])
        if git(PUB, "diff", "--cached", "--name-only").strip():
            git(PUB, "commit", "-q", "-m", f"chore: sync {top} from the private repo ({len(paths)} files)", "-m", TRAILER); made += 1
    git(PUB, "checkout", "-q", "main")
    git(PUB, "merge", "-q", "--no-ff", branch, "-m", f"Merge branch '{branch}' into main")
    git(PUB, "tag", "-a", version, "-m", f"{version}: Sync with the private repo at {version}")
    print(f"  public: {len(changed)} files changed, {len(delete)} removed, {made} commits, tagged {version}")
    if not args.no_push:
        r = subprocess.run(["git", "-C", str(PUB), "push", "origin", "main", branch, version], capture_output=True)
        print(f"  public pushed (exit {r.returncode})")
        if r.returncode:
            print(r.stderr.decode("utf-8", "replace")[-400:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-public", action="store_true")
    ap.add_argument("--no-push", action="store_true")
    ap.add_argument("--skip", action="append", default=[])
    ap.add_argument("--plan")
    ap.add_argument("--resume-public", action="store_true", help="continue a public sync that stopped after writing files")
    args = ap.parse_args()

    branches, tags, notes = private_workflow(args)
    if args.dry_run:
        return
    for n in notes:
        print("  note:", n)
    last = tags[-1] if tags else sorted(git(PRIV, "tag", "--list", "v0.0.*").split(), key=lambda t: int(t.rsplit(".", 1)[1]))[-1]
    if not args.no_push:
        r = subprocess.run(["git", "-C", str(PRIV), "push", "origin", "dev", *branches, "--tags"], capture_output=True)
        ahead = git(PRIV, "rev-list", "--count", "origin/dev..dev").strip()
        print(f"  private pushed (exit {r.returncode}), unpushed commits on dev: {ahead}")
        if r.returncode:
            print(r.stderr.decode("utf-8", "replace")[-400:])
    if not args.no_public:
        public_workflow(last, args)
        if not args.no_push:
            ahead = git(PUB, "rev-list", "--count", "origin/main..main").strip()
            print(f"  public unpushed commits on main: {ahead}")
    print("DONE", " ".join(tags))


if __name__ == "__main__":
    main()
