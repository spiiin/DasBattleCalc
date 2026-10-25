"use strict";
// The page side: starts the wasm module and puts the files the user picks
// into its memory file system at the paths the app reads (--state, --rom).
const $ = id => document.getElementById(id);
const STATE = '/files/battle.State', ROM = '/files/rom.zip';
let runtime, errors = '', have = {state: false, rom: false};

function log(text) { console.log(text); }
function err(text) { console.error(text); errors += text + '\n'; }
function show(text) { $('status').style.display = text ? '' : 'none'; $('status').textContent = text || ''; }

async function put(input, path, key) {
  const file = input.files[0];
  if (!file || !runtime) return;
  runtime.FS.writeFile(path, new Uint8Array(await file.arrayBuffer()));
  have[key] = file.name;
  $('files').textContent = [have.state, have.rom].filter(x => x).join(' · ');
  // FFT (PSX) and War of the Lions need the state only; FFTA / FFTA2 the
  // ROM too (the app picks the game by the state, else by the ROM)
  if (have.state) runtime._web_reload();
}

createBattleCalc({
  canvas: $('canvas'), print: log, printErr: err,
  locateFile: path => path + '?v=' + Date.now(),   // .wasm and .data of one build
  onAbort(what) { show('Ошибка: ' + what + '\n' + errors); },
  onSessionEnd(code) { show(code ? 'Ошибка\n' + errors : 'Остановлено'); }
}).then(module => {
  runtime = module;
  runtime.FS.mkdirTree('/files');
  show('');
  $('canvas').focus();
  // page options: ?ui-scale=1.6 -> --ui-scale 1.6
  const args = ['--state', STATE, '--rom', ROM];
  for (const [k, v] of new URLSearchParams(location.search)) args.push('--' + k, v);
  try { runtime.callMain(args); }
  catch (e) { if (e !== 'unwind') throw e; }
  // SDL's fill-document mode hides every other element: bring ours back
  document.body.appendChild($('bar'));
  document.body.appendChild($('status'));
}).catch(e => show('Ошибка: ' + e + '\n' + (e.stack || '') + errors));

// While a button is held the canvas keeps the pointer: released over our
// file bar (it lies on top of the canvas) the button never came up for
// SDL - a dragged unit stuck to the cursor, the UI waited for a release.
$('canvas').addEventListener('pointerdown', e => $('canvas').setPointerCapture(e.pointerId));

// Ctrl+V: SDL's clipboard lives in the page only, and the browser one can
// only be read asynchronously - read it here and type the text into the
// app (web_paste); SDL does not see this Ctrl+V.
// e.code: the V key in any layout (e.key is 'м' in the Russian one); any
// focus but our file inputs (after a permission prompt it can be <body>).
document.addEventListener('keydown', e => {
  if (!runtime || !(e.ctrlKey || e.metaKey) || e.code !== 'KeyV' || e.target.tagName === 'INPUT') return;
  if (!navigator.clipboard || !navigator.clipboard.readText) return;
  e.preventDefault();
  e.stopImmediatePropagation();
  navigator.clipboard.readText()
    .then(text => { if (text) runtime.ccall('web_paste', null, ['string'], [text]); })
    .catch(err => console.warn('paste: ' + err))
    .finally(() => $('canvas').focus());
}, true);

$('state').onchange = () => put($('state'), STATE, 'state');
$('rom').onchange = () => put($('rom'), ROM, 'rom');
