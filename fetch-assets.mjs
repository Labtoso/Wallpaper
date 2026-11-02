import { mkdir, writeFile } from 'node:fs/promises';
const ids = [1018,1015,1016,1040,1043,1067,1002,1036,1022,1076,1080,1049];
await mkdir('assets',{recursive:true});
const photos = [];
for (let i=0;i<ids.length;i+=3) {
  await Promise.all(ids.slice(i,i+3).map(async id=>{
    const info = await fetch(`https://picsum.photos/id/${id}/info`).then(r=>{if(!r.ok)throw Error(`${id}: ${r.status}`);return r.json()});
    for (const [suffix,url] of [['full',info.download_url],['thumb',`https://picsum.photos/id/${id}/1000/700`]]) {
      const r=await fetch(url);if(!r.ok)throw Error(`${url}: ${r.status}`);
      await writeFile(`assets/${id}-${suffix}.jpg`,Buffer.from(await r.arrayBuffer()));
    }
    photos.push(info); console.log(`Downloaded ${id}: ${info.author} (${info.width}x${info.height})`);
  }));
}
await writeFile('photos.json',JSON.stringify(ids.map(id=>photos.find(p=>p.id===String(id))),null,2));
