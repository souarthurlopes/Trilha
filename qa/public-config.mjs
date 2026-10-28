import assert from 'node:assert/strict';
import {mkdtemp,mkdir,copyFile,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';import {join} from 'node:path';import {spawnSync} from 'node:child_process';
import {normalizePublicConfig,isPublicSupabaseKey} from '../dist/config-utils.js';
const key='sb_publishable_test_public_config';
assert.deepEqual(normalizePublicConfig({url:' https://test.supabase.co/ ',key:' '+key+' '}),{url:'https://test.supabase.co',key});
const jwt=role=>'header.'+Buffer.from(JSON.stringify({role})).toString('base64url')+'.signature';
assert.equal(isPublicSupabaseKey(jwt('anon')),true);assert.equal(isPublicSupabaseKey(jwt('service_role')),false);
for(const value of [{url:'http://test.supabase.co',key},{url:'https://test.supabase.co.evil.example',key},{url:'https://test.supabase.co/path',key},{url:'https://user:password@test.supabase.co',key},{url:'https://test.supabase.co',key:'sb_secret_do_not_publish'},{url:'https://test.supabase.co',key:jwt('service_role')}])assert.throws(()=>normalizePublicConfig(value));
const root=await mkdtemp(join(tmpdir(),'trilha-public-config-'));try{
 await mkdir(join(root,'scripts'));await mkdir(join(root,'dist'));await writeFile(join(root,'package.json'),'{"type":"module"}');await copyFile('scripts/build-config.mjs',join(root,'scripts/build-config.mjs'));await copyFile('dist/config-utils.js',join(root,'dist/config-utils.js'));
 const env={...process.env};for(const name of ['PUBLIC_SUPABASE_URL','PUBLIC_SUPABASE_KEY','PUBLIC_SUPABASE_PUBLISHABLE_KEY','PUBLIC_SUPABASE_ANON_KEY'])delete env[name];
 const build=extra=>spawnSync(process.execPath,[join(root,'scripts/build-config.mjs')],{env:{...env,...extra},encoding:'utf8'});
 assert.equal(build({}).status,0);assert.match(await readFile(join(root,'dist/config.js'),'utf8'),/TRILHA_PUBLIC_CONFIG = null/);
 let result=build({PUBLIC_SUPABASE_URL:'https://test.supabase.co',PUBLIC_SUPABASE_KEY:key});assert.equal(result.status,0);const generated=await readFile(join(root,'dist/config.js'),'utf8');assert.ok(generated.includes(key));assert.ok(generated.includes('https://test.supabase.co'));assert.ok(!result.stdout.includes(key));
 assert.equal(build({PUBLIC_SUPABASE_URL:'https://test.supabase.co'}).status,1);
 const secret='sb_secret_never_print_this_value';result=build({PUBLIC_SUPABASE_URL:'https://test.supabase.co',PUBLIC_SUPABASE_KEY:secret});assert.equal(result.status,1);assert.ok(!result.stdout.includes(secret)&&!result.stderr.includes(secret));assert.ok(!(await readFile(join(root,'dist/config.js'),'utf8')).includes(secret));
 assert.equal(build({PUBLIC_SUPABASE_URL:'https://test.supabase.co',PUBLIC_SUPABASE_ANON_KEY:jwt('anon')}).status,0);
}finally{await rm(root,{recursive:true,force:true})}
console.log('PASS: deployment URL/key validation, publishable and anon support, secret/service_role rejection, build generation, missing-variable failure and no secret logging.');
