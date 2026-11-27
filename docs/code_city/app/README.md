# Code City (desktop app)

The 3D city in its own window. Git runs on your computer. No server, no network.

- Open: double-click `CodeCity.bat` (or drag a project folder onto it).
- First time only: `npm install`, then `node node_modules/electron/install.js` (npm blocks that step by default).
- `npm run build` remakes the page from the newest `../code_city_vNN.html`.
- `npm run dist` makes a portable Windows .exe (downloads electron-builder).

What it does
1. Review: "Review changes in the city". The bots print, inspect and carry your real changes; the review shows the real lines.
2. Git: stage (tick a file), commit, switch branch, merge (asks first; aborts cleanly on conflict), discard (saved in a git stash first). It never pushes.
3. Replay: the slider builds the city up to any commit at once, then the bots go on.

Safety: the page can only use the project you picked, through the few actions in `main.js`.
