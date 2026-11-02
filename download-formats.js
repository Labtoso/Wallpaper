/* Image conversion and lossless ZIP packaging run locally in the browser. */
(function () {
  const formats = { desktop: [2560, 1440], mobile: [1080, 1920] };
  const table = Uint32Array.from({ length: 256 }, (_, value) => {
    let crc = value;
    for (let i = 0; i < 8; i++) crc = crc & 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    return crc >>> 0;
  });
  function crc32(bytes) {
    let crc = 0xffffffff;
    for (const byte of bytes) crc = table[(crc ^ byte) & 255] ^ (crc >>> 8);
    return (crc ^ 0xffffffff) >>> 0;
  }
  function cropRectangle(width, height, targetWidth, targetHeight) {
    if (![width, height, targetWidth, targetHeight].every(n => Number.isFinite(n) && n > 0)) throw new Error('Ungültige Bildgröße.');
    const scale = Math.max(targetWidth / width, targetHeight / height);
    const sw = targetWidth / scale, sh = targetHeight / scale;
    return { x: (width - sw) / 2, y: (height - sh) / 2, width: sw, height: sh };
  }
  async function convert(blob, format) {
    if (format === 'original') return blob;
    if (!formats[format]) throw new Error('Unbekanntes Format.');
    let image, release;
    try {
      image = await createImageBitmap(blob);
      release = () => image.close();
    } catch {
      const url = URL.createObjectURL(blob);
      image = new Image();
      image.src = url;
      release = () => URL.revokeObjectURL(url);
      try { await image.decode(); } catch (error) { release(); throw error; }
    }
    try {
      const [width, height] = formats[format];
      const source = cropRectangle(image.naturalWidth || image.width, image.naturalHeight || image.height, width, height);
      const canvas = document.createElement('canvas');
      canvas.width = width; canvas.height = height;
      const context = canvas.getContext('2d');
      if (!context) throw new Error('Der Browser kann kein Bild erzeugen.');
      context.fillStyle = '#111111'; context.fillRect(0, 0, width, height);
      context.imageSmoothingEnabled = true; context.imageSmoothingQuality = 'high';
      context.drawImage(image, source.x, source.y, source.width, source.height, 0, 0, width, height);
      const result = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', .95));
      canvas.width = canvas.height = 0;
      if (!result) throw new Error('Der Bildausschnitt konnte nicht erzeugt werden.');
      return result;
    } finally { release(); }
  }
  function makeZip(entries) {
    if (entries.length > 65535) throw new Error('Zu viele Bilder in einem Pack.');
    const parts = [], central = [];
    let offset = 0;
    for (const entry of entries) {
      const name = new TextEncoder().encode(entry.name);
      const bytes = entry.bytes;
      if (!name.length || name.length > 65535 || entry.name.split(/[\\/]/).includes('..') || /^[\\/]/.test(entry.name)) throw new Error('Ungültiger Dateiname.');
      if (offset + bytes.length + name.length + 30 > 0xffffffff) throw new Error('Das Pack ist größer als 4 GB. Bitte ein kleineres Pack auswählen.');
      const crc = crc32(bytes);
      const local = new Uint8Array(30), l = new DataView(local.buffer);
      l.setUint32(0, 0x04034b50, true); l.setUint16(4, 20, true); l.setUint16(6, 0x800, true); l.setUint16(12, 0x21, true);
      l.setUint32(14, crc, true); l.setUint32(18, bytes.length, true); l.setUint32(22, bytes.length, true); l.setUint16(26, name.length, true);
      const header = new Uint8Array(46), d = new DataView(header.buffer);
      d.setUint32(0, 0x02014b50, true); d.setUint16(4, 20, true); d.setUint16(6, 20, true); d.setUint16(8, 0x800, true);
      d.setUint16(14, 0x21, true); d.setUint32(16, crc, true); d.setUint32(20, bytes.length, true); d.setUint32(24, bytes.length, true);
      d.setUint16(28, name.length, true); d.setUint32(42, offset, true);
      parts.push(local, name, bytes); central.push(header, name);
      offset += local.length + name.length + bytes.length;
    }
    const start = offset;
    for (const bytes of central) { parts.push(bytes); offset += bytes.length; }
    if (offset > 0xffffffff) throw new Error('Das Pack ist größer als 4 GB.');
    const end = new Uint8Array(22), e = new DataView(end.buffer);
    e.setUint32(0, 0x06054b50, true); e.setUint16(8, entries.length, true); e.setUint16(10, entries.length, true);
    e.setUint32(12, offset - start, true); e.setUint32(16, start, true); parts.push(end);
    return new Blob(parts, { type: 'application/zip' });
  }
  function convertedName(filename, format) {
    return filename.replace(/\.[^.\/]+$/, '') + '-' + format + '.jpg';
  }
  function uniqueName(name, used) {
    let candidate = name, index = 2;
    while (used.has(candidate.toLowerCase())) candidate = name.replace(/\.jpg$/i, '-' + index++ + '.jpg');
    used.add(candidate.toLowerCase());
    return candidate;
  }
  function saveUrl(url, filename) {
    const link = document.createElement('a'); link.href = url; link.download = filename;
    document.body.append(link); link.click(); link.remove();
  }
  function save(blob, filename) {
    const url = URL.createObjectURL(blob);
    globalThis.WallpaperDownloads.saveUrl(url, filename);
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  }
  globalThis.WallpaperDownloads = { formats, cropRectangle, convert, makeZip, convertedName, uniqueName, saveUrl, save };
})();
