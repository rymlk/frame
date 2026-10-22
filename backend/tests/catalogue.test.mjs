import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createCatalogue } from '../src/catalogue.mjs';

test('catalogue : absence de clé isolée du .env Windows',async()=>{
  const call=createCatalogue({token:''});
  assert.deepEqual(await call('/api/status',new URLSearchParams()),{ready:false});
  await assert.rejects(call('/api/home',new URLSearchParams()),e=>e.status===503);
});
test('catalogue : films, animes, saisons, épisodes et validation',async()=>{
  const server=http.createServer((req,res)=>{
    const p=new URL(req.url,'http://test').pathname;let data;
    const movie={id:1,title:'Film',poster_path:'/film.jpg',backdrop_path:'/back.jpg',overview:'Résumé',vote_count:10,vote_average:8};
    const show={id:2,name:'Anime',poster_path:'/anime.jpg',original_language:'ja',genre_ids:[16],overview:'Résumé',seasons:[{season_number:1}]};
    if(p.includes('/season/'))data={name:'Saison 1',episodes:[{id:3,season_number:1,episode_number:1,name:'Pilote',overview:'Début',air_date:'2020-01-01',runtime:24}]};
    else if(p==='/3/tv/2')data=show;
    else if(p==='/3/movie/1')data=movie;
    else data={results:[p.includes('movie')?movie:show],page:1,total_pages:3};
    res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(data));
  });
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  try{
    const call=createCatalogue({token:'fixture',apiRoot:`http://127.0.0.1:${server.address().port}/3`});
    const get=(p,q='')=>call(p,new URLSearchParams(q));
    assert.equal((await get('/api/search','type=anime&q=test')).items[0].category,'anime');
    assert.equal((await get('/api/detail','type=movie&id=1')).title,'Film');
    assert.equal((await get('/api/season','id=2&season=1')).episodes[0].runtime,24);
    assert.equal((await get('/api/earlier','type=tv&id=2&season=1&episode=2')).episodes.length,1);
    assert.equal((await get('/api/discover','type=movie')).totalPages,3);
    assert.ok((await get('/api/home')).films.length);
    await assert.rejects(get('/api/detail','type=movie&id=-1'),e=>e.status===400);
    await assert.rejects(get('/api/home','type=invalid'),e=>e.status===400);
    await assert.rejects(get('/api/unknown'),e=>e.status===404);
  }finally{await new Promise(r=>server.close(r));}
});
