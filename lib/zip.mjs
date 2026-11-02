import { open, readFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

const table = Uint32Array.from({ length: 256 }, (_, value) => {
  let crc = value;
  for (let i = 0; i < 8; i++) crc = crc & 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  return crc >>> 0;
});
export function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = table[(crc ^ byte) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

// Images are already compressed. Store them losslessly with UTF-8 filenames.
export async function writeZip(filename, entries) {
  if (entries.length > 65535) throw new Error('Ein Pack darf maximal 65535 Bilder enthalten.');
  await mkdir(path.dirname(filename), { recursive: true });
  const file = await open(filename, 'w');
  const central = [];
  let offset = 0;
  async function write(buffer) {
    let done = 0;
    while (done < buffer.length) {
      const { bytesWritten } = await file.write(buffer, done, buffer.length - done, offset + done);
      if (!bytesWritten) throw new Error('ZIP konnte nicht geschrieben werden.');
      done += bytesWritten;
    }
    offset += buffer.length;
  }
  try {
    for (const entry of entries) {
      const name = Buffer.from(entry.name.replaceAll('\\', '/'));
      if (!name.length || name.length > 65535 || entry.name.split(/[\\/]/).some(p => p === '..') || /^[\\/]/.test(entry.name)) {
        throw new Error('Ungültiger Dateiname im Pack.');
      }
      const bytes = await readFile(entry.file);
      if (offset + bytes.length > 0xffffffff) throw new Error('ZIP-Packs über 4 GB werden nicht unterstützt.');
      const crc = crc32(bytes);
      const header = Buffer.alloc(30);
      header.writeUInt32LE(0x04034b50); header.writeUInt16LE(20, 4); header.writeUInt16LE(0x800, 6);
      header.writeUInt16LE(0x21, 12); header.writeUInt32LE(crc, 14);
      header.writeUInt32LE(bytes.length, 18); header.writeUInt32LE(bytes.length, 22); header.writeUInt16LE(name.length, 26);
      const directory = Buffer.alloc(46);
      directory.writeUInt32LE(0x02014b50); directory.writeUInt16LE(20, 4); directory.writeUInt16LE(20, 6);
      directory.writeUInt16LE(0x800, 8); directory.writeUInt16LE(0x21, 14);
      directory.writeUInt32LE(crc, 16); directory.writeUInt32LE(bytes.length, 20); directory.writeUInt32LE(bytes.length, 24);
      directory.writeUInt16LE(name.length, 28); directory.writeUInt32LE(offset, 42);
      central.push(directory, name);
      await write(header); await write(name); await write(bytes);
    }
    const centralOffset = offset;
    for (const bytes of central) await write(bytes);
    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054b50); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
    end.writeUInt32LE(offset - centralOffset, 12); end.writeUInt32LE(centralOffset, 16);
    await write(end);
  } finally { await file.close(); }
}
