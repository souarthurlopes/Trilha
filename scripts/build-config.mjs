import {writeFile} from 'node:fs/promises';
import {normalizePublicConfig} from '../dist/config-utils.js';
const url=process.env.PUBLIC_SUPABASE_URL?.trim();
const key=(process.env.PUBLIC_SUPABASE_KEY||process.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY||process.env.PUBLIC_SUPABASE_ANON_KEY)?.trim();
try{
 if(Boolean(url)!==Boolean(key))throw Error('Configure as duas variáveis de build: PUBLIC_SUPABASE_URL e PUBLIC_SUPABASE_KEY.');
 const config=url?normalizePublicConfig({url,key}):null;
 const json=JSON.stringify(config).replaceAll('<','\\u003c').replaceAll('\u2028','\\u2028').replaceAll('\u2029','\\u2029');
 await writeFile(new URL('../dist/config.js',import.meta.url),'// Gerado no build. Somente configuração pública do Supabase.\nglobalThis.TRILHA_PUBLIC_CONFIG = '+json+';\n');
 console.log(config?'Conexão pública do Supabase preparada para todos os dispositivos.':'Sem conexão padrão de publicação; mantida a configuração local por navegador.');
}catch(error){console.error('Configuração da publicação inválida:',error.message);process.exitCode=1}
