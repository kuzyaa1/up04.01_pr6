'use strict';
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const root = path.resolve(process.argv[2] || 'build/web');
if (!fs.existsSync(path.join(root, 'index.html'))) throw new Error('Not a Flutter web output');
const bootstrap = fs.readFileSync(path.join(root, 'flutter_bootstrap.js'), 'utf8');
const needsSkwasm = /"renderer"\s*:\s*"skwasm"/.test(bootstrap);
let removed = 0;
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) { walk(file); continue; }
    const unused = entry.name.endsWith('.symbols') ||
      (!needsSkwasm && entry.name.startsWith('skwasm'));
    if (unused) { removed += fs.statSync(file).size; fs.unlinkSync(file); continue; }
    if (/\.(js|mjs|wasm|json|css|html|svg|ttf)$/.test(file)) {
      const source = fs.readFileSync(file);
      const gzip = zlib.gzipSync(source, { level: 9 });
      if (gzip.length < source.length) fs.writeFileSync(file + '.gz', gzip);
    }
  }
}
walk(root);
console.log(JSON.stringify({ removedBytes: removed, needsSkwasm }));
