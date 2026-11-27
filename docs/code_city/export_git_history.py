#!/usr/bin/env python3
"""Export a git repo's history (all branches) so Code City can replay it.

Usage:  python export_git_history.py [repo_folder] [output.json]
Default: the current folder, written to code_city_history.json.
Only needs Python 3 and git. It reads the history; it changes nothing."""
import json, os, re, subprocess, sys

repo = sys.argv[1] if len(sys.argv) > 1 else '.'
out = sys.argv[2] if len(sys.argv) > 2 else 'code_city_history.json'
SKIP = re.compile(r'(^|/)(node_modules|\.git|venv|\.venv|build|dist|\.dart_tool|__pycache__|\.idea|Pods)/|\.(lock|map)$|\.min\.js$|package-lock\.json$')


def git(*a):
    r = subprocess.run(['git', '-c', 'core.quotepath=false', '-C', repo] + list(a), capture_output=True, text=True, encoding='utf-8', errors='replace')
    if r.returncode:
        sys.exit(r.stderr.strip() or 'git failed')
    return r.stdout


def expand(p):
    m = re.match(r'^(.*)\{(.*) => (.*)\}(.*)$', p)
    if m:
        a, b, c, d = m.groups()
        return (a + b + d).replace('//', '/'), (a + c + d).replace('//', '/')
    if ' => ' in p:
        o, n = p.split(' => ', 1)
        return o, n
    return None, p


# every commit of every branch, parents before children (merge commits are kept: they show where branches join)
raw = git('log', '--branches', '--remotes', '--reverse', '--topo-order', '-M', '--numstat', '--summary', '--pretty=format:@@%H\t%P\t%at\t%an\t%s')
commits = []


def finish(c):
    if not c:
        return
    ent = []
    for a, d, p in c['n']:
        old, new = expand(p)
        if a == '-' or SKIP.search(new):
            continue
        a, d = int(a), int(d)
        if old is not None and not SKIP.search(old):
            ent.append(['R', new, a, d, old])
        elif new in c['c']:
            ent.append(['A', new, a, d])
        elif new in c['d']:
            ent.append(['D', new, a, d])
        else:
            ent.append(['M', new, a, d])
    commits.append({'h': c['h'], 'p': c['p'], 't': c['t'], 'a': c['a'], 'm': c['m'], 'f': ent})


cur = None
for line in raw.split('\n'):
    if line.startswith('@@'):
        finish(cur)
        h, p, t, a, m = (line[2:].split('\t', 4) + ['', '', '', '', ''])[:5]
        cur = {'h': h, 'p': p.split() if p else [], 't': int(t or 0), 'a': a, 'm': m, 'n': [], 'c': set(), 'd': set()}
    elif cur is not None:
        mm = re.match(r'^(\d+|-)\t(\d+|-)\t(.+)$', line)
        if mm:
            cur['n'].append(mm.groups())
        else:
            s = line.strip()
            if s.startswith('create mode'):
                cur['c'].add(s.split(' ', 3)[3])
            elif s.startswith('delete mode'):
                cur['d'].add(s.split(' ', 3)[3])
finish(cur)

branches, remotes = {}, {}
for ln in git('for-each-ref', '--format=%(refname:short)\t%(objectname)', 'refs/heads').splitlines():
    n, h = ln.split('\t')
    branches[n] = h
for ln in git('for-each-ref', '--format=%(refname:short)\t%(objectname)', 'refs/remotes').splitlines():
    n, h = ln.split('\t')
    if not n.endswith('/HEAD'):
        remotes[n] = h
# the apps of the project: the folders that hold a manifest file (outermost only). A monorepo has several.
MANIFESTS = {'pubspec.yaml', 'package.json', 'pyproject.toml', 'requirements.txt', 'setup.py', 'setup.cfg', 'pom.xml', 'build.gradle', 'build.gradle.kts', 'Cargo.toml', 'go.mod', 'composer.json', 'Gemfile', 'CMakeLists.txt'}
found = {}
for p in git('ls-files').splitlines():
    base = p.rsplit('/', 1)[-1]
    if base in MANIFESTS and '/' in p and not SKIP.search(p):
        found.setdefault(p.rsplit('/', 1)[0], base)
apps = {}
for d in sorted(found, key=lambda x: x.count('/')):
    if not any(d == a or d.startswith(a + '/') for a in apps):
        apps[d] = found[d]

name = os.path.basename(os.path.abspath(repo))
head = git('rev-parse', '--abbrev-ref', 'HEAD').strip()

# ---- imports as of HEAD: which file uses which file (for the architecture roads and wires) ----
heads = set(p for p in git('ls-files').splitlines() if not SKIP.search(p))
app_of = lambda p: next((a for a in apps if p == a or p.startswith(a + '/')), p.split('/')[0] if '/' in p else '')
RX = r"^[[:space:]]*((from[[:space:]]+[.[:alnum:]_]+[[:space:]]+import[[:space:]])|(import[[:space:]]+[.[:alnum:]_'\"])|(export[[:space:]].*from[[:space:]]+['\"]))"
try:
    gr = subprocess.run(['git', '-c', 'core.quotepath=false', '-C', repo, 'grep', '-n', '-I', '-E', RX, '--', '*.py', '*.dart', '*.js', '*.ts', '*.tsx', '*.jsx'], capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
except Exception:
    gr = ''
edges = set()


def add(src, dst):
    dst = os.path.normpath(dst).replace('\\', '/')
    if dst in heads and dst != src:
        edges.add((src, dst))


def py_mod(src, mod, names):
    lv = len(mod) - len(mod.lstrip('.'))
    rest = mod.lstrip('.').replace('.', '/')
    if lv:
        b = os.path.dirname(src)
        for _ in range(lv - 1):
            b = os.path.dirname(b)
        bases = [b]
    else:
        bases = [app_of(src), '', os.path.dirname(src)]
    for b in bases:
        root = os.path.join(b, rest) if rest else b
        hit = False
        for c in (root + '.py', os.path.join(root, '__init__.py')):
            c = os.path.normpath(c).replace('\\', '/')
            if c in heads:
                add(src, c); hit = True
        for n in names:
            add(src, os.path.join(root, n + '.py'))
        if hit or any(os.path.normpath(os.path.join(root, n + '.py')).replace('\\', '/') in heads for n in names):
            return


for ln in gr.splitlines():
    m = re.match(r'^(.*?):(\d+):(.*)$', ln)
    if not m:
        continue
    src, text = m.group(1), m.group(3).strip()
    if SKIP.search(src):
        continue
    if src.endswith('.py'):
        mm = re.match(r'^from\s+([.\w]+)\s+import\s+(.*)$', text)
        if mm:
            names = [x.strip().split(' as ')[0].strip('() \\') for x in mm.group(2).split(',')]
            py_mod(src, mm.group(1), [n for n in names if re.match(r'^\w+$', n)])
            continue
        mm = re.match(r'^import\s+(.*)$', text)
        if mm:
            for part in mm.group(1).split(','):
                mod = part.strip().split(' as ')[0].strip()
                if re.match(r'^[.\w]+$', mod):
                    py_mod(src, mod, [])
    else:
        mm = re.search(r"""(?:import|export|from)\s+(?:.*?\s+from\s+)?['"]([^'"]+)['"]""", text)
        if not mm:
            continue
        t = mm.group(1)
        if src.endswith('.dart'):
            if t.startswith('dart:'):
                continue
            if t.startswith('package:'):
                rest = t.split('/', 1)[1] if '/' in t else ''
                add(src, os.path.join(app_of(src), 'lib', rest))
            else:
                add(src, os.path.join(os.path.dirname(src), t))
        elif t.startswith('.'):
            base = os.path.join(os.path.dirname(src), t)
            for suf in ('', '.js', '.ts', '.tsx', '.jsx', '/index.js', '/index.ts'):
                add(src, base + suf)
imports = sorted([list(e) for e in edges])

# ---- flows: what happens when a user presses a button (from the Project Mapper map.json, read only) ----
flows = []
mp = sys.argv[3] if len(sys.argv) > 3 else os.path.join(repo, '..', 'project_mapper', 'outputs', name, 'map.json')
if os.path.exists(mp):
    try:
        mj = json.load(open(mp, encoding='utf-8'))
        seen = set()

        def walk(t, acc, depth):
            if t.get('file') and t['file'] in heads and t['file'] not in acc:
                acc.append(t['file'])
            if depth < 5:
                for ch in t.get('children', []):
                    walk(ch, acc, depth + 1)
        for ft in mj.get('features', []):
            for ac in ft.get('actions', []):
                for api in ac.get('api', []):
                    for eid in api.get('endpoints', []):
                        tr = mj.get('trees', {}).get(eid)
                        if not tr:
                            continue
                        acc = [ac['file']] if ac.get('file') in heads else []
                        walk(tr, acc, 0)
                        acc = acc[:9]
                        if len(acc) >= 2 and tuple(acc) not in seen:
                            seen.add(tuple(acc))
                            flows.append({'l': '%s · %s → %s' % (ft.get('label', ''), ac.get('label', ''), eid), 'p': acc})
        flows = flows[:90]
    except Exception as ex:
        print('map.json not used:', ex)

with open(out, 'w', encoding='utf-8') as fh:
    json.dump({'repo': name, 'head': head, 'branches': branches, 'remotes': remotes, 'apps': apps, 'imports': imports, 'flows': flows, 'commits': commits}, fh, separators=(',', ':'))
print('Wrote %s: %d commits, %d branches, %d imports, %d flows, %d bytes' % (out, len(commits), len(branches), len(imports), len(flows), os.path.getsize(out)))
