export function isPublicSupabaseKey(key){
 if(typeof key!=='string')return false;
 if(/^sb_publishable_[A-Za-z0-9_-]+$/.test(key))return true;
 if(key.startsWith('sb_secret_'))return false;
 try{const parts=key.split('.');if(parts.length!==3)return false;const payload=JSON.parse(atob(parts[1].replace(/-/g,'+').replace(/_/g,'/')));return payload.role==='anon'}catch{return false}
}
export function normalizePublicConfig(value){
 if(!value||typeof value!=='object'||typeof value.url!=='string'||typeof value.key!=='string')throw Error('Informe a URL e a chave pública do Supabase.');
 let url;try{url=new URL(value.url.trim())}catch{throw Error('A URL do Supabase deve ser HTTPS, no formato https://projeto.supabase.co.')}
 if(url.protocol!=='https:'||!url.hostname.endsWith('.supabase.co')||url.pathname!=='/'||url.search||url.hash||url.username||url.password||url.port)throw Error('A URL do Supabase deve ser HTTPS, no formato https://projeto.supabase.co.');
 const key=value.key.trim();if(!isPublicSupabaseKey(key))throw Error('Use somente a chave Publishable ou anon. Chaves secretas e service_role não podem ser publicadas no aplicativo.');
 return {url:url.origin,key};
}
