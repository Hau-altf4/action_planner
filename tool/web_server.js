import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, resolve, sep } from 'node:path';

const root = resolve(process.cwd(), 'build', 'web');
const port = Number(process.env.WEB_PORT || 8080);
const mimeTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
};

if (!existsSync(resolve(root, 'index.html'))) {
  console.error('Chưa có build/web. Hãy chạy: flutter build web --release');
  process.exit(1);
}

createServer((req, res) => {
  let pathname = '/';
  try {
    pathname = decodeURIComponent(new URL(req.url || '/', 'http://localhost').pathname);
  } catch {
    res.writeHead(400).end('Bad request');
    return;
  }

  // Thay thế service worker cũ bằng worker tự gỡ để các máy đã từng mở bản
  // PWA không tiếp tục giữ giao diện cũ trong cache.
  if (pathname === '/flutter_service_worker.js') {
    res.writeHead(200, {
      'Content-Type': 'text/javascript; charset=utf-8',
      'Cache-Control': 'no-store, max-age=0',
      'Service-Worker-Allowed': '/',
    });
    res.end(`
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil((async () => {
  const keys = await caches.keys();
  await Promise.all(keys.map(key => caches.delete(key)));
  await self.registration.unregister();
  const clients = await self.clients.matchAll({ type: 'window' });
  await Promise.all(clients.map(client => client.navigate(client.url)));
})()));
self.addEventListener('fetch', event => event.respondWith(fetch(event.request)));
`);
    return;
  }

  let filePath = resolve(root, `.${pathname}`);
  if (filePath !== root && !filePath.startsWith(`${root}${sep}`)) {
    res.writeHead(403).end('Forbidden');
    return;
  }
  if (existsSync(filePath) && statSync(filePath).isDirectory()) {
    filePath = resolve(filePath, 'index.html');
  }
  if (!existsSync(filePath) || !statSync(filePath).isFile()) {
    filePath = resolve(root, 'index.html');
  }

  const extension = extname(filePath).toLowerCase();
  const cacheable = ['.ico', '.png', '.svg'].includes(extension);
  res.writeHead(200, {
    'Content-Type': mimeTypes[extension] || 'application/octet-stream',
    'Cache-Control': cacheable ? 'public, max-age=3600' : 'no-cache',
  });
  createReadStream(filePath).pipe(res);
}).listen(port, '0.0.0.0', () => {
  console.log(`Action Planner Web: http://0.0.0.0:${port}`);
});
