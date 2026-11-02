const $ = selector => document.querySelector(selector);
const icons = {
  bookmark: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3h12v18l-6-4-6 4z"/></svg>',
  download: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/></svg>'
};
const state = { catalog: null, filter: 'all', packId: '', saved: new Set(), selected: null, viewerIds: [], zoomed: false };
let loading = false;
function updateCopyrightYear() { $('#copyright-year').textContent = new Date().getFullYear(); }
updateCopyrightYear();
setInterval(updateCopyrightYear, 60000);
try { state.saved = new Set(JSON.parse(localStorage.getItem('wallpaper-saved') || localStorage.getItem('still-saved') || '[]')); } catch {}

function element(tag, className, text) {
  const el = document.createElement(tag);
  if (className) el.className = className;
  if (text !== undefined) el.textContent = text;
  return el;
}
function safeUrl(value) {
  try { const url = new URL(value); return ['https:', 'http:'].includes(url.protocol) ? url.href : null; }
  catch { return null; }
}
function size(photo) {
  return photo.width && photo.height ? photo.width + ' × ' + photo.height : formatBytes(photo.bytes);
}
function formatBytes(bytes) {
  return bytes >= 1024 * 1024 ? (bytes / 1024 / 1024).toFixed(1).replace('.', ',') + ' MB' : Math.max(1, Math.round(bytes / 1024)) + ' KB';
}
function downloadLink(photo, className = 'icon-button') {
  const a = element('a', className);
  a.href = photo.src;
  a.download = photo.filename;
  a.setAttribute('aria-label', photo.title + ' herunterladen');
  a.title = 'Original herunterladen';
  a.innerHTML = icons.download;
  return a;
}
function getVisible() {
  if (!state.catalog) return [];
  return state.catalog.photos.filter(photo => state.filter === 'all' ||
    (state.filter === 'saved' ? state.saved.has(photo.id) : photo.packId === state.packId));
}
function toggleSave(id) {
  if (state.saved.has(id)) state.saved.delete(id); else state.saved.add(id);
  try { localStorage.setItem('wallpaper-saved', JSON.stringify([...state.saved])); } catch {}
  if (state.filter === 'saved') render(); else {
    document.querySelectorAll('[data-save-id]').forEach(button => updateSave(button, button.dataset.saveId));
    const count = $('#saved-count');
    if (count) count.textContent = state.catalog.photos.filter(p => state.saved.has(p.id)).length;
  }
  if (state.selected) updateSave($('#viewer-save'), state.selected);
}
function updateSave(button, id) {
  const saved = state.saved.has(id);
  button.setAttribute('aria-pressed', String(saved));
  button.setAttribute('aria-label', saved ? 'Aus Merkliste entfernen' : 'Bild merken');
  button.title = saved ? 'Aus Merkliste entfernen' : 'Merken';
  button.innerHTML = icons.bookmark;
}
function renderFilters() {
  const filters = $('#filters');
  filters.replaceChildren();
  function add(label, count, type, id = '') {
    const button = element('button', '', label);
    const counter = element('span', '', count);
    if (type === 'saved') counter.id = 'saved-count';
    button.append(counter);
    button.dataset.filter = type;
    if (type === 'pack') button.dataset.packId = id;
    button.setAttribute('aria-pressed', String(state.filter === type && (type !== 'pack' || state.packId === id)));
    button.onclick = () => { state.filter = type; state.packId = id; render(); };
    filters.append(button);
  }
  add('Alle', state.catalog.photos.length, 'all');
  if (state.catalog.packs.some(p => p.id !== '')) {
    state.catalog.packs.forEach(pack => add(pack.name, pack.count, 'pack', pack.id));
  }
  add('Merkliste', state.catalog.photos.filter(p => state.saved.has(p.id)).length, 'saved');
}
function card(photo) {
  const article = element('article', 'card');
  const open = element('button', 'image-button');
  open.setAttribute('aria-label', photo.title + ' ansehen');
  open.onclick = () => openViewer(photo.id);
  const image = element('img');
  image.src = photo.preview; image.alt = photo.alt; image.loading = 'lazy'; image.decoding = 'async';
  if (photo.width && photo.height) { image.width = photo.width; image.height = photo.height; }
  open.append(image);
  const info = element('div', 'card-info');
  const description = element('div');
  description.append(element('h3', 'card-title', photo.title), element('p', 'card-meta', size(photo)));
  const actions = element('div', 'card-actions');
  const save = element('button', 'icon-button save-button');
  save.dataset.saveId = photo.id;
  updateSave(save, photo.id);
  save.onclick = () => toggleSave(photo.id);
  actions.append(save, downloadLink(photo));
  info.append(description, actions);
  article.append(open, info);
  return article;
}
function render() {
  const photos = getVisible(), catalog = state.catalog;
  if (!catalog) return;
  renderFilters();
  const selectedPack = catalog.packs.find(p => p.id === state.packId);
  $('#collection-title').textContent = state.filter === 'saved' ? 'Merkliste' : state.filter === 'pack' ? selectedPack.name : 'Alle Wallpaper';
  $('#collection-count').textContent = photos.length + (photos.length === 1 ? ' Bild' : ' Bilder');
  const download = $('#pack-download');
  download.hidden = state.filter === 'saved' || !photos.length;
  download.href = state.filter === 'pack' ? selectedPack.archive : catalog.archive;
  download.download = (state.filter === 'pack' ? selectedPack.name : 'Alle Wallpaper') + '.zip';
  download.replaceChildren(document.createTextNode(state.filter === 'pack' ? 'Pack herunterladen ' : 'Alle herunterladen '), element('span', '', '↓'));
  const gallery = $('#gallery');
  gallery.replaceChildren();
  const groups = state.filter === 'saved' ? [{ id: 'saved', name: 'Merkliste', count: photos.length }] :
    catalog.packs.filter(pack => state.filter === 'all' || pack.id === state.packId);
  for (const pack of groups) {
    const items = state.filter === 'saved' ? photos : photos.filter(p => p.packId === pack.id);
    const section = element('section', 'pack-section');
    if (state.filter === 'all' && groups.length > 1) {
      const heading = element('div', 'pack-heading');
      const title = element('h2', '', pack.name); title.append(element('span', '', pack.count));
      heading.append(title);
      if (items.length) {
        const a = element('a', '', 'Pack herunterladen ↓'); a.href = pack.archive; a.download = pack.name + '.zip'; heading.append(a);
      }
      section.append(heading);
    }
    const grid = element('div', 'image-grid');
    for (const photo of items) grid.append(card(photo));
    if (!items.length && state.filter !== 'saved') grid.append(element('p', 'empty', 'In diesem Ordner sind noch keine Bilder.'));
    section.append(grid); gallery.append(section);
  }
  if (!photos.length && state.filter === 'saved') {
    const empty = element('div', 'empty'); empty.append(element('h3', '', 'Noch nichts gemerkt.'), element('p', '', 'Mit dem Lesezeichen am Bild fügst du es hier hinzu.')); gallery.append(empty);
  } else if (!groups.length) gallery.append(element('p', 'empty', 'Noch keine Wallpaper vorhanden.'));
  $('#visible-count').textContent = photos.length + ' Bilder';
  $('#result-status').textContent = photos.length + ' Bilder angezeigt';
  gallery.setAttribute('aria-busy', 'false');
  $('#shuffle').disabled = !photos.length;
}
function renderSources() {
  const known = state.catalog.photos.filter(p => safeUrl(p.url));
  $('#source-count').textContent = '(' + known.length + ')';
  const links = $('#source-links'); links.replaceChildren();
  if (known.some(p => p.legacyId)) {
    for (const [title, url] of [['Unsplash', 'https://unsplash.com'], ['Lorem Picsum', 'https://picsum.photos'], ['Unsplash-Lizenz', 'https://unsplash.com/license']]) {
      const a = element('a', '', title + ' ↗'); a.href = url; a.target = '_blank'; a.rel = 'noopener noreferrer'; links.append(a);
    }
  } else links.append(element('span', '', 'Quellenangaben beim jeweiligen Bild.'));
  const list = $('#source-list'); list.replaceChildren();
  for (const photo of known) {
    const item = element('li'), a = element('a', '', photo.title + (photo.author ? ' — ' + photo.author : '') + ' ↗');
    a.href = safeUrl(photo.url); a.target = '_blank'; a.rel = 'noopener noreferrer'; item.append(a); list.append(item);
  }
}
function openViewer(id) {
  state.viewerIds = getVisible().map(p => p.id);
  showPhoto(id);
  renderThumbs();
  if (!$('#viewer').open) $('#viewer').showModal();
}
function showPhoto(id) {
  const photo = state.catalog.photos.find(p => p.id === id);
  if (!photo) return;
  state.selected = id;
  setZoom(false);
  $('#viewer-title').textContent = photo.title;
  $('#viewer-counter').textContent = (state.viewerIds.indexOf(id) + 1) + ' / ' + state.viewerIds.length;
  $('#viewer-size').textContent = size(photo) + ' · ' + formatBytes(photo.bytes);
  const image = $('#viewer-image');
  $('#viewer-zoom').disabled = true;
  $('#viewer-message').textContent = 'Bild wird geladen …';
  image.hidden = true;
  image.onload = () => {
    $('#viewer-zoom').disabled = false;
    image.hidden = false; $('#viewer-message').textContent = '';
    if (!photo.width || !photo.height) $('#viewer-size').textContent = image.naturalWidth + ' × ' + image.naturalHeight + ' · ' + formatBytes(photo.bytes);
  };
  image.onerror = () => { $('#viewer-message').textContent = 'Das Bild konnte nicht geladen werden.'; };
  image.alt = photo.alt; image.src = photo.src;
  $('#viewer-download').href = photo.src; $('#viewer-download').download = photo.filename;
  $('#viewer-download').setAttribute('aria-label', photo.title + ' herunterladen');
  updateSave($('#viewer-save'), id);
  const credit = $('#viewer-credit'); credit.replaceChildren();
  if (photo.author) credit.append(element('span', '', photo.author));
  for (const [label, url] of [['Quelle ↗', photo.url], [photo.license ? photo.license + ' ↗' : 'Lizenz ↗', photo.licenseUrl]]) {
    const safe = safeUrl(url); if (!safe) continue;
    const a = element('a', '', label); a.href = safe; a.target = '_blank'; a.rel = 'noopener noreferrer'; credit.append(a);
  }
  $('#viewer-prev').disabled = $('#viewer-next').disabled = state.viewerIds.length < 2;
  document.querySelectorAll('#viewer-thumbs button').forEach(button => {
    button.setAttribute('aria-current', String(button.dataset.photoId === id));
    if (button.dataset.photoId === id) button.scrollIntoView({ block: 'nearest', inline: 'center' });
  });
}
function renderThumbs() {
  const thumbs = $('#viewer-thumbs'); thumbs.replaceChildren();
  for (const id of state.viewerIds) {
    const photo = state.catalog.photos.find(p => p.id === id); if (!photo) continue;
    const button = element('button'); button.dataset.photoId = id;
    button.setAttribute('aria-label', photo.title + ' ansehen'); button.setAttribute('aria-current', String(id === state.selected));
    const img = element('img'); img.src = photo.preview; img.alt = ''; img.loading = 'lazy';
    button.append(img); button.onclick = () => showPhoto(id); thumbs.append(button);
  }
}
function navigate(direction) {
  if (!state.viewerIds.length) return;
  const index = state.viewerIds.indexOf(state.selected);
  showPhoto(state.viewerIds[(index + direction + state.viewerIds.length) % state.viewerIds.length]);
}
function setZoom(zoomed) {
  state.zoomed = zoomed;
  const canvas = $('#viewer-canvas'), image = $('#viewer-image');
  canvas.classList.toggle('zoomed', zoomed);
  $('#viewer-zoom').setAttribute('aria-pressed', String(zoomed));
  $('#viewer-zoom').textContent = zoomed ? 'Einpassen' : '100 %';
  $('#viewer-zoom').title = zoomed ? 'Ganzes Bild einpassen' : 'Originalgröße anzeigen';
  image.style.width = zoomed ? image.naturalWidth + 'px' : '';
  image.style.height = zoomed ? image.naturalHeight + 'px' : '';
  if (zoomed) requestAnimationFrame(() => {
    canvas.scrollLeft = Math.max(0, (canvas.scrollWidth - canvas.clientWidth) / 2);
    canvas.scrollTop = Math.max(0, (canvas.scrollHeight - canvas.clientHeight) / 2);
  });
}
$('#viewer-close').onclick = () => $('#viewer').close();
$('#viewer').addEventListener('close', () => { setZoom(false); state.selected = null; });
$('#viewer-save').onclick = () => toggleSave(state.selected);
$('#viewer-prev').onclick = () => navigate(-1);
$('#viewer-next').onclick = () => navigate(1);
$('#viewer-zoom').onclick = () => setZoom(!state.zoomed);
$('#shuffle').onclick = () => {
  const photos = getVisible(); if (photos.length) openViewer(photos[Math.floor(Math.random() * photos.length)].id);
};
document.addEventListener('keydown', event => {
  if (!$('#viewer').open || event.altKey || event.ctrlKey || event.metaKey) return;
  if (['ArrowLeft', 'ArrowRight'].includes(event.key)) { event.preventDefault(); navigate(event.key === 'ArrowLeft' ? -1 : 1); }
});
let gesture, suppressClick = false;
const canvas = $('#viewer-canvas');
canvas.addEventListener('pointerdown', event => {
  if (event.button !== 0) return;
  suppressClick = false;
  gesture = { x: event.clientX, y: event.clientY, left: canvas.scrollLeft, top: canvas.scrollTop, moved: false };
});
canvas.addEventListener('pointermove', event => {
  if (!gesture || !state.zoomed) return;
  const dx = event.clientX - gesture.x, dy = event.clientY - gesture.y;
  if (Math.abs(dx) + Math.abs(dy) > 5) {
    gesture.moved = true;
    canvas.classList.add('dragging');
    if (!canvas.hasPointerCapture(event.pointerId)) canvas.setPointerCapture(event.pointerId);
  }
  canvas.scrollLeft = gesture.left - dx; canvas.scrollTop = gesture.top - dy;
});
canvas.addEventListener('pointerup', event => {
  if (!gesture) return;
  const dx = event.clientX - gesture.x, dy = event.clientY - gesture.y;
  suppressClick = gesture.moved;
  if (!state.zoomed && Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) { navigate(dx > 0 ? -1 : 1); suppressClick = true; }
  gesture = null; canvas.classList.remove('dragging');
});
canvas.addEventListener('pointercancel', () => { gesture = null; canvas.classList.remove('dragging'); });
canvas.addEventListener('click', event => {
  if (suppressClick) { suppressClick = false; return; }
  if (event.target === $('#viewer-image') || (state.zoomed && event.target === canvas)) setZoom(!state.zoomed);
});

async function loadCatalog() {
  if (loading) return;
  loading = true;
  try {
    const response = await fetch('catalog.json', { cache: 'no-store' });
    if (!response.ok) throw new Error('Katalog nicht erreichbar');
    const catalog = await response.json();
    if (catalog.version === state.catalog?.version) return;
    for (const photo of catalog.photos) if (photo.legacyId && state.saved.has(photo.legacyId)) {
      state.saved.delete(photo.legacyId); state.saved.add(photo.id);
    }
    state.catalog = catalog;
    if (state.filter === 'pack' && !catalog.packs.some(p => p.id === state.packId)) state.filter = 'all';
    render(); renderSources();
    if ($('#viewer').open) {
      state.viewerIds = getVisible().map(p => p.id);
      if (state.viewerIds.includes(state.selected)) { showPhoto(state.selected); renderThumbs(); }
      else $('#viewer').close();
    }
  } catch {
    if (!state.catalog) {
      const error = element('div', 'empty');
      error.append(element('p', '', 'Die Sammlung konnte nicht geladen werden.'));
      const retry = element('button', 'text-button', 'Erneut versuchen'); retry.onclick = loadCatalog; error.append(retry);
      $('#gallery').replaceChildren(error); $('#gallery').setAttribute('aria-busy', 'false');
    }
  } finally { loading = false; }
}
loadCatalog();
setInterval(() => { if (!document.hidden) loadCatalog(); }, 8000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) loadCatalog(); });
