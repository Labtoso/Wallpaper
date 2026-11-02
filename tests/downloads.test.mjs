import test from 'node:test';
import assert from 'node:assert/strict';
import '../download-formats.js';
import { crc32 } from '../lib/zip.mjs';

const tools = globalThis.WallpaperDownloads;
test('desktop and mobile crops are centered and preserve the target aspect ratio', () => {
  const desktop = tools.cropRectangle(1080, 1920, 2560, 1440);
  assert.equal(desktop.width, 1080);
  assert.equal(desktop.height, 607.5);
  assert.equal(desktop.x, 0);
  assert.equal(desktop.y, 656.25);
  const mobile = tools.cropRectangle(1600, 900, 1080, 1920);
  assert.equal(mobile.height, 900);
  assert.equal(mobile.width, 506.25);
  assert.equal(mobile.x, 546.875);
  assert.equal(mobile.y, 0);
  assert.throws(() => tools.cropRectangle(0, 20, 10, 10));
});
test('original downloads are never re-encoded and duplicate output names stay distinct', async () => {
  const original = new Blob(['untouched']);
  assert.equal(await tools.convert(original, 'original'), original);
  const used = new Set();
  assert.equal(tools.uniqueName(tools.convertedName('Pack/Bild.png', 'desktop'), used), 'Pack/Bild-desktop.jpg');
  assert.equal(tools.uniqueName(tools.convertedName('Pack/Bild.jpg', 'desktop'), used), 'Pack/Bild-desktop-2.jpg');
  assert.equal(tools.uniqueName(tools.convertedName('Pack/bild.webp', 'desktop'), used), 'Pack/bild-desktop-3.jpg');
});
test('browser-created ZIPs preserve UTF-8 names, bytes and checksums', async () => {
  const files = [{ name: 'Grün & Ruhe/Bild-mobile.jpg', bytes: new Uint8Array([1, 2, 3, 4]) }, { name: 'Andere/Bild-mobile.jpg', bytes: new Uint8Array([7, 8, 9]) }];
  const zip = await tools.makeZip(files).arrayBuffer();
  const data = new Uint8Array(zip), view = new DataView(zip);
  let offset = 0;
  for (const file of files) {
    assert.equal(view.getUint32(offset, true), 0x04034b50);
    const length = view.getUint16(offset + 26, true);
    assert.equal(new TextDecoder().decode(data.subarray(offset + 30, offset + 30 + length)), file.name);
    assert.equal(view.getUint32(offset + 14, true), crc32(file.bytes));
    assert.deepEqual(data.subarray(offset + 30 + length, offset + 30 + length + file.bytes.length), file.bytes);
    offset += 30 + length + file.bytes.length;
  }
  assert.equal(view.getUint32(data.length - 22, true), 0x06054b50);
  assert.equal(view.getUint16(data.length - 12, true), files.length);
  assert.throws(() => tools.makeZip([{ name: '../invalid', bytes: new Uint8Array() }]));
});
