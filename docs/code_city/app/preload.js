const { contextBridge, ipcRenderer } = require('electron');
const call = ch => async (...a) => { const r = await ipcRenderer.invoke(ch, ...a); if (!r.ok) throw new Error(r.error); return r.v; };
contextBridge.exposeInMainWorld('cityGit', {
  currentRepo: call('g:cur'), pickRepo: call('g:pick'), history: call('g:history'),
  status: call('g:status'), diff: call('g:diff'), stage: call('g:stage'), unstage: call('g:unstage'),
  commit: call('g:commit'), branches: call('g:branches'), switchTo: call('g:switch'),
  merge: call('g:merge'), mergeAbort: call('g:mergeAbort'), discard: call('g:discard')
});
