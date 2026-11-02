import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { once } from 'node:events';
import { scanAssets, generateCatalog } from '../lib/catalog.mjs';
import { crc32 } from '../lib/zip.mjs';
import { startPreview } from '../preview.mjs';

const project = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const pixel = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0P8AAAAASUVORK5CYII=', 'base64');
async function fixture(t) {
  const root = await mkdtemp(path.join(project, '.test-'));
  t.after(async () => {
    if (path.dirname(root) !== project || !path.basename(root).startsWith('.test-')) throw new Error('Unexpected test directory');
    await rm(root, { recursive: true, force: true });
  });
  await mkdir(path.join(root, 'assets'));
  return root;
}
function entries(zip) {
  const result = [];
  let offset = 0;
  while (zip.readUInt32LE(offset) === 0x04034b50) {
    const size = zip.readUInt32LE(offset + 18);
    const length = zip.readUInt16LE(offset + 26);
    const name = zip.subarray(offset + 30, offset + 30 + length).toString('utf8');
    const data = zip.subarray(offset + 30 + length, offset + 30 + length + size);
    assert.equal(crc32(data), zip.readUInt32LE(offset + 14), 'Archive CRC must match original bytes');
    result.push({ name, data });
    offset += 30 + length + size;
  }
  assert.equal(zip.readUInt32LE(zip.length - 22), 0x06054b50);
  assert.equal(zip.readUInt16LE(zip.length - 12), result.length);
  return result;
}

test('folder names become categories; nested files, spaces and umlauts work; paired thumbnails stay hidden', async t => {
  const root = await fixture(t);
  await mkdir(path.join(root, 'assets', 'Grün & Ruhe', 'Unterordner'), { recursive: true });
  await mkdir(path.join(root, 'assets', 'Leer'));
  await mkdir(path.join(root, 'assets', '.versteckt'));
  for (const name of ['101-full.png', '101-thumb.png', 'Grün & Ruhe/Unterordner/Ein Bild.png', '.versteckt/geheim.png']) {
    await writeFile(path.join(root, 'assets', name), pixel);
  }
  await writeFile(path.join(root, 'assets', 'Grün & Ruhe', 'sources.json'), JSON.stringify({ 'Unterordner/Ein Bild.png': { title:'Ruhe', author:'Test', url:'https://example.com/photo' } }));
  const catalog = await scanAssets(root);
  assert.deepEqual(catalog.packs.map(p => [p.name, p.count]), [['Sammlung',1], ['Grün & Ruhe',1], ['Leer',0]]);
  assert.equal(catalog.photos.length, 2);
  assert.equal(catalog.photos[0].preview, 'assets/101-thumb.png');
  const photo = catalog.photos.find(p => p.packId === 'Grün & Ruhe');
  assert.equal(photo.title, 'Ruhe');
  assert.equal(photo.author, 'Test');
  assert.equal(photo.width, 1);
  assert.equal(photo.height, 1);
  assert.equal(photo.src, 'assets/Gr%C3%BCn%20%26%20Ruhe/Unterordner/Ein%20Bild.png');
});

test('whole collection and individual packs contain only the correct, unmodified originals', async t => {
  const root = await fixture(t);
  await mkdir(path.join(root, 'assets', 'Pack'));
  await writeFile(path.join(root, 'assets', 'eins.png'), pixel);
  await writeFile(path.join(root, 'assets', 'Pack', 'zwei.png'), pixel);
  const output = path.join(root, 'dist');
  const catalog = await generateCatalog(root, output);
  const all = entries(await readFile(path.join(output, catalog.archive)));
  assert.deepEqual(all.map(e => e.name).sort(), ['Pack/zwei.png', 'eins.png']);
  all.forEach(e => assert.deepEqual(e.data, pixel));
  const pack = catalog.packs.find(p => p.id === 'Pack');
  const selected = entries(await readFile(path.join(output, pack.archive)));
  assert.deepEqual(selected.map(e => e.name), ['zwei.png']);
  const before = (await stat(path.join(output, catalog.archive))).mtimeMs;
  const unchanged = await generateCatalog(root, output, catalog.version);
  assert.equal(unchanged.version, catalog.version);
  assert.equal((await stat(path.join(output, catalog.archive))).mtimeMs, before, 'Unchanged packs must not rebuild');
});

test('new folders appear during a running preview; downloads work and private source paths stay inaccessible', async t => {
  const root = await fixture(t);
  const server = startPreview(root, 0);
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const url = 'http://127.0.0.1:' + server.address().port;
  const first = await fetch(url + '/catalog.json').then(r => r.json());
  assert.equal(first.photos.length, 0);
  await mkdir(path.join(root, 'assets', 'Neu #1'));
  await writeFile(path.join(root, 'assets', 'Neu #1', 'Bild.png'), pixel);
  const next = await fetch(url + '/catalog.json').then(r => r.json());
  assert.notEqual(next.version, first.version);
  assert.equal(next.packs[0].name, 'Neu #1');
  const response = await fetch(url + '/' + next.photos[0].src);
  assert.equal(response.status, 200);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), pixel);
  const zip = await fetch(url + '/' + next.packs[0].archive);
  assert.equal(zip.headers.get('content-type'), 'application/zip');
  assert.equal(entries(Buffer.from(await zip.arrayBuffer())).length, 1);
  assert.equal((await fetch(url + '/.git/config')).status, 404);
  assert.equal((await fetch(url + '/photos.json')).status, 404);
  assert.equal((await fetch(url + '/assets/%2e%2e%5cREADME.md')).status, 403);
  await rm(path.join(root, 'assets', 'Neu #1', 'Bild.png'));
  const removed = await fetch(url + '/catalog.json').then(r => r.json());
  assert.equal(removed.packs[0].count, 0);
  assert.equal((await fetch(url + '/' + next.photos[0].src)).status, 404);
});
