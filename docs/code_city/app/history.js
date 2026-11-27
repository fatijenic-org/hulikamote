/* Reads the whole git history of a repo (all branches) plus the imports and flows, in the JSON form Code City replays.
   The same job as export_git_history.py, so the app needs no Python. It only READS the repo. */
const fs = require('fs');
const path = require('path');

const SKIP = /(^|\/)(node_modules|\.git|venv|\.venv|build|dist|\.dart_tool|__pycache__|\.idea|Pods)\/|\.(lock|map)$|\.min\.js$|package-lock\.json$/;
const MANIFESTS = new Set(['pubspec.yaml', 'package.json', 'pyproject.toml', 'requirements.txt', 'setup.py', 'setup.cfg', 'pom.xml', 'build.gradle', 'build.gradle.kts', 'Cargo.toml', 'go.mod', 'composer.json', 'Gemfile', 'CMakeLists.txt']);
const norm = p => path.posix.normalize(p.replace(/\\/g, '/'));

function expand(p) {
  const m = p.match(/^(.*)\{(.*) => (.*)\}(.*)$/);
  if (m) { const [, a, b, c, d] = m; return [(a + b + d).split('//').join('/'), (a + c + d).split('//').join('/')]; }
  const i = p.indexOf(' => ');
  if (i >= 0) return [p.slice(0, i), p.slice(i + 4)];
  return [null, p];
}

async function exportHistory(repo, git) {
  const raw = await git(['log', '--branches', '--remotes', '--reverse', '--topo-order', '-M', '--numstat', '--summary', '--pretty=format:@@%H%x09%P%x09%at%x09%an%x09%s']);
  const commits = []; let cur = null;
  const finish = c => {
    if (!c) return;
    const ent = [];
    for (const [a, d, p] of c.n) {
      const [old, nw] = expand(p);
      if (a === '-' || SKIP.test(nw)) continue;
      const A = +a, D = +d;
      if (old !== null && !SKIP.test(old)) ent.push(['R', nw, A, D, old]);
      else if (c.c.has(nw)) ent.push(['A', nw, A, D]);
      else if (c.d.has(nw)) ent.push(['D', nw, A, D]);
      else ent.push(['M', nw, A, D]);
    }
    commits.push({ h: c.h, p: c.p, t: c.t, a: c.a, m: c.m, f: ent });
  };
  for (const line of raw.split('\n')) {
    if (line.startsWith('@@')) {
      finish(cur);
      const [h, p, t, a, ...m] = line.slice(2).split('\t');
      cur = { h, p: p ? p.split(' ').filter(Boolean) : [], t: +t || 0, a: a || '', m: m.join('\t'), n: [], c: new Set(), d: new Set() };
    } else if (cur) {
      const mm = line.match(/^(\d+|-)\t(\d+|-)\t(.+)$/);
      if (mm) cur.n.push([mm[1], mm[2], mm[3]]);
      else {
        const s = line.trim();
        if (s.startsWith('create mode')) cur.c.add(s.split(' ').slice(3).join(' '));
        else if (s.startsWith('delete mode')) cur.d.add(s.split(' ').slice(3).join(' '));
      }
    }
  }
  finish(cur);

  const branches = {}, remotes = {};
  for (const ln of (await git(['for-each-ref', '--format=%(refname:short)\t%(objectname)', 'refs/heads'])).split('\n')) { if (ln) { const [n, h] = ln.split('\t'); branches[n] = h; } }
  for (const ln of (await git(['for-each-ref', '--format=%(refname:short)\t%(objectname)', 'refs/remotes'])).split('\n')) { if (ln) { const [n, h] = ln.split('\t'); if (!n.endsWith('/HEAD')) remotes[n] = h; } }

  const lsfiles = (await git(['ls-files'])).split('\n').filter(Boolean);
  const heads = new Set(lsfiles.filter(p => !SKIP.test(p)));
  const found = new Map();
  for (const p of lsfiles) {
    const base = p.split('/').pop();
    if (MANIFESTS.has(base) && p.includes('/') && !SKIP.test(p)) { const d = p.slice(0, p.lastIndexOf('/')); if (!found.has(d)) found.set(d, base); }
  }
  const apps = {};
  [...found.keys()].sort((a, b) => a.split('/').length - b.split('/').length).forEach(d => { if (!Object.keys(apps).some(a => d === a || d.startsWith(a + '/'))) apps[d] = found.get(d); });
  const appOf = p => Object.keys(apps).find(a => p === a || p.startsWith(a + '/')) || (p.includes('/') ? p.split('/')[0] : '');

  /* imports as of HEAD */
  const edges = new Set(), add = (src, dst) => { dst = norm(dst); if (heads.has(dst) && dst !== src) edges.add(src + '\u0000' + dst); };
  const pyMod = (src, mod, names) => {
    const lv = mod.length - mod.replace(/^\.+/, '').length, rest = mod.replace(/^\.+/, '').split('.').join('/');
    let bases;
    if (lv) { let b = path.posix.dirname(src); for (let i = 0; i < lv - 1; i++) b = path.posix.dirname(b); bases = [b]; } else bases = [appOf(src), '', path.posix.dirname(src)];
    for (const b of bases) {
      const root = rest ? path.posix.join(b, rest) : b; let hit = false;
      for (const c of [root + '.py', path.posix.join(root, '__init__.py')]) { const n = norm(c); if (heads.has(n)) { add(src, n); hit = true; } }
      let any = false; for (const n of names) { const c = norm(path.posix.join(root, n + '.py')); if (heads.has(c)) { add(src, c); any = true; } }
      if (hit || any) return;
    }
  };
  let gr = '';
  try { gr = await git(['grep', '-n', '-I', '-E', "^[[:space:]]*((from[[:space:]]+[.[:alnum:]_]+[[:space:]]+import[[:space:]])|(import[[:space:]]+[.[:alnum:]_'\"])|(export[[:space:]].*from[[:space:]]+['\"]))", '--', '*.py', '*.dart', '*.js', '*.ts', '*.tsx', '*.jsx'], true); } catch (e) { gr = ''; }
  for (const ln of gr.split(/\r?\n/)) {                   // files with Windows line ends: "." does not match \r in JS
    const m = ln.match(/^(.*?):(\d+):(.*)$/); if (!m) continue;
    const src = m[1], text = m[3].trim(); if (SKIP.test(src)) continue;
    if (src.endsWith('.py')) {
      let mm = text.match(/^from\s+([.\w]+)\s+import\s+(.*)$/);
      if (mm) { const names = mm[2].split(',').map(x => x.trim().split(' as ')[0].replace(/[() \\]/g, '')).filter(n => /^\w+$/.test(n)); pyMod(src, mm[1], names); continue; }
      mm = text.match(/^import\s+(.*)$/);
      if (mm) for (const part of mm[1].split(',')) { const mod = part.trim().split(' as ')[0].trim(); if (/^[.\w]+$/.test(mod)) pyMod(src, mod, []); }
    } else {
      const mm = text.match(/(?:import|export|from)\s+(?:.*?\s+from\s+)?['"]([^'"]+)['"]/); if (!mm) continue;
      const t = mm[1];
      if (src.endsWith('.dart')) {
        if (t.startsWith('dart:')) continue;
        if (t.startsWith('package:')) add(src, path.posix.join(appOf(src), 'lib', t.includes('/') ? t.split('/').slice(1).join('/') : ''));
        else add(src, path.posix.join(path.posix.dirname(src), t));
      } else if (t.startsWith('.')) {
        const base = path.posix.join(path.posix.dirname(src), t);
        for (const suf of ['', '.js', '.ts', '.tsx', '.jsx', '/index.js', '/index.ts']) add(src, base + suf);
      }
    }
  }
  const imports = [...edges].map(e => e.split('\u0000')).sort((a, b) => (a[0] + a[1]).localeCompare(b[0] + b[1]));

  /* flows from the Project Mapper map.json, if it sits beside the project (read only) */
  const flows = []; const name = path.basename(path.resolve(repo));
  const mp = path.join(repo, '..', 'project_mapper', 'outputs', name, 'map.json');
  try {
    if (fs.existsSync(mp)) {
      const mj = JSON.parse(fs.readFileSync(mp, 'utf8')), seen = new Set();
      const walk = (t, acc, depth) => { if (t.file && heads.has(t.file) && !acc.includes(t.file)) acc.push(t.file); if (depth < 5) (t.children || []).forEach(ch => walk(ch, acc, depth + 1)); };
      for (const ft of mj.features || []) for (const ac of ft.actions || []) for (const api of ac.api || []) for (const eid of api.endpoints || []) {
        const tr = (mj.trees || {})[eid]; if (!tr) continue;
        const acc = heads.has(ac.file) ? [ac.file] : []; walk(tr, acc, 0);
        const a9 = acc.slice(0, 9), key = a9.join('|');
        if (a9.length >= 2 && !seen.has(key)) { seen.add(key); flows.push({ l: (ft.label || '') + ' · ' + (ac.label || '') + ' → ' + eid, p: a9 }); }
      }
    }
  } catch (e) { /* the map is optional */ }

  const head = (await git(['rev-parse', '--abbrev-ref', 'HEAD'])).trim();
  return { repo: name, head, branches, remotes, apps, imports, flows: flows.slice(0, 90), commits };
}

module.exports = { exportHistory, SKIP };
