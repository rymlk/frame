import crypto from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { APIError } from './gateway.mjs';

async function body(req) {
  if(!String(req.headers['content-type']||'').toLowerCase().startsWith('application/json'))throw new APIError(415,'Format JSON requis.');
  const chunks=[];let size=0;
  for await(const chunk of req){size+=chunk.length;if(size>16384)throw new APIError(413,'Demande trop volumineuse.');chunks.push(chunk);}
  try{const data=JSON.parse(Buffer.concat(chunks).toString('utf8'));if(!data||Array.isArray(data)||typeof data!=='object')throw Error();return data;}
  catch{throw new APIError(400,'JSON invalide.');}
}
function send(res,status,data,headers={}){
  if(res.headersSent)return;
  res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...headers});
  res.end(status===204?undefined:JSON.stringify(data));
}

export function createApp({config,gateway,catalogue}) {
  const limits=new Map();
  return async(req,res)=>{
    const requestId=crypto.randomUUID();res.setHeader('X-Request-ID',requestId);
    try{
      const ip=config.trustProxy ? String(req.headers['x-forwarded-for']||req.socket.remoteAddress).split(',').at(-1).trim() : req.socket.remoteAddress;
      const now=Date.now();let count=limits.get(ip);
      if(!count||now-count.since>60000){count={since:now,n:0};limits.delete(ip);limits.set(ip,count);}
      if(limits.size>20000)limits.delete(limits.keys().next().value);
      if(++count.n>(config.rateLimit||180))return send(res,429,{error:'Trop de demandes. Réessaie dans une minute.'},{'Retry-After':'60'});
      const origin=req.headers.origin;
      if(origin && !(config.allowedOrigins||[]).includes(origin))throw new APIError(403,'Origine refusée.');
      if(origin){res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');}
      if(req.method==='OPTIONS')return send(res,204,null,{'Access-Control-Allow-Methods':'GET,POST,PATCH,DELETE,OPTIONS','Access-Control-Allow-Headers':'Authorization,Content-Type'});
      const url=new URL(req.url,'http://frame.internal');const path=url.pathname;
      if(path==='/health'&&req.method==='GET')return send(res,200,{status:'ok',version:'1.0.0'});
      if(path==='/v1/config'&&req.method==='GET')return send(res,200,{
        supabaseURL:config.supabaseURL,supabaseKey:config.supabaseKey,communityEnabled:!!config.communityEnabled,
        termsURL:config.termsURL,privacyURL:config.privacyURL,supportURL:config.supportURL,termsVersion:'2026-10-22'
      });
      if(req.method==='GET'&&['/moderation','/moderation.js','/moderation.css'].includes(path)){
        const file=path==='/moderation'?'moderation.html':path.slice(1);
        const data=await readFile(new URL('../public/'+file,import.meta.url));
        res.writeHead(200,{'Content-Type':file.endsWith('.html')?'text/html; charset=utf-8':file.endsWith('.js')?'text/javascript; charset=utf-8':'text/css; charset=utf-8',
          'Content-Security-Policy':"default-src 'self'; connect-src 'self' https://*.supabase.co; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",'X-Content-Type-Options':'nosniff','Cache-Control':'no-store'});res.end(data);return;
      }
      if(path.startsWith('/api/')&&path!=='/api/community'&&req.method==='GET')return send(res,200,await catalogue(path,url.searchParams));
      const known=new Set(['/v1/profile','/v1/library','/v1/library/mutations','/v1/community','/v1/reports','/v1/blocks','/v1/moderation','/v1/account']);
      if(!known.has(path))throw new APIError(404,'Adresse introuvable.');
      const bearer=String(req.headers.authorization||'').match(/^Bearer ([^\s]+)$/i)?.[1];
      if(!bearer)throw new APIError(401,'Connexion requise.');
      const user=await gateway.verify(bearer);
      if(['/v1/community','/v1/reports','/v1/blocks','/v1/moderation'].includes(path)&&!config.communityEnabled)throw new APIError(503,'La communauté ouvrira prochainement.');
      if(path==='/v1/profile'){
        if(req.method==='GET'){const rows=await gateway.rows('profiles',`id=eq.${encodeURIComponent(user.id)}&select=*`,bearer);return send(res,200,rows[0]||null);}
        if(req.method==='PATCH'){const b=await body(req);return send(res,200,await gateway.rpc('save_profile',{p_nickname:b.nickname,p_bio:b.bio,p_avatar:b.avatar,p_accept_terms:b.acceptTerms===true},bearer));}
      }
      if(path==='/v1/library'&&req.method==='GET'){
        const offset=Number(url.searchParams.get('offset')||0);
        if(!Number.isSafeInteger(offset)||offset<0)throw new APIError(400,'Pagination invalide.');
        return send(res,200,await gateway.rows('library_fields',`owner_id=eq.${encodeURIComponent(user.id)}&select=media_key,field,value,revision,updated_at&order=media_key.asc,field.asc&limit=500&offset=${offset}`,bearer));
      }
      if(path==='/v1/library/mutations'&&req.method==='POST'){
        const b=await body(req);const input={mutation_id:b.mutation_id,media_key:b.media_key,field:b.field,value:b.value,expected_revision:b.expected_revision};
        return send(res,200,await gateway.rpc('apply_library_mutation',{p_input:input},bearer));
      }
      if(path==='/v1/community'){
        if(req.method==='GET')return send(res,200,await gateway.rpc('community_feed',{p_media_key:url.searchParams.get('mediaKey')||null},bearer));
        if(req.method==='POST'){const b=await body(req);return send(res,201,await gateway.rpc('submit_post',{p_media_key:b.mediaKey,p_content:b.content,p_rating:b.rating??null},bearer));}
      }
      if(path==='/v1/reports'&&req.method==='POST'){const b=await body(req);await gateway.rpc('report_post',{p_post_id:b.postID,p_reason:b.reason},bearer);return send(res,204);}
      if(path==='/v1/blocks'){
        if(req.method==='GET')return send(res,200,await gateway.rpc('blocked_users',{},bearer));
        if(req.method==='POST'){const b=await body(req);await gateway.rpc('set_block',{p_user_id:b.userID,p_blocked:b.blocked},bearer);return send(res,204);}
      }
      if(path==='/v1/moderation'){
        if(user.app_metadata?.frame_moderator!==true)throw new APIError(403,'Accès modération refusé.');
        if(req.method==='GET')return send(res,200,await gateway.rpc('moderation_queue',{},bearer));
        if(req.method==='POST'){const b=await body(req);await gateway.rpc('moderate_post',{p_post_id:b.postID,p_status:b.status},bearer);return send(res,204);}
      }
      if(path==='/v1/account'&&req.method==='DELETE'){
        const b=await body(req);if(b.confirmation!=='SUPPRIMER')throw new APIError(400,'Confirme la suppression du compte.');
        await gateway.deleteAccount(user.id);return send(res,204);
      }
      throw new APIError(405,'Méthode non autorisée.');
    }catch(e){
      const expected=e instanceof APIError || (Number.isInteger(e.status)&&e.status>=400&&e.status<600);
      send(res,expected?e.status:502,{error:expected?e.message:'Service temporairement indisponible.',requestId});
    }
  };
}
