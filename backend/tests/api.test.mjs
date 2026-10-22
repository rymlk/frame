import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createApp } from '../src/app.mjs';
import { SupabaseGateway } from '../src/gateway.mjs';

async function serve(handler) {
  const server=http.createServer(handler);
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  return {url:`http://127.0.0.1:${server.address().port}`,close:()=>new Promise(r=>server.close(r))};
}
const user='11111111-1111-4111-8111-111111111111';
async function setup(overrides={}) {
  const calls=[];
  const upstream=await serve(async(req,res)=>{
    let raw=''; for await(const c of req) raw+=c;
    calls.push({url:req.url,auth:req.headers.authorization,key:req.headers.apikey,body:raw?JSON.parse(raw):null});
    const json=(code,data)=>{res.writeHead(code,{'content-type':'application/json'});res.end(JSON.stringify(data));};
    if(req.url==='/auth/v1/user') return req.headers.authorization==='Bearer valid' ? json(200,{id:user,app_metadata:{}}) : json(401,{message:'invalid'});
    if(req.url.startsWith('/auth/v1/admin/users/')) return json(200,{});
    if(req.url.startsWith('/rest/v1/')) return json(200,req.url.includes('/rpc/')?{ok:true}:[]);
    json(404,{});
  });
  const gateway=new SupabaseGateway({url:upstream.url,publishableKey:'public-test',secretKey:'secret-test'});
  const config={supabaseURL:upstream.url,supabaseKey:'public-test',communityEnabled:true,termsURL:'https://frame.test/terms',privacyURL:'https://frame.test/privacy',supportURL:'https://frame.test/support',allowedOrigins:['https://frame.test'],rateLimit:100,...overrides};
  const app=await serve(createApp({config,gateway,catalogue:async()=>({items:[]})}));
  return {...app,calls,close:async()=>{await app.close();await upstream.close();}};
}
const headers={Authorization:'Bearer valid','Content-Type':'application/json'};

test('API privée : refus sans session, vérification distante, identité issue du serveur',async()=>{
  const s=await setup();
  try {
    assert.equal((await fetch(s.url+'/v1/profile')).status,401);
    assert.equal((await fetch(s.url+'/v1/profile',{headers:{Authorization:'Bearer invalid'}})).status,401);
    assert.equal((await fetch(s.url+'/v1/profile',{headers})).status,200);
    const last=s.calls.at(-1);assert.match(last.url,new RegExp(`id=eq.${user}`));assert.equal(last.auth,'Bearer valid');assert.equal(last.key,'public-test');
    const r=await fetch(s.url+'/v1/library/mutations',{method:'POST',headers,body:JSON.stringify({mutation_id:'x',owner_id:'someone-else'})});
    assert.equal(r.status,200);
    assert.equal(s.calls.at(-1).body.p_input.owner_id,undefined);
    assert.equal(s.calls.at(-1).auth,'Bearer valid');
  } finally {await s.close();}
});

test('API : JSON, taille, origine, pagination complète et erreurs stables',async()=>{
  const s=await setup();
  try {
    assert.equal((await fetch(s.url+'/v1/profile',{method:'PATCH',headers,body:'{'})).status,400);
    assert.equal((await fetch(s.url+'/v1/profile',{method:'PATCH',headers,body:JSON.stringify({bio:'x'.repeat(17000)})})).status,413);
    assert.equal((await fetch(s.url+'/v1/profile',{method:'PATCH',headers:{...headers,Origin:'https://evil.test'},body:'{}'})).status,403);
    assert.equal((await fetch(s.url+'/v1/library?offset=1000',{headers})).status,200);
    assert.match(s.calls.at(-1).url,/offset=1000/);
    assert.equal((await fetch(s.url+'/v1/library?offset=-1',{headers})).status,400);
    assert.equal((await fetch(s.url+'/not-found')).status,404);
    assert.equal((await fetch(s.url+'/api/community',{method:'POST',headers,body:'{}'})).status,404);
    assert.equal((await fetch(s.url+'/api/community')).status,404);
  }finally{await s.close();}
});

test('suppression : confirmation explicite, secret serveur uniquement pour supprimer son propre compte',async()=>{
  const s=await setup();
  try {
    assert.equal((await fetch(s.url+'/v1/account',{method:'DELETE',headers,body:'{}'})).status,400);
    const r=await fetch(s.url+'/v1/account',{method:'DELETE',headers,body:JSON.stringify({confirmation:'SUPPRIMER',user_id:'other'})});
    assert.equal(r.status,204);
    assert.equal(s.calls.at(-1).url,`/auth/v1/admin/users/${user}`);
    assert.equal(s.calls.at(-1).key,'secret-test');
    assert.equal((await fetch(s.url+'/v1/moderation',{headers})).status,403);
  } finally {await s.close();}
});

test('configuration publique sans secrets, communauté désactivable et limite de requêtes',async()=>{
  const s=await setup({communityEnabled:false,rateLimit:5});
  try {
    const cfg=await (await fetch(s.url+'/v1/config')).json();
    assert.equal(cfg.supabaseKey,'public-test');assert.equal(cfg.communityEnabled,false);
    assert.doesNotMatch(JSON.stringify(cfg),/secret-test/);
    assert.equal((await fetch(s.url+'/v1/community',{headers})).status,503);
    assert.equal((await fetch(s.url+'/health')).status,200);
    assert.equal((await fetch(s.url+'/api/home')).status,200);
    await fetch(s.url+'/health');
    assert.equal((await fetch(s.url+'/health')).status,429);
  } finally {await s.close();}
});

test('échec du fournisseur : pas de fuite des messages internes',async()=>{
  const s=await serve(createApp({config:{rateLimit:10},gateway:{verify:async()=>{throw new Error('secret internal credential');}},catalogue:async()=>{throw new Error('secret TMDB');}}));
  try {
    const a=await fetch(s.url+'/v1/profile',{headers});assert.equal(a.status,502);assert.doesNotMatch(await a.text(),/secret/);
    const b=await fetch(s.url+'/api/home');assert.equal(b.status,502);assert.doesNotMatch(await b.text(),/secret/);
  } finally {await s.close();}
});
