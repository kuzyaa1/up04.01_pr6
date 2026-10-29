'use strict';
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const root = path.resolve(process.argv[2] || 'build/web');
let raw = 0, gzip = 0, disk = 0, files = 0;
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) { walk(file); continue; }
    const data = fs.readFileSync(file); disk += data.length;
    if (entry.name.endsWith('.gz')) continue;
    raw += data.length; gzip += Math.min(data.length, zlib.gzipSync(data).length); files++;
  }
}
walk(root);
const main = fs.readFileSync(path.join(root, 'main.dart.js'));
console.log(JSON.stringify({ directory: root, files, rawBytes: raw,
  gzipTransferBytes: gzip, diskBytesIncludingGzip: disk,
  mainJsBytes: main.length, mainJsGzipBytes: zlib.gzipSync(main).length }, null, 2));
