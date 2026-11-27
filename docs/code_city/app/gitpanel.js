/* The git panel of the desktop app. Loaded BEFORE the page script. Everything here talks to real git through window.cityGit (preload.js). */
(function () {
  const G = window.cityGit;
  if (!G) { window.cityLoad = () => fetch('sample_history.json').then(r => { if (!r.ok) throw new Error('missing'); return r.json(); }); return; }
  const $ = id => document.getElementById(id);
  const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  let repo = null, base = null, st = null, lastSig = '', busy = false, brSig = '';

  window.cityLoad = async () => {
    repo = await G.currentRepo(); if (!repo) repo = await G.pickRepo(); if (!repo) throw new Error('no repo');
    window.__liveOn = false; base = await G.history(); window.__baseRaw = base; return base;
  };

  const css = document.createElement('style');
  css.textContent = `#gitPanel{position:fixed;right:10px;top:54px;width:330px;max-height:calc(100vh - 70px);overflow:auto;z-index:20;background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:9px 11px;font-size:12.5px;box-shadow:0 6px 24px rgba(0,0,0,.35)}
#gitPanel .gh{display:flex;justify-content:space-between;align-items:center;gap:8px}
#gitPanel .gr{display:flex;gap:8px;align-items:center;justify-content:space-between;margin-top:7px}
#gitPanel select{max-width:160px}
#gitPanel .gl{margin-top:6px;border:1px solid var(--line);border-radius:7px;max-height:210px;overflow:auto}
#gitPanel .gi{display:flex;gap:6px;align-items:center;padding:3px 6px;border-bottom:1px solid var(--line)}
#gitPanel .gi:last-child{border-bottom:0}
#gitPanel .gi .n{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;direction:rtl;text-align:left}
#gitPanel .gi .l{width:14px;font-weight:700;text-align:center}
#gitPanel .gi .a{color:#4ade80}#gitPanel .gi .d{color:#ff6b6b}
#gitPanel .gi button{padding:0 5px;line-height:1.2}
#gitPanel textarea{width:100%;margin-top:7px;min-height:44px;resize:vertical;box-sizing:border-box;background:transparent;color:inherit;border:1px solid var(--line);border-radius:7px;padding:5px 7px;font:inherit}
#gitPanel .gm{margin-top:7px;color:var(--muted);white-space:pre-wrap;overflow-wrap:anywhere}
#gitPanel .gm.bad{color:#ff7b7b}
#gitPanel input[type=range]{width:100%;margin:6px 0 0}
#gitPanel .hint{color:var(--muted);font-size:11.5px}
.gpdiff{margin:0;padding:10px 14px;font:12.5px/1.5 ui-monospace,Consolas,monospace;white-space:pre;overflow:auto}
.gpdiff .p{background:rgba(74,222,128,.14)}.gpdiff .m{background:rgba(255,77,77,.14)}.gpdiff .h{color:var(--muted)}`;
  document.head.appendChild(css);

  const panel = document.createElement('div'); panel.id = 'gitPanel';
  panel.innerHTML = `<div class="gh"><b id="gpRepo">no project</b><span><button id="gpOpen" class="btn sm">Open…</button> <button id="gpMin" class="btn sm" title="Fold the panel">–</button></span></div>
<div id="gpBody">
 <div class="gr"><span>Branch</span><span><select id="gpBr" aria-label="Branches"></select> <button id="gpSwitch" class="btn sm">Switch</button></span></div>
 <div class="gr"><b>Changes <span id="gpCount" class="hint"></span></b><span><button id="gpStageAll" class="btn sm">Stage all</button> <button id="gpUnstageAll" class="btn sm">Unstage all</button></span></div>
 <div id="gpList" class="gl"></div>
 <div class="gr"><button id="gpReview" class="btn primary sm" title="The bots print, inspect and carry your real changes. Real lines are shown in the review.">Review changes in the city</button><span class="hint" id="gpTicks"></span></div>
 <textarea id="gpMsg" placeholder="Commit message"></textarea>
 <div class="gr"><button id="gpCommit" class="btn sm">Commit staged files</button><span class="hint">never pushes</span></div>
 <div class="gr"><span>Merge into <b id="gpCur"></b></span><span><select id="gpMrg" aria-label="Merge this branch"></select> <button id="gpMerge" class="btn sm">Merge</button></span></div>
 <div class="gr"><b>Replay from a commit</b><span class="hint" id="gpFromLbl"></span></div>
 <input id="gpFrom" type="range" min="1" max="1" value="1" aria-label="Replay start">
 <div class="gr"><span class="hint">the city is built up to there at once, then the bots go on</span><button id="gpReplay" class="btn sm">Replay</button></div>
 <div id="gpOut" class="gm"></div>
</div>`;

  const say = (t, bad) => { const o = $('gpOut'); o.textContent = t || ''; o.className = 'gm' + (bad ? ' bad' : ''); };
  const act = async fn => { if (busy) return; busy = true; try { await fn(); } catch (e) { say(e.message, true); } finally { busy = false; refresh(true); } };
  const nBase = () => (window.__baseRaw ? window.__baseRaw.commits.length : 0);

  function render() {
    if (!st) return;
    const staged = st.files.filter(f => f.staged).length;
    $('gpCount').textContent = '(' + st.files.length + (st.more ? ' + ' + st.more + ' more' : '') + ')';
    $('gpTicks').textContent = staged + ' staged';
    $('gpCur').textContent = st.branch;
    $('gpList').innerHTML = st.files.length ? st.files.map((f, i) => '<div class="gi"><input type="checkbox" data-i="' + i + '"' + (f.staged ? ' checked' : '') + ' title="ticked = staged for the next commit"><span class="l" style="color:' + (f.x === 'U' || f.y === 'U' ? '#ff6b6b' : f.untracked ? '#35e0ff' : f.x === 'D' || f.y === 'D' ? '#ff6b6b' : '#ffb02e') + '">' + (f.untracked ? 'N' : (f.x !== ' ' ? f.x : f.y)) + '</span><span class="n" title="' + esc(f.p) + '">&lrm;' + esc(f.p) + '</span><span class="a">+' + f.a + '</span><span class="d">−' + f.d + '</span><button class="btn sm" data-x="' + i + '" title="Discard this change (saved in a git stash first)">✕</button></div>').join('') : '<div class="gi hint">No changes. Everything is committed.</div>';
    $('gpList').querySelectorAll('input[type=checkbox]').forEach(cb => { cb.onchange = () => { const f = st.files[+cb.dataset.i]; act(async () => { if (cb.checked) await G.stage([f.p]); else await G.unstage([f.p]); }); }; });
    $('gpList').querySelectorAll('button[data-x]').forEach(b => { b.onclick = () => { const f = st.files[+b.dataset.x]; if (!confirm('Discard the changes of ' + f.p + '?\n\nThey are saved in a git stash first, so you can bring them back with: git stash pop')) return; act(async () => { say(await G.discard([f.p])); }); }; });
    const n = nBase(), s = $('gpFrom'); if (+s.max !== n && n) { s.max = n; s.value = n; showFrom(); }
  }
  async function refresh(force) {
    if (!repo || busy && !force) return;
    try {
      st = await G.status(); const sig = JSON.stringify(st) + nBase(); if (sig !== lastSig) { lastSig = sig; render(); }
      const bs = await G.branches(), bsig = bs.join('|') + '@' + st.branch;
      if (bsig !== brSig) { brSig = bsig; $('gpBr').innerHTML = bs.map(b => '<option' + (b === st.branch ? ' selected' : '') + '>' + esc(b) + '</option>').join(''); $('gpMrg').innerHTML = bs.filter(b => b !== st.branch).map(b => '<option>' + esc(b) + '</option>').join(''); }
    } catch (e) { say(e.message, true); }
  }
  async function reloadCity() { base = await G.history(); window.__baseRaw = base; window.__liveOn = false; rpLoadRaw(base); rpBegin(true); lastSig = ''; }
  function showFrom() {
    const raw = window.__baseRaw, k = +$('gpFrom').value; if (!raw) return;
    const c = raw.commits[k - 1]; $('gpFromLbl').textContent = c ? '#' + k + ' · ' + c.h.slice(0, 7) + ' · ' + new Date(c.t * 1000).toLocaleDateString() + ' · ' + String(c.m).slice(0, 30) : '';
  }
  async function reviewWorking() {
    const fresh = await G.status(); if (!fresh.files.length) { say('No changes to review.'); return; }
    const b = window.__baseRaw; if (!b) { say('The history is not loaded yet.', true); return; }
    const headH = b.branches[b.head]; if (!headH) { say('You are not on a branch (detached HEAD). Switch to a branch first.', true); return; }
    const f = fresh.files.map(x => [x.untracked || x.x === 'A' ? 'A' : (x.x === 'D' || x.y === 'D') ? 'D' : 'M', x.p, x.a, x.d]);
    const ps = { h: 'working'.padEnd(40, '0'), p: [headH], t: Math.floor(Date.now() / 1000), a: 'you', m: 'Working changes (not committed yet)', f };
    const raw2 = Object.assign({}, b, { commits: b.commits.concat([ps]), branches: Object.assign({}, b.branches, { [b.head]: ps.h }) });
    window.__liveOn = true; rpLoadRaw(raw2);
    const sel = document.getElementById('rpBr0'); if ([...sel.options].some(o => o.value === b.head)) sel.value = b.head;
    document.getElementById('rpFrom').value = 1; document.getElementById('rpTo').value = raw2.commits.length;
    rpBegin(true); if (!RP.on) return;
    say('The bots take your ' + f.length + ' changed file' + (f.length === 1 ? '' : 's') + ' one by one. Press "Next commit" on the card to start.');
    rpSeek(Math.max(0, RP.evs.length - 1));
  }
  window.cityShowDiff = async c => {                       // in the code review of a live change: the REAL lines
    if (!window.__liveOn) return;
    try {
      const t = await G.diff(c.path), box = $('code'); if (!box) return;
      box.innerHTML = '<pre class="gpdiff">' + (t || '(no text changes)').split('\n').map(l => '<div class="' + (l.startsWith('+') && !l.startsWith('+++') ? 'p' : l.startsWith('-') && !l.startsWith('---') ? 'm' : l.startsWith('@@') || l.startsWith('diff') || l.startsWith('index') ? 'h' : '') + '">' + esc(l) + ' </div>').join('') + '</pre>';
    } catch (e) { /* the simulated lines stay */ }
  };

  window.addEventListener('load', () => {
    document.body.appendChild(panel);
    try { if (localStorage.getItem('gpMin') === '1') $('gpBody').hidden = true; } catch (e) { /* no storage */ }
    $('gpMin').onclick = () => { const h = $('gpBody'); h.hidden = !h.hidden; try { localStorage.setItem('gpMin', h.hidden ? '1' : '0'); } catch (e) { /* no storage */ } };
    $('gpOpen').onclick = () => act(async () => { const r = await G.pickRepo(); if (!r) return; repo = r; $('gpRepo').textContent = r.split(/[\\/]/).pop(); await reloadCity(); say('Opened ' + r); });
    $('gpSwitch').onclick = () => act(async () => { const b = $('gpBr').value; if (b === st.branch) return; if (!confirm('Switch to branch ' + b + '?')) return; await G.switchTo(b); await reloadCity(); say('Now on ' + b); });
    $('gpStageAll').onclick = () => act(() => G.stage('all'));
    $('gpUnstageAll').onclick = () => act(() => G.unstage('all'));
    $('gpReview').onclick = () => act(reviewWorking);
    $('gpCommit').onclick = () => act(async () => {
      const msg = $('gpMsg').value.trim(), n = st.files.filter(f => f.staged).length;
      if (!n) { say('Nothing is staged. Tick the files you want in this commit.', true); return; }
      if (!msg) { say('Write a commit message first.', true); return; }
      if (!confirm('Commit ' + n + ' staged file' + (n === 1 ? '' : 's') + ' on ' + st.branch + '?\n\n' + msg)) return;
      await G.commit(msg); $('gpMsg').value = ''; await reloadCity(); say('Committed.');
    });
    $('gpMerge').onclick = () => act(async () => {
      const b = $('gpMrg').value; if (!b) return;
      if (!confirm('Merge ' + b + ' into ' + st.branch + '?')) return;
      try { await G.merge(b); } catch (e) {
        say(e.message, true);
        if (confirm('The merge stopped:\n\n' + e.message.slice(0, 400) + '\n\nAbort it so nothing is left half done?')) { try { await G.mergeAbort(); say('Merge aborted. Nothing changed.'); } catch (x) { say(x.message, true); } }
        return;
      }
      await reloadCity(); say('Merged ' + b + ' into ' + st.branch + '. The city shows it.');
    });
    $('gpFrom').oninput = showFrom;
    $('gpReplay').onclick = () => act(async () => {
      const raw = window.__baseRaw; if (!raw) return; const k = +$('gpFrom').value; window.__liveOn = false; rpLoadRaw(raw);
      document.getElementById('rpFrom').value = 1; document.getElementById('rpTo').value = raw.commits.length;
      const sel = document.getElementById('rpBr0'); if ([...sel.options].some(o => o.value === raw.head)) sel.value = raw.head;
      rpBegin(true); if (!RP.on) return;
      const j = Math.max(0, RP.evs.findIndex(e => e.idx >= k - 1)); rpSeek(j);
      say('The city is built up to commit #' + k + '. Press "Next commit" to go on.');
    });
    G.currentRepo().then(r => { if (r) { repo = r; $('gpRepo').textContent = r.split(/[\\/]/).pop(); } refresh(true); });
    setInterval(() => { if (!document.hidden) refresh(); }, 3000);
    window.addEventListener('focus', () => refresh());
  });
})();
