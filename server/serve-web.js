'use strict';
const http = require('node:http');
const path = require('node:path');
const { serveStatic } = require('./static-files');
const root = path.resolve(process.env.WEB_ROOT || path.join(__dirname, '../build/web'));
const port = Number(process.env.PORT || 5555);
http.createServer((req, res) => {
  if (/^\/api(?:\/|\?|$)/.test(req.url)) {
    const upstream = http.request({
      hostname: '127.0.0.1', port: Number(process.env.API_PORT || 8080),
      path: req.url, method: req.method, headers: req.headers,
    }, response => { res.writeHead(response.statusCode, response.headers); response.pipe(res); });
    upstream.on('error', () => {
      if (!res.headersSent) res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ message: 'Сервер фотостудии временно недоступен' }));
    });
    req.pipe(upstream); return;
  }
  serveStatic(req, res, root);
}).listen(port, () => console.log(`FocusFrame preview: http://localhost:${port}`));
