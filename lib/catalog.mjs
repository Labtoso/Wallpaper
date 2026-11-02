import { readdir, stat, readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { dimensions, imagePattern } from './images.mjs';
import { writeZip } from './zip.mjs';

const collator = new Intl.Collator('de', { numeric: true, sensitivity: 'base' });
const encoded = value => value.split('/').map(encodeURIComponent).join('/');
async function json(filename, fallback = {}) {
  try { return JSON.parse(await readFile(filename, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return fallback; throw new Error(`Ungültige Metadaten: ${filename}`, { cause: error }); }
}

export async function scanAssets(root) {
  const assets = path.join(root, 'assets');
  const files = [], folders = new Set(), metadata = new Map();
  async function walk(directory, relative = '') {
    const items = (await readdir(directory, { withFileTypes: true })).sort((a, b) => collator.compare(a.name, b.name));
    for (const item of items) {
      if (item.name.startsWith('.') || item.isSymbolicLink()) continue;
      const rel = relative ? `${relative}/${item.name}` : item.name;
      const full = path.join(directory, item.name);
      if (item.isDirectory()) {
        folders.add(rel.split('/')[0]);
        await walk(full, rel);
      } else if (item.isFile() && (imagePattern.test(item.name) || item.name === 'sources.json')) {
        const info = await stat(full);
        if (item.name === 'sources.json') metadata.set(relative, await json(full));
        files.push({ relative: rel, full, bytes: info.size, modified: info.mtimeMs, image: imagePattern.test(item.name) });
      }
    }
  }
  await mkdir(assets, { recursive: true });
  await walk(assets);
  const legacy = await json(path.join(root, 'photos.json'), []);
  const legacyById = new Map(legacy.map(p => [String(p.id), p]));
  const allPaths = new Set(files.map(f => f.relative));
  const originals = files.filter(f => f.image && !(/-thumb\./i.test(f.relative) && allPaths.has(f.relative.replace(/-thumb\./i, '-full.'))));
  const revision = createHash('sha256').update(JSON.stringify([files.map(f => [f.relative, f.bytes, f.modified]), [...folders], legacy])).digest('hex');
  const packs = [...folders].sort(collator.compare).map(name => ({ id: name, name }));
  if (originals.some(f => !f.relative.includes('/'))) packs.unshift({ id: '', name: 'Sammlung' });
  const photos = [];
  for (const file of originals) {
    const basename = path.basename(file.relative);
    const legacyId = !file.relative.includes('/') ? basename.match(/^(\d+)-full\./)?.[1] : null;
    const old = legacyById.get(legacyId) || {};
    const folder = path.posix.dirname(file.relative);
    const source = { ...(metadata.get(file.relative.includes('/') ? file.relative.split('/')[0] : '')?.[file.relative.split('/').slice(1).join('/')] || {}), ...(metadata.get(folder === '.' ? '' : folder)?.[basename] || {}) };
    const thumb = file.relative.replace(/-full(?=\.)/i, '-thumb');
    const title = source.title || old.title || path.parse(basename).name.replace(/-full$/i, '').replace(/[_-]+/g, ' ');
    photos.push({
      id: file.relative, legacyId, packId: file.relative.includes('/') ? file.relative.split('/')[0] : '',
      title, alt: source.alt || old.alt || title, src: `assets/${encoded(file.relative)}`,
      preview: `assets/${encoded(allPaths.has(thumb) ? thumb : file.relative)}`,
      filename: basename, bytes: file.bytes, ...await dimensions(file.full),
      author: source.author || old.author || '', url: source.url || old.url || '',
      license: source.license || (old.url ? 'Unsplash' : ''),
      licenseUrl: source.licenseUrl || (old.url ? 'https://unsplash.com/license' : ''),
    });
  }
  for (const pack of packs) {
    pack.count = photos.filter(p => p.packId === pack.id).length;
    pack.archive = `packs/${pack.id ? createHash('sha256').update(pack.id).digest('hex').slice(0, 16) : 'sammlung'}.zip`;
  }
  return { version: revision, packs, photos, archive: 'packs/alle-wallpaper.zip' };
}

export async function generateCatalog(root, output, previousVersion) {
  const catalog = await scanAssets(root);
  if (catalog.version === previousVersion) return catalog;
  await mkdir(output, { recursive: true });
  const entries = catalog.photos.map(p => ({ file: path.join(root, 'assets', ...p.id.split('/')), name: p.id }));
  for (const pack of catalog.packs) {
    const selected = catalog.photos.filter(p => p.packId === pack.id);
    await writeZip(path.join(output, pack.archive), selected.map(p => ({
      file: path.join(root, 'assets', ...p.id.split('/')),
      name: pack.id ? p.id.slice(pack.id.length + 1) : p.id,
    })));
  }
  await writeZip(path.join(output, catalog.archive), entries);
  await writeFile(path.join(output, 'catalog.json'), JSON.stringify(catalog, null, 2));
  return catalog;
}
