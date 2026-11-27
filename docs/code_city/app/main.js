/* Code City desktop app: the 3D city in its own window, git run on this computer. No server, no network.
   The page can only act on the one repo you picked, and only through the few git actions below. Nothing here ever pushes. */
const { app, BrowserWindow, ipcMain, dialog, Menu } = require('electron');
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const { exportHistory, SKIP } = require('./history');

let current = null, win = null;
const cfgFile = () => path.join(app.getPath('userData'), 'config.json');
const readCfg = () => { try { return JSON.parse(fs.readFileSync(cfgFile(), 'utf8')); } catch (e) { return {}; } };
const saveCfg = o => { try { fs.mkdirSync(path.dirname(cfgFile()), { recursive: true }); fs.writeFileSync(cfgFile(), JSON.stringify(Object.assign(readCfg(), o))); } catch (e) { /* not important */ } };

function git(repo, args, okFail) {
  return new Promise((resolve, reject) => {
    execFile('git', ['-c', 'core.quotepath=false', '-C', repo].concat(args), { maxBuffer: 1 << 30, encoding: 'utf8', env: Object.assign({}, process.env, { GIT_TERMINAL_PROMPT: '0' }), windowsHide: true }, (err, out, serr) => {
      if (err && !(okFail && err.code === 1 && !String(serr || '').trim())) return reject(new Error(String(serr || err.message).trim() || 'git failed'));
      resolve(out);
    });
  });
}
const need = () => { if (!current) throw new Error('No repo is open. Click Open…'); return current; };
const safePath = p => { if (typeof p !== 'string' || !p || p.includes('\0') || p.startsWith('-') || path.isAbsolute(p) || p.split(/[\\/]/).includes('..')) throw new Error('bad path'); return p; };
const safeBranch = b => { if (typeof b !== 'string' || !/^[\w./+-]+$/.test(b) || b.startsWith('-')) throw new Error('bad branch name'); return b; };

async function openRepo(dir) {
  const top = (await git(dir, ['rev-parse', '--show-toplevel'])).trim();
  current = path.resolve(top); saveCfg({ repo: current }); return current;
}
const handle = (ch, fn) => ipcMain.handle(ch, async (e, ...a) => { try { return { ok: true, v: await fn(...a) }; } catch (x) { return { ok: false, error: String((x && x.message) || x) }; } });

handle('g:cur', async () => {
  if (current) return current;
  const c = readCfg().repo; if (c && fs.existsSync(c)) { try { return await openRepo(c); } catch (e) { /* not a repo any more */ } }
  return null;
});
handle('g:pick', async () => {
  const r = await dialog.showOpenDialog(win, { title: 'Pick a git project folder', properties: ['openDirectory'] });
  if (r.canceled || !r.filePaths.length) return null;
  return openRepo(r.filePaths[0]);
});
handle('g:history', async () => { const repo = need(); return exportHistory(repo, (a, ok) => git(repo, a, ok)); });
handle('g:status', async () => {
  const repo = need();
  const [branch, st, ns] = await Promise.all([git(repo, ['rev-parse', '--abbrev-ref', 'HEAD'], true).catch(() => 'HEAD'), git(repo, ['status', '--porcelain=v1', '-z', '-uall']), git(repo, ['diff', 'HEAD', '--numstat'], true).catch(() => '')]);
  const num = new Map(); ns.split('\n').forEach(l => { const m = l.match(/^(\d+|-)\t(\d+|-)\t(.+)$/); if (m) num.set(m[3], [m[1] === '-' ? 0 : +m[1], m[2] === '-' ? 0 : +m[2]]); });
  const parts = st.split('\0'), files = []; let more = 0;
  for (let i = 0; i < parts.length; i++) {
    const s = parts[i]; if (s.length < 4) continue;
    const x = s[0], y = s[1], p = s.slice(3); if (x === 'R' || x === 'C') i++;
    if (SKIP.test(p)) continue;
    if (files.length >= 400) { more++; continue; }
    const untracked = x === '?', n = num.get(p) || [0, 0];
    if (untracked) { try { const fp = path.join(repo, p), sz = fs.statSync(fp).size; if (sz < 2e6) n[0] = fs.readFileSync(fp, 'utf8').split('\n').length; } catch (e) { /* unreadable */ } }
    files.push({ p, x, y, a: n[0], d: n[1], staged: !untracked && x !== ' ' && x !== '!', untracked });
  }
  return { branch: branch.trim(), files, more };
});
handle('g:diff', async p => {
  const repo = need(); safePath(p);
  const st = await git(repo, ['status', '--porcelain=v1', '--', p], true);
  if (st.startsWith('??')) { const t = fs.readFileSync(path.join(repo, p), 'utf8').split('\n').slice(0, 3000); return '@@ new file @@\n' + t.map(l => '+' + l).join('\n'); }
  return git(repo, ['diff', 'HEAD', '--', p], true).catch(() => git(repo, ['diff', '--cached', '--', p], true));
});
handle('g:stage', async list => { const repo = need(); if (list === 'all') return git(repo, ['add', '-A']); return git(repo, ['add', '--'].concat(list.map(safePath))); });
handle('g:unstage', async list => { const repo = need(); if (list === 'all') return git(repo, ['restore', '--staged', '.']); return git(repo, ['restore', '--staged', '--'].concat(list.map(safePath))); });
handle('g:commit', async msg => { const repo = need(); if (typeof msg !== 'string' || !msg.trim()) throw new Error('empty message'); return git(repo, ['commit', '-m', msg.trim()]); });
handle('g:branches', async () => { const repo = need(); const out = await git(repo, ['for-each-ref', '--format=%(refname:short)', 'refs/heads']); return out.split('\n').filter(Boolean); });
handle('g:switch', async b => { const repo = need(); return git(repo, ['switch', safeBranch(b)]); });
handle('g:merge', async b => { const repo = need(); return git(repo, ['merge', '--no-edit', safeBranch(b)]); });
handle('g:mergeAbort', async () => { const repo = need(); return git(repo, ['merge', '--abort']); });
handle('g:discard', async list => {                       // never loses work: the changes go into a git stash first
  const repo = need(); const msg = 'code-city discard ' + new Date().toISOString();
  await git(repo, ['stash', 'push', '-u', '-m', msg, '--'].concat(list.map(safePath)));
  return 'Saved in git stash "' + msg + '". Bring it back with: git stash pop';
});

function createWindow() {
  win = new BrowserWindow({ width: 1560, height: 940, backgroundColor: '#0b1018', title: 'Code City', autoHideMenuBar: true, webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true } });
  const page = path.join(__dirname, 'renderer', 'index.html');
  if (!fs.existsSync(page)) { win.loadURL('data:text/html,<body style="font:16px system-ui;padding:30px;background:#0b1018;color:#e8eef7">Run <code>npm run build</code> first: the page was not made yet.</body>'); return; }
  win.loadFile(page);
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('file://')) e.preventDefault(); });
}
app.whenReady().then(async () => {
  Menu.setApplicationMenu(null);
  const arg = process.argv.slice(app.isPackaged ? 1 : 2).find(a => !a.startsWith('-') && fs.existsSync(a));
  if (arg) { try { await openRepo(arg); } catch (e) { /* not a repo */ } }
  createWindow();
});
app.on('window-all-closed', () => app.quit());
