import { open } from 'node:fs/promises';

export const imagePattern = /\.(jpe?g|png|webp|gif|avif|svg)$/i;

export async function dimensions(filename) {
  const file = await open(filename, 'r');
  try {
    const bytes = Buffer.alloc(256 * 1024);
    const { bytesRead } = await file.read(bytes, 0, bytes.length, 0);
    const b = bytes.subarray(0, bytesRead);
    if (b.length < 10) return {};
    if (b.subarray(1, 4).toString() === 'PNG' && b.length >= 24) {
      return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
    }
    if (b.subarray(0, 3).toString() === 'GIF') {
      return { width: b.readUInt16LE(6), height: b.readUInt16LE(8) };
    }
    if (b[0] === 0xff && b[1] === 0xd8) {
      let at = 2;
      while (at + 9 < b.length) {
        if (b[at] !== 0xff) { at++; continue; }
        const marker = b[at + 1];
        if (marker === 0xff) { at++; continue; }
        if (marker === 0xd9 || marker === 0xda) break;
        if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) { at += 2; continue; }
        const length = b.readUInt16BE(at + 2);
        if (length < 2) break;
        if ([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker)) {
          return { height: b.readUInt16BE(at + 5), width: b.readUInt16BE(at + 7) };
        }
        at += length + 2;
      }
    }
    if (b.subarray(0, 4).toString() === 'RIFF' && b.subarray(8, 12).toString() === 'WEBP') {
      const type = b.subarray(12, 16).toString();
      if (type === 'VP8X' && b.length >= 30) return { width: 1 + b.readUIntLE(24, 3), height: 1 + b.readUIntLE(27, 3) };
      if (type === 'VP8 ' && b.length >= 30) return { width: b.readUInt16LE(26) & 0x3fff, height: b.readUInt16LE(28) & 0x3fff };
      if (type === 'VP8L' && b.length >= 25) {
        const bits = b.readUInt32LE(21);
        return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
      }
    }
    if (/\.svg$/i.test(filename)) {
      const svg = b.toString('utf8');
      const box = svg.match(/viewBox\s*=\s*["']\s*[-\d.]+[ ,]+[-\d.]+[ ,]+([\d.]+)[ ,]+([\d.]+)/i);
      if (box) return { width: Number(box[1]), height: Number(box[2]) };
      const width = svg.match(/\bwidth=["']([\d.]+)(?:px)?["']/i);
      const height = svg.match(/\bheight=["']([\d.]+)(?:px)?["']/i);
      if (width && height) return { width: Number(width[1]), height: Number(height[1]) };
    }
    return {};
  } finally { await file.close(); }
}
