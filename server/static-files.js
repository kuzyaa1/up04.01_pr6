'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { pipeline } = require('node:stream');
const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json',
  '.css': 'text/css', '.wasm': 'application/wasm', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ttf': 'font/ttf',
  '.woff2': 'font/woff2', '.ico': 'image/x-icon',
};

/** Serve a Flutter release, including GoRouter deep links, from a bounded root. */
function serveStatic(req, res, rootDir) {
  if (!['GET', 'HEAD'].includes(req.method)) {
    res.writeHead(405, { Allow: 'GET, HEAD' }); res.end(); return;
  }
  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, 'http://preview').pathname); }
  catch { res.writeHead(400); res.end(); return; }
  const root = path.resolve(rootDir);
  let file = path.resolve(root, '.' + pathname);
  if (pathname.includes('\0') || (file !== root && !file.startsWith(root + path.sep))) {
    res.writeHead(403); res.end(); return;
  }
  const exists = p => fs.existsSync(p) && fs.statSync(p).isFile();
  if (!exists(file)) {
    if (path.extname(pathname)) { res.writeHead(404); res.end(); return; }
    file = path.join(root, 'index.html');
  }
  if (!exists(file)) { res.writeHead(503); res.end('Flutter release is not built'); return; }
  const headers = {
    'Content-Type': types[path.extname(file)] || 'application/octet-stream',
    'Cache-Control': 'no-cache',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'credentialless',
    'Vary': 'Accept-Encoding',
  };
  if (/\bgzip\b/.test(req.headers['accept-encoding'] || '') && exists(file + '.gz')) {
    file += '.gz'; headers['Content-Encoding'] = 'gzip';
  }
  headers['Content-Length'] = fs.statSync(file).size;
  res.writeHead(200, headers);
  if (req.method === 'HEAD') { res.end(); return; }
  pipeline(fs.createReadStream(file), res, err => { if (err) res.destroy(); });
}
module.exports = { serveStatic };
