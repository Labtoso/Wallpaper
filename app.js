const $ = selector => document.querySelector(selector);
const state = {photos:[],filter:'Alle',format:'desktop',selected:null,saved:new Set()};
try{state.saved=new Set(JSON.parse(localStorage.getItem('still-saved')||'[]'))}catch{}
const editorial = [
  [1018,'Grüne Weite','Natur','Ein gewundener Pfad entlang grüner Felsen unter tiefen Wolken'],
  [1022,'Nordlicht','Natur','Grüne Polarlichter über den Silhouetten dunkler Tannen'],
  [1076,'Fassade','Architektur','Ein geometrisches Backsteingebäude von unten betrachtet'],
  [1002,'Von oben','Details','Blaues Meer und goldene Küstenstrukturen in einer NASA-Aufnahme'],
  [1067,'Abend in der Stadt','Architektur','Eine Skyline im warmen Licht der untergehenden Sonne'],
  [1015,'Fjord','Natur','Ein tiefblauer Fjord zwischen hellen Felsplateaus'],
  [1049,'Gezeiten','Natur','Ein dunkler Fels spiegelt sich im stillen Wasser am Strand'],
  [1043,'Am Wasser','Natur','Ein klarer See vor bewaldeten Felsen und Bergen'],
  [1016,'Roter Fels','Natur','Warme Abendsonne auf roten Felsformationen'],
  [1036,'Schneelager','Natur','Gelbe Zelte in einer verschneiten Berglandschaft'],
  [1040,'Das Schloss','Architektur','Ein helles Schloss vor bewaldeten Berghängen'],
  [1080,'Rot','Details','Nahaufnahme reifer roter Erdbeeren']
];
function persist(){try{localStorage.setItem('still-saved',JSON.stringify([...state.saved]))}catch{}$('#saved-count').textContent=state.saved.size}
function toggleSave(id){state.saved.has(id)?state.saved.delete(id):state.saved.add(id);persist();render();if(state.selected)updateSaveButton()}
function render(){
  const visible=state.photos.filter(p=>state.filter==='Alle'||(state.filter==='Merkliste'?state.saved.has(p.id):p.category===state.filter));
  const gallery=$('#gallery');gallery.replaceChildren();gallery.classList.toggle('mobile-view',state.format==='mobile');
  visible.forEach(p=>{
    const card=document.createElement('article');card.className='card';
    const open=document.createElement('button');open.className='image-button';open.setAttribute('aria-label',`${p.title} ansehen`);open.onclick=()=>openDetail(p);
    const img=document.createElement('img');img.src=`assets/${p.id}-thumb.jpg`;img.alt=p.alt;img.loading=p.number<=3?'eager':'lazy';img.width=1000;img.height=700;open.append(img);
    const info=document.createElement('div');info.className='card-info';
    const text=document.createElement('div');
    const title=document.createElement('h3');title.className='card-title';const number=document.createElement('span');number.textContent=String(p.number).padStart(3,'0');title.append(number,document.createTextNode(p.title));
    const meta=document.createElement('p');meta.className='card-meta';meta.textContent=`${p.width} × ${p.height} · ${p.category}`;text.append(title,meta);
    const save=document.createElement('button');save.className='save';save.textContent=state.saved.has(p.id)?'♥':'♡';save.setAttribute('aria-label',`${p.title} ${state.saved.has(p.id)?'aus Merkliste entfernen':'merken'}`);save.setAttribute('aria-pressed',String(state.saved.has(p.id)));save.onclick=()=>toggleSave(p.id);info.append(text,save);card.append(open,info);gallery.append(card);
  });
  if(!visible.length){const empty=document.createElement('div');empty.className='empty';const title=document.createElement('h3');title.textContent='Platz für deine Favoriten.';const p=document.createElement('p');p.textContent='Mit dem Herz am Bild stellst du deine eigene Sammlung zusammen.';empty.append(title,p);gallery.append(empty)}
  $('#visible-count').textContent=`${visible.length} Motive · Originalauflösung`;$('#result-status').textContent=`${visible.length} Motive angezeigt`;gallery.setAttribute('aria-busy','false');
}
function updateSaveButton(){$('#detail-save').textContent=state.saved.has(state.selected.id)?'Aus der Merkliste entfernen −':'Zur Merkliste hinzufügen +'}
function openDetail(p){
  state.selected=p;$('#detail-number').textContent=`WALLPAPER / ${String(p.number).padStart(3,'0')}`;$('#detail-title').textContent=p.title;$('#detail-category').textContent=p.category.toUpperCase();$('#detail-author').textContent=`Fotografie von ${p.author}`;$('#detail-size').textContent=`${p.width} × ${p.height} px`;$('#source-link').href=p.url;$('#detail-img').src=`assets/${p.id}-full.jpg`;$('#detail-img').alt=p.alt;$('#download-format').value=state.format==='mobile'?'mobile':'original';$('#download-status').textContent='';updateSaveButton();updateCrop();$('#detail').showModal();
}
function updateCrop(){const mode=$('#download-format').value;const container=$('.detail-image');container.classList.toggle('is-crop',mode!=='original');container.classList.toggle('mobile-crop',mode==='mobile');container.classList.toggle('desktop-crop',mode==='desktop')}
document.querySelectorAll('[data-filter]').forEach(button=>button.onclick=()=>{state.filter=button.dataset.filter;document.querySelectorAll('[data-filter]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));render()});
document.querySelectorAll('[data-format]').forEach(button=>button.onclick=()=>{state.format=button.dataset.format;document.querySelectorAll('[data-format]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));render()});
$('#shuffle').onclick=()=>{if(state.photos.length)openDetail(state.photos[Math.floor(Math.random()*state.photos.length)])};
$('#close-detail').onclick=()=>$('#detail').close();
$('#detail').addEventListener('click',e=>{if(e.target===$('#detail')){const r=e.target.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)e.target.close()}});
$('#detail-save').onclick=()=>toggleSave(state.selected.id);$('#download-format').onchange=updateCrop;
function saveBlob(blob,filename){const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=filename;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000)}
$('#download').onclick=async()=>{
  const button=$('#download'),p=state.selected,mode=$('#download-format').value;button.disabled=true;$('#download-status').textContent='Dein Wallpaper wird vorbereitet …';
  try{
    const response=await fetch(`assets/${p.id}-full.jpg`);if(!response.ok)throw Error('Bilddatei nicht erreichbar');let blob=await response.blob();
    if(mode!=='original'){
      const image=await createImageBitmap(blob);const [w,h]=mode==='mobile'?[1080,1920]:[2560,1440];const canvas=document.createElement('canvas');canvas.width=w;canvas.height=h;const ctx=canvas.getContext('2d');if(!ctx)throw Error('Bildformat wird nicht unterstützt');const scale=Math.max(w/image.width,h/image.height);const sw=w/scale,sh=h/scale;ctx.drawImage(image,(image.width-sw)/2,(image.height-sh)/2,sw,sh,0,0,w,h);image.close();blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',.95));if(!blob)throw Error('Ausschnitt konnte nicht erzeugt werden');
    }
    saveBlob(blob,`Wallpaper-${String(p.number).padStart(3,'0')}-${mode}.jpg`);$('#download-status').textContent='Dein Download wurde gestartet.';
  }catch(error){$('#download-status').textContent=`Der Download hat nicht geklappt. ${error.message}. Bitte erneut versuchen.`}finally{button.disabled=false}
};
async function init(){try{const response=await fetch('photos.json');if(!response.ok)throw Error('Fotodaten fehlen');const data=await response.json();state.photos=editorial.map(([id,title,category,alt],index)=>{const info=data.find(p=>p.id===String(id));if(!info)throw Error(`Motiv ${id} fehlt`);return{...info,title,category,alt,number:index+1}});persist();render()}catch{$('#gallery').setAttribute('aria-busy','false');$('#gallery').textContent='Die Sammlung konnte nicht geladen werden. Bitte lade die Seite erneut.'}}
init();
