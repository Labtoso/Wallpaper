import { mkdir, copyFile, cp, rename } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { generateCatalog } from './lib/catalog.mjs';
const root = path.dirname(fileURLToPath(import.meta.url));
const output = path.join(root, 'dist');
const staging = path.join(root, '.build-' + process.pid + '-' + Date.now());
await mkdir(staging);
for (const file of ['index.html', 'gallery.css', 'app.js', 'favicon.svg']) {
  await copyFile(path.join(root, file), path.join(staging, file));
}
await cp(path.join(root, 'assets'), path.join(staging, 'assets'), {
  recursive: true,
  filter: source => !path.relative(path.join(root, 'assets'), source).split(path.sep).some(part => part.startsWith('.'))
});
const catalog = await generateCatalog(root, staging);
await mkdir(path.join(root, '_old', 'builds'), { recursive: true });
try { await rename(output, path.join(root, '_old', 'builds', 'dist-' + Date.now())); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
await rename(staging, output);
console.log(catalog.photos.length + ' Bilder, ' + catalog.packs.length + ' Packs → dist/');
