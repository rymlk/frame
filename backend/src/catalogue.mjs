export function createCatalogue({token = '', apiRoot = 'https://api.themoviedb.org/3'} = {}) {
const cache = new Map();
const img = (p,size) => typeof p === 'string' && /^\/[\w./-]+$/.test(p) ? `https://image.tmdb.org/t/p/${size}${p}` : null;
const mediaType = (item, force) => force || item.media_type || (item.title ? 'movie' : 'tv');
const isAnime = item => item.original_language === 'ja' && ((item.genre_ids||[]).includes(16) || (item.genres||[]).some(g=>g.id === 16));
const clean = (v) => typeof v === 'string' ? v.trim() : '';
const norm = (item, force) => {
 const type = mediaType(item,force);
 return { id: item.id, key: `${type}:${item.id}`, type, category: type==='movie'?'film':isAnime(item)?'anime':'série', title: item.title||item.name||item.original_title||item.original_name||'Sans titre', year: (item.release_date||item.first_air_date||'').slice(0,4), overview:clean(item.overview), poster:img(item.poster_path,'w500'), backdrop:img(item.backdrop_path,'w1280'), rating:item.vote_count ? Number(item.vote_average||0).toFixed(1):null, originalLanguage:item.original_language||null, genreIds:item.genre_ids||item.genres?.map(x=>x.id)||[], releaseDate:item.release_date||item.first_air_date||null };
};
function reply(res,code,payload,headers={}) {const data=JSON.stringify(payload);res.writeHead(code,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store',...headers});res.end(data)}
function err(message,status=502){return Object.assign(new Error(message),{status})}
async function tmdb(endpoint, params={}, ttl=300000) {
 if (!token) throw err('Une clé TMDB est nécessaire. Ajoute TMDB_READ_ACCESS_TOKEN dans le fichier .env.',503);
 const u = new URL(apiRoot.replace(/\/$/,'')+'/'+endpoint.replace(/^\//,''));
 const query = {language:'fr-FR',include_adult:'false',...params};
 Object.entries(query).forEach(([k,v])=>{if(v !== undefined && v!==null)u.searchParams.set(k,String(v))});
 const key=u.toString(), item=cache.get(key);
 if(item && item.until>Date.now())return item.data;
 const controller = new AbortController();const t=setTimeout(()=>controller.abort(),11000);
 let response;
 try {response=await fetch(u,{headers:{Authorization:`Bearer ${token}`,Accept:'application/json'},signal:controller.signal})} catch(ex){throw err(ex.name==='AbortError'?'La source met trop de temps à répondre.':'Source de données temporairement inaccessible.',502)}finally{clearTimeout(t)}
 if(!response.ok){ if(response.status===401||response.status===403)throw err('Clé TMDB invalide ou accès refusé.',502); if(response.status===429)throw err('Trop de recherches. Réessaie dans un instant.',429); if(response.status===404)throw err('Œuvre introuvable.',404); throw err(`La source TMDB a répondu avec le statut ${response.status}.`,502)}
 const data=await response.json();if(cache.size>=400)cache.delete(cache.keys().next().value); cache.set(key,{data,until:Date.now()+ttl});return data;
}
function page(n){const num=Number(n)||1;return Math.max(1,Math.min(500,Math.trunc(num)))}
function stripNoArt(arr){return arr.filter(i=>i?.id && (i.poster||i.backdrop))}
async function discover(type,p) {
 if(type==='all'){ const pages=await Promise.all(['movie','tv','anime'].map(t=>discover(t,p))); const items=pages.flatMap(x=>x.items.slice(0,8)); return {items,page:p,totalPages:Math.min(500,Math.max(...pages.map(x=>x.totalPages)))}; }
 const category=['movie','tv','anime'].includes(type)?type:'movie';
 const route=category==='movie'?'movie':'tv';
 const extra=category==='anime'?{'with_genres':'16','with_original_language':'ja'}:{};
 const data=await tmdb(`discover/${route}`, {page:p,sort_by:'popularity.desc',...extra},600000);
 return {items:stripNoArt(data.results.map(x=>norm(x,route))),page:data.page,totalPages:Math.min(500,data.total_pages||1)};
}
async function search(type,q,p){
 const term=clean(q).slice(0,120);
 if(!term)return discover(type==='all'?'movie':type,p);
 const types=type==='movie'?['movie']:type==='tv'?['tv']:['movie','tv'];
 const results=await Promise.all(types.map(async t=>({t,data:await tmdb(`search/${t}`,{query:term,page:p},120000)})));
 let values=results.flatMap(({t,data})=>data.results.map(i=>norm(i,t)));
 if(type==='anime')values=values.filter(i=>i.originalLanguage==='ja'&&i.genreIds.includes(16));
 values=stripNoArt(values);
 if(type==='all')values.sort((a,b)=>Number(b.rating||0)-Number(a.rating||0));
 return {items:values,page:p,totalPages:Math.min(500,Math.max(...results.map(x=>x.data.total_pages||1))),note:type==='anime'?'La recherche anime utilise les classifications TMDB et peut manquer certains titres.':null};
}
async function home(){
 const [trending,films,shows,animes]=await Promise.all([
   tmdb('trending/all/week',{},300000),discover('movie',1),discover('tv',1),discover('anime',1)
 ]);
 const lead=stripNoArt(trending.results.filter(x=>x.media_type==='movie'||x.media_type==='tv').map(x=>norm(x))).find(x=>x.backdrop&&x.overview)||films.items[0];
 return {lead,films:films.items.slice(0,12),shows:shows.items.slice(0,12),animes:animes.items.slice(0,12)};
}
async function detail(type,id){
 const d=await tmdb(`${type}/${id}`,{append_to_response:'videos'},600000);
 if(!clean(d.overview)) {try{const en=await tmdb(`${type}/${id}`,{language:'en-US'},600000);d.overview=en.overview||'';}catch{}}
 const basic=norm(d,type);
 const genres=(d.genres||[]).map(g=>g.name);
 return {...basic,genres, runtime:d.runtime||d.episode_run_time?.[0]||null, tagline:clean(d.tagline), status:d.status||null, originalTitle:d.original_title||d.original_name||null,
     seasons:type==='tv'?(d.seasons||[]).map(s=>({number:s.season_number,name:s.name,count:s.episode_count,poster:img(s.poster_path,'w500'),airDate:s.air_date||null})):[],
     nextEpisode:type==='tv'&&d.next_episode_to_air?{id:d.next_episode_to_air.id,name:d.next_episode_to_air.name||null,airDate:d.next_episode_to_air.air_date||null,season:d.next_episode_to_air.season_number,episode:d.next_episode_to_air.episode_number}:null,
     videos:(d.videos?.results||[]).filter(v=>v.site==='YouTube'&&v.type==='Trailer').slice(0,2).map(v=>({id:v.key,name:v.name})),
     homepage:d.homepage?.startsWith('https://')?d.homepage:null};
}
async function season(id,n){
 const d=await tmdb(`tv/${id}/season/${n}`,{},600000);
 let originals=[];
 if((d.episodes||[]).some(e=>!clean(e.overview)))try{const en=await tmdb(`tv/${id}/season/${n}`,{language:'en-US'},600000);originals=en.episodes||[];}catch{}
 const byNumber=new Map(originals.map(x=>[x.episode_number,x]));
 return {number:Number(n),name:d.name, episodes:(d.episodes||[]).map(e=>({id:e.id,season:e.season_number,number:e.episode_number,name:clean(e.name)||byNumber.get(e.episode_number)?.name||`Épisode ${e.episode_number}`,description:clean(e.overview)||clean(byNumber.get(e.episode_number)?.overview)||'',airDate:e.air_date||null,runtime:e.runtime||null,still:img(e.still_path||byNumber.get(e.episode_number)?.still_path,'w300')}))};
}
async function earlierEpisodes(id, targetSeason, targetEpisode) {
  const show = await tmdb(`tv/${id}`, {}, 600000);
  const seasonNumbers = (show.seasons||[]).filter(s => s.season_number > 0 && s.season_number <= targetSeason && (s.season_number < targetSeason || targetEpisode > 1)).map(s => s.season_number);
  // TMDB only serves one season at a time. Limit concurrency to avoid flooding its API.
  const episodes = [];
  for (let i=0; i<seasonNumbers.length; i+=3) {
    const batch = await Promise.all(seasonNumbers.slice(i,i+3).map(n=>season(id,n)));
    for (const part of batch) for (const ep of part.episodes) {
      if (ep.season < targetSeason || (ep.season === targetSeason && ep.number < targetEpisode)) {
        // Avoid automatically ticking upcoming, unaired episodes.
        if (ep.airDate && ep.airDate > new Date().toISOString().slice(0,10)) continue;
        episodes.push({season:ep.season, number:ep.number, runtime:ep.runtime||null});
      }
    }
  }
  return {episodes};
}
return async function catalogue(pathname,params) {
  const type=params.get('type')||'all', id=Number(params.get('id')), sn=Number(params.get('season'));
  if(!['all','movie','tv','anime'].includes(type))throw err('Type non reconnu.',400);
  if(pathname==='/api/status')return {ready:!!token};
  if(pathname==='/api/home')return home();
  if(pathname==='/api/discover')return discover(type,page(params.get('page')));
  if(pathname==='/api/search')return search(type,params.get('q')||'',page(params.get('page')));
  if(pathname==='/api/detail'){
    if(!['movie','tv'].includes(type)||!Number.isSafeInteger(id)||id<=0)throw err('Paramètres invalides.',400);
    return detail(type,id);
  }
  if(pathname==='/api/season'||pathname==='/api/earlier'){
    if(!Number.isSafeInteger(id)||id<=0||!Number.isInteger(sn)||sn<0||sn>=1000)throw err('Paramètres invalides.',400);
    if(pathname==='/api/season')return season(id,sn);
    const ep=Number(params.get('episode'));
    if(type!=='tv'||sn<1||!Number.isInteger(ep)||ep<1||ep>10000)throw err('Paramètres invalides.',400);
    return earlierEpisodes(id,sn,ep);
  }
  throw err('Adresse introuvable.',404);
};
}