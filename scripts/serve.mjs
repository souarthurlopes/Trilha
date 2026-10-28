import {createServer} from 'node:http';
import {readFile,stat,realpath} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../dist/',import.meta.url));
const host=process.env.HOST||'127.0.0.1',port=Number(process.env.PORT||4173);
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.json':'application/json','.webmanifest':'application/manifest+json','.sql':'text/plain; charset=utf-8'};
const server=createServer(async(req,res)=>{
 if(!['GET','HEAD'].includes(req.method)){res.writeHead(405,{Allow:'GET, HEAD'});res.end();return}
 try{
  const pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
  const requested=resolve(root,'.'+(pathname==='/'?'/index.html':pathname));
  const allowed=path=>path===resolve(root)||path.startsWith(resolve(root)+sep);
  if(!allowed(requested)){res.writeHead(403);res.end('Acesso negado');return}
  const path=await realpath(requested);
  if(!allowed(path)){res.writeHead(403);res.end('Acesso negado');return}
  const info=await stat(path);if(!info.isFile()){res.writeHead(404);res.end('Arquivo não encontrado');return}
  res.writeHead(200,{'Content-Type':types[extname(path)]||'application/octet-stream','Content-Length':info.size,'Cache-Control':'no-cache','X-Content-Type-Options':'nosniff'});
  res.end(req.method==='HEAD'?undefined:await readFile(path));
 }catch(error){res.writeHead(error instanceof URIError?400:404);res.end('Arquivo não encontrado')}
});
server.on('error',error=>{console.error('Não foi possível iniciar o servidor:',error.message);process.exitCode=1});
server.listen(port,host,()=>console.log(`Trilha Apostólica: http://${host}:${port}`));
