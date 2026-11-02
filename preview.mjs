import http from 'node:http';
import { readFile, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { generateCatalog } from './lib/catalog.mjs';
const mime = { '.html':'text/html; charset=utf-8', '.css':'text/css; charset=utf-8', '.js':'application/javascript; charset=utf-8', '.json':'application/json', '.jpg':'image/jpeg', '.jpeg':'image/jpeg', '.png':'image/png', '.webp':'image/webp', '.gif':'image/gif', '.avif':'image/avif', '.svg':'image/svg+xml', '.zip':'application/zip' };
export function startPreview(root, port = 4173) {
  const output = path.join(root, 'dist');
  let catalog, pending;
  async function refresh() {
    if (!pending) pending = generateCatalog(root, output, catalog?.version).then(value => (catalog = value)).finally(() => { pending = null; });
    return pending;
  }
  const server = http.createServer(async (req, res) => {
    try {
      const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\//, '') || 'index.html';
      if (pathname.includes('\\') || pathname.includes('\0') || pathname.split('/').includes('..')) { res.writeHead(403); return res.end(); }
      let file;
      if (pathname === 'catalog.json') {
        const current = await refresh();
        res.setHeader('Content-Type', mime['.json']); res.setHeader('Cache-Control', 'no-store');
        return res.end(JSON.stringify(current));
      }
      if (['index.html', 'gallery.css', 'app.js', 'download-formats.js', 'favicon.svg'].includes(pathname)) {
        file = path.join(root, pathname); res.setHeader('Cache-Control', 'no-cache');
      } else {
        const current = catalog || await refresh();
        if (pathname.startsWith('packs/') && [current.archive, ...current.packs.map(p => p.archive)].includes(pathname)) {
          file = path.join(output, pathname); res.setHeader('Cache-Control', 'no-cache');
        } else if (pathname.startsWith('assets/') && current.photos.some(p => decodeURIComponent(p.src) === pathname || decodeURIComponent(p.preview) === pathname)) {
          file = await realpath(path.join(root, ...pathname.split('/')));
          const assetRoot = await realpath(path.join(root, 'assets'));
          if (!file.startsWith(assetRoot + path.sep)) { res.writeHead(403); return res.end(); }
          res.setHeader('Cache-Control', 'no-cache');
        } else { res.writeHead(404); return res.end('Nicht gefunden'); }
      }
      res.setHeader('Content-Type', mime[path.extname(file).toLowerCase()] || 'application/octet-stream');
      res.setHeader('X-Content-Type-Options', 'nosniff');
      res.end(await readFile(file));
    } catch (error) {
      res.writeHead(error.code === 'ENOENT' ? 404 : 500);
      res.end(error.code === 'ENOENT' ? 'Nicht gefunden' : 'Die Sammlung konnte nicht aktualisiert werden.');
      if (error.code !== 'ENOENT') console.error(error.message);
    }
  });
  server.listen(port, '127.0.0.1', () => console.log('Wallpaper: http://127.0.0.1:' + server.address().port));
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  startPreview(path.dirname(fileURLToPath(import.meta.url)), Number(process.env.PORT) || 4173);
}
