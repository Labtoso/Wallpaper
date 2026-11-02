import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
const root=path.resolve('dist');
const mime={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'application/javascript; charset=utf-8','.json':'application/json','.jpg':'image/jpeg','.svg':'image/svg+xml'};
http.createServer(async(req,res)=>{
  try {
    const file=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));
    if(file!==root&&!file.startsWith(root+path.sep)){res.writeHead(403);return res.end()}
    const target=(await stat(file)).isDirectory()?path.join(file,'index.html'):file;
    res.setHeader('Content-Type',mime[path.extname(target)]||'application/octet-stream');
    res.end(await readFile(target));
  }catch{res.writeHead(404);res.end('Nicht gefunden')}
}).listen(4173,'127.0.0.1',()=>console.log('Wallpaper: http://127.0.0.1:4173'));
