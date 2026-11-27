/* Makes renderer/index.html from the newest ../code_city_vNN.html, so the app always has the latest city.
   Run:  node build_app.js   (npm start does it for you) */
const fs = require('fs');
const path = require('path');

const dir = path.join(__dirname, '..');
const pages = fs.readdirSync(dir).map(f => ({ f, m: f.match(/^code_city_v(\d+)\.html$/) })).filter(x => x.m).sort((a, b) => +b.m[1] - +a.m[1]);
if (!pages.length) throw new Error('No code_city_vNN.html found in ' + dir);
let s = fs.readFileSync(path.join(dir, pages[0].f), 'utf8');
const rep = (re, to, what) => { if (!re.test(s)) throw new Error('page changed, cannot patch: ' + what); s = s.replace(re, () => to); };

/* Three.js comes from this folder, not from the internet; the git panel loads before the page script */
rep(/<script[^>]*three\.min\.js[^>]*><\/script>/, '<script src="three.min.js"></script><script src="gitpanel.js"></script>', 'three.js tag');
/* the page loads its history through the app (git on this computer), not from a file */
s = s.split("fetch('sample_history.json').then(r => { if (!r.ok) throw new Error('missing'); return r.json(); })").join('window.cityLoad()');
if (/fetch\('sample_history\.json'\)/.test(s)) throw new Error('a history fetch was not replaced');
/* the code review shows the real lines of a live change */
rep(/await present\(c, i, ctx\); if \(r !== RP\.run\) return false;/, 'await present(c, i, ctx); if (r !== RP.run) return false; if (window.cityShowDiff) await window.cityShowDiff(c);', 'review hook');
rep(/el\.head\.insertAdjacentHTML\('beforeend', ' <span class="where">· the lines are simulated[^']*'\);/, "if (!window.__liveOn) el.head.insertAdjacentHTML('beforeend', ' <span class=\"where\">· the lines are simulated: git history keeps the size of a change, not its text</span>');", 'simulated note');

const out = path.join(__dirname, 'renderer');
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'index.html'), s);
fs.copyFileSync(path.join(__dirname, 'gitpanel.js'), path.join(out, 'gitpanel.js'));
const three = path.join(__dirname, 'node_modules', 'three', 'build', 'three.min.js');
if (!fs.existsSync(three)) throw new Error('Run "npm install" first (it brings Three.js and Electron).');
fs.copyFileSync(three, path.join(out, 'three.min.js'));
console.log('Built renderer/index.html from ' + pages[0].f);
