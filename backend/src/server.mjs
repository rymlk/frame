import http from 'node:http';
import { createApp } from './app.mjs';
import { SupabaseGateway } from './gateway.mjs';
import { createCatalogue } from './catalogue.mjs';

const production=process.env.NODE_ENV==='production';
function address(name,required=true){
  const value=process.env[name]||'';
  if(!value&&!required)return '';
  let url;try{url=new URL(value);}catch{throw Error(`${name} doit être une adresse valide.`);}
  if(url.username||url.password||(!['http:','https:'].includes(url.protocol))||(production&&url.protocol!=='https:'))throw Error(`${name} doit utiliser HTTPS en production.`);
  return url.toString().replace(/\/$/,'');
}
const config={supabaseURL:address('SUPABASE_URL'),supabaseKey:process.env.SUPABASE_PUBLISHABLE_KEY,
  communityEnabled:process.env.COMMUNITY_ENABLED==='true',termsURL:address('TERMS_URL'),privacyURL:address('PRIVACY_URL'),supportURL:address('SUPPORT_URL'),
  allowedOrigins:(process.env.ALLOWED_ORIGINS||'').split(',').map(s=>s.trim()).filter(Boolean),trustProxy:process.env.TRUST_PROXY==='true',rateLimit:Number(process.env.RATE_LIMIT_PER_MINUTE||180)};
if(!config.supabaseKey||!process.env.SUPABASE_SECRET_KEY)throw Error('Configure les clés Supabase dans l’environnement du serveur.');
if(production&&!process.env.TMDB_READ_ACCESS_TOKEN)throw Error('Configure TMDB_READ_ACCESS_TOKEN.');
if(config.communityEnabled&&process.env.MODERATION_READY!=='true')throw Error('Valide MODERATION_READY avant d’ouvrir la communauté.');
const gateway=new SupabaseGateway({url:config.supabaseURL,publishableKey:config.supabaseKey,secretKey:process.env.SUPABASE_SECRET_KEY});
const catalogue=createCatalogue({token:process.env.TMDB_READ_ACCESS_TOKEN||''});
const server=http.createServer({requestTimeout:20000,headersTimeout:15000,maxHeaderSize:16384},createApp({config,gateway,catalogue}));
server.listen(Number(process.env.PORT||8080),process.env.HOST||'0.0.0.0',()=>console.log('FRAME API démarrée.'));
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{server.close(()=>process.exit(0));setTimeout(()=>process.exit(1),10000).unref();});
