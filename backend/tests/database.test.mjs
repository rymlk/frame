import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const alice = '11111111-1111-4111-8111-111111111111';
const bob = '22222222-2222-4222-8222-222222222222';
const admin = '33333333-3333-4333-8333-333333333333';
const mutation = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

async function database() {
  const db = new PGlite();
  await db.exec(`create role anon nologin; create role authenticated nologin;
    create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    grant usage on schema auth to authenticated;
    grant execute on all functions in schema auth to authenticated;
    insert into auth.users values ('${alice}'), ('${bob}'), ('${admin}');`);
  await db.exec(await readFile(new URL('../../supabase/migrations/202610220001_frame.sql', import.meta.url), 'utf8'));
  await db.exec('update public.frame_settings set community_enabled=true');
  return db;
}
async function as(db, id, moderator = false) {
  await db.exec('reset role');
  await db.query(`select set_config('request.jwt.claim.sub', $1, false),
    set_config('request.jwt.claims', $2, false)`, [id, JSON.stringify({app_metadata:{frame_moderator:moderator}})]);
  await db.exec('set role authenticated');
}
async function rpc(db, name, args = []) {
  const values = args.map((_,i)=>`$${i+1}`).join(',');
  return (await db.query(`select public.${name}(${values}) as result`, args)).rows[0].result;
}
const patch = (id = mutation, expected = 0, value = true) => ({mutation_id:id, media_key:'tv:42', field:'watchlist', value, expected_revision:expected});

test('synchronisation: idempotence, collisions, conflits et isolation entre comptes', async () => {
  const db = await database();
  try {
    await as(db, alice);
    const first = await rpc(db, 'apply_library_mutation', [patch()]);
    assert.equal(first.conflict, false);
    assert.equal(first.record.value, true);
    assert.equal(first.record.revision, 1);
    assert.deepEqual(await rpc(db, 'apply_library_mutation', [patch()]), first);
    await assert.rejects(rpc(db, 'apply_library_mutation', [patch(mutation,0,false)]), /mutation_id/);
    const conflict = await rpc(db, 'apply_library_mutation', [patch('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',0,false)]);
    assert.equal(conflict.conflict, true);
    assert.equal(conflict.record.value, true);
    const next = await rpc(db, 'apply_library_mutation', [patch('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',1,false)]);
    assert.equal(next.record.value, false);
    assert.equal(next.record.revision, 2);
    await as(db, bob);
    assert.equal((await db.query('select * from public.library_fields')).rows.length, 0);
    await db.query(`insert into public.library_fields(owner_id,media_key,field,value) values ($1,'tv:4','watched','true')`,[bob])
      .then(()=>assert.fail('direct writes must be forbidden'), e=>assert.match(e.message,/permission denied/));
    const own = await rpc(db,'apply_library_mutation',[patch()]);
    assert.equal(own.record.revision, 1);
    await assert.rejects(db.query('select * from public.library_mutations'), /permission denied/);
  } finally { await db.close(); }
});

test('validation: valeurs et noms de champs stricts, épisodes et suppression conservée', async () => {
  const db = await database();
  try {
    await as(db, alice);
    for (const change of [ {field:'owner_id'}, {media_key:'tv:-1'}, {field:'rating',value:7},
      {field:'watchlist',value:'yes'}, {field:'episode:0:2',value:true}, {expected_revision:-1},
      {field:'review',value:'x'.repeat(701)}, {field:'media',value:{title:'x',poster:'javascript:alert(1)'}} ]) {
      await assert.rejects(rpc(db,'apply_library_mutation',[{...patch(),...change}]), /invalide/);
    }
    const result = await rpc(db,'apply_library_mutation',[{...patch(),field:'episode:1:2',value:{watched:true,runtime:44}}]);
    assert.deepEqual(result.record.value,{watched:true,runtime:44});
    const deleted = await rpc(db,'apply_library_mutation',[{...patch('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),field:'episode:1:2',value:null,expected_revision:1}]);
    assert.equal(deleted.record.value,null);
    assert.equal(deleted.record.revision,2);
  } finally { await db.close(); }
});

test('communauté: consentement, prémodération, signalement, blocage et rôles', async () => {
  const db = await database();
  try {
    await as(db, alice);
    await assert.rejects(rpc(db,'submit_post',['tv:42','Mon avis',4]), /conditions/);
    await rpc(db,'save_profile',['Alice','Cinéma','indigo',true]);
    const post = await rpc(db,'submit_post',['tv:42','Mon avis',4]);
    assert.equal(post.status,'pending');
    assert.equal((await rpc(db,'community_feed',[null])).length,0);
    await assert.rejects(rpc(db,'moderate_post',[post.id,'approved']),/modération/);
    await assert.rejects(db.query(`update public.posts set status='approved' where id=$1`,[post.id]),/permission denied/);
    await as(db, admin, true);
    assert.equal((await rpc(db,'moderation_queue')).length,1);
    await rpc(db,'moderate_post',[post.id,'approved']);
    await as(db,bob);
    assert.equal((await rpc(db,'community_feed',[null])).length,1);
    await rpc(db,'save_profile',['Bob','','mint',true]);
    const bobPost=await rpc(db,'submit_post',['tv:42','Avis de Bob',3]);
    await as(db,admin,true);
    await rpc(db,'moderate_post',[bobPost.id,'approved']);
    await as(db,bob);
    await rpc(db,'report_post',[post.id,'Insulte']);
    await rpc(db,'set_block',[alice,true]);
    assert.equal((await rpc(db,'blocked_users'))[0].nickname,'Alice');
    assert.deepEqual((await rpc(db,'community_feed',[null])).map(p=>p.author_id),[bob]);
    await as(db,alice);
    assert.deepEqual((await rpc(db,'community_feed',[null])).map(p=>p.author_id),[alice]);
    await as(db,admin,true);
    const queue=await rpc(db,'moderation_queue');
    assert.equal(queue[0].report_count,1);
    await rpc(db,'moderate_post',[post.id,'rejected']);
    await as(db,bob);
    await rpc(db,'set_block',[alice,false]);
    assert.equal((await rpc(db,'community_feed',[null])).length,1);
    await assert.rejects(rpc(db,'report_post',[post.id,'test']),/introuvable/);
  } finally { await db.close(); }
});

test('suppression de compte: données privées, messages et signalements supprimés en cascade', async () => {
  const db=await database();
  try {
    await as(db,alice);
    await rpc(db,'save_profile',['Alice','','indigo',true]);
    await rpc(db,'apply_library_mutation',[patch()]);
    await rpc(db,'submit_post',['movie:1','Un avis',5]);
    await db.exec('reset role');
    await db.query('delete from auth.users where id=$1',[alice]);
    for (const table of ['profiles','library_fields','library_mutations','posts']) {
      assert.equal((await db.query(`select count(*)::int as n from public.${table}`)).rows[0].n,0);
    }
    await db.exec('set role anon');
    await assert.rejects(db.query('select * from public.profiles'),/permission denied/);
    await assert.rejects(rpc(db,'community_feed',[null]),/permission denied/);
  } finally { await db.close(); }
});

test('la fermeture communauté est imposée dans PostgreSQL et les signalements ne dépendent pas des 60 derniers posts',async()=>{
  const db=await database();
  try {
    await as(db,alice);
    await rpc(db,'save_profile',['Alice','','indigo',true]);
    const post=await rpc(db,'submit_post',['movie:42','Avis ancien',4]);
    await db.exec('reset role');
    await db.query(`update public.posts set status='approved',created_at=now()-interval '1 day' where id=$1`,[post.id]);
    await db.query(`insert into public.posts(author_id,media_key,content,status) select $1,'tv:1','Autre avis','approved' from generate_series(1,61)`,[alice]);
    await as(db,bob);
    assert.equal((await rpc(db,'community_feed',[null])).some(p=>p.id===post.id),false);
    assert.equal((await rpc(db,'community_feed',['movie:42'])).length,1);
    await rpc(db,'report_post',[post.id,'Signalement légitime']);
    await db.exec('reset role');
    await db.exec('update public.frame_settings set community_enabled=false');
    await as(db,alice);
    await assert.rejects(rpc(db,'submit_post',['tv:1','Contournement',null]),/communauté.*indisponible/i);
    await assert.rejects(rpc(db,'community_feed',[null]),/communauté.*indisponible/i);
    await assert.rejects(rpc(db,'report_post',[post.id,'Contournement']),/communauté.*indisponible/i);
    await assert.rejects(db.exec('update public.frame_settings set community_enabled=true'),/permission denied/);
  }finally{await db.close();}
});
