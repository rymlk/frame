begin;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default 'Spectateur' check (length(nickname) between 1 and 24),
  bio text not null default '' check (length(bio) <= 240),
  avatar text not null default 'indigo' check (avatar in ('indigo','rose','amber','mint')),
  accepted_terms_at timestamptz,
  accepted_terms_version text,
  updated_at timestamptz not null default now()
);
create table public.library_fields (
  owner_id uuid not null references auth.users(id) on delete cascade,
  media_key text not null check (media_key ~ '^(movie|tv):[1-9][0-9]{0,9}$'),
  field text not null,
  value jsonb,
  revision integer not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  primary key(owner_id,media_key,field)
);
create table public.library_mutations (
  owner_id uuid not null references auth.users(id) on delete cascade,
  mutation_id uuid not null,
  input jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key(owner_id,mutation_id)
);
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  media_key text not null check (media_key ~ '^(movie|tv):[1-9][0-9]{0,9}$'),
  content text not null check (length(content) between 1 and 700),
  rating integer check (rating between 1 and 5),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  moderated_at timestamptz
);
create index posts_feed on public.posts(status,created_at desc);
create index posts_author on public.posts(author_id,created_at desc);
create table public.blocks (
  owner_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  primary key(owner_id,blocked_id),
  check(owner_id <> blocked_id)
);
create index blocks_reverse on public.blocks(blocked_id,owner_id);
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  reason text not null check(length(reason) between 1 and 500),
  created_at timestamptz not null default now(),
  unique(reporter_id,post_id)
);

alter table public.profiles enable row level security;
alter table public.library_fields enable row level security;
alter table public.library_mutations enable row level security;
alter table public.posts enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
create policy own_profile on public.profiles for select to authenticated using (id=(select auth.uid()));
create policy own_library on public.library_fields for select to authenticated using (owner_id=(select auth.uid()));
create policy own_blocks on public.blocks for select to authenticated using (owner_id=(select auth.uid()));
revoke all on public.profiles,public.library_fields,public.library_mutations,public.posts,public.blocks,public.reports from anon,authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles,public.library_fields,public.blocks to authenticated;

-- All write functions derive identity from the verified JWT. No owner parameter.
create function public.apply_library_mutation(p_input jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid(); mid uuid; k text := p_input->>'media_key'; f text := p_input->>'field';
  v jsonb := nullif(p_input->'value','null'::jsonb); expected integer;
  old public.library_mutations%rowtype; current_row public.library_fields%rowtype; result jsonb;
begin
  if u is null then raise exception 'Authentification requise'; end if;
  begin
    mid := (p_input->>'mutation_id')::uuid;
    expected := (p_input->>'expected_revision')::integer;
  exception when others then raise exception 'Mutation invalide'; end;
  if mid is null or expected is null or expected < 0 or k is null or k !~ '^(movie|tv):[1-9][0-9]{0,9}$'
    or f is null or not (f in ('watchlist','watched','rating','review','media') or f ~ '^episode:[1-9][0-9]{0,2}:[1-9][0-9]{0,3}$')
    or not (p_input ? 'value') then raise exception 'Mutation invalide'; end if;
  if v is not null then
    if f in ('watchlist','watched') and jsonb_typeof(v) <> 'boolean' then raise exception 'Valeur invalide'; end if;
    if f='rating' and (jsonb_typeof(v)<>'number' or v::text !~ '^[1-5]$') then raise exception 'Note invalide'; end if;
    if f='review' and (jsonb_typeof(v)<>'string' or length(v#>>'{}')>700) then raise exception 'Avis invalide'; end if;
    if f like 'episode:%' and (jsonb_typeof(v)<>'object' or jsonb_typeof(v->'watched') is distinct from 'boolean'
      or (v ? 'runtime' and v->'runtime'<>'null'::jsonb and (jsonb_typeof(v->'runtime')<>'number' or (v->>'runtime') !~ '^[0-9]{1,3}$')))
      then raise exception 'Épisode invalide'; end if;
    if f='media' and (jsonb_typeof(v)<>'object' or jsonb_typeof(v->'title') is distinct from 'string'
      or length(v->>'title') not between 1 and 300
      or (v ? 'poster' and v->'poster'<>'null'::jsonb and (v->>'poster') !~ '^https://image[.]tmdb[.]org/t/p/[a-z0-9]+/[A-Za-z0-9._/-]+$')
      or octet_length(v::text)>12000) then raise exception 'Média invalide'; end if;
  end if;
  -- Serialise by account so concurrent retries and different fields remain atomic.
  perform 1 from auth.users where id=u for update;
  select * into old from public.library_mutations where owner_id=u and mutation_id=mid;
  if found then
    if old.input<>p_input then raise exception 'mutation_id déjà utilisé'; end if;
    return old.result;
  end if;
  select * into current_row from public.library_fields where owner_id=u and media_key=k and field=f;
  if coalesce(current_row.revision,0)<>expected then
    return jsonb_build_object('conflict',true,'record',case when current_row.owner_id is null then null else to_jsonb(current_row)-'owner_id' end);
  end if;
  insert into public.library_fields(owner_id,media_key,field,value,revision) values(u,k,f,v,1)
    on conflict(owner_id,media_key,field) do update set value=excluded.value,revision=public.library_fields.revision+1,updated_at=now()
    returning * into current_row;
  result:=jsonb_build_object('conflict',false,'record',to_jsonb(current_row)-'owner_id');
  insert into public.library_mutations(owner_id,mutation_id,input,result) values(u,mid,p_input,result);
  return result;
end $$;

create function public.save_profile(p_nickname text,p_bio text,p_avatar text,p_accept_terms boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid:=auth.uid(); result public.profiles%rowtype;
begin
  if u is null then raise exception 'Authentification requise'; end if;
  if length(trim(p_nickname)) not between 1 and 24 or length(p_bio)>240 or p_avatar not in ('indigo','rose','amber','mint')
    or p_nickname is null or p_bio is null or p_avatar is null then raise exception 'Profil invalide'; end if;
  insert into public.profiles(id,nickname,bio,avatar,accepted_terms_at,accepted_terms_version)
    values(u,trim(p_nickname),p_bio,p_avatar,case when p_accept_terms then now() end,case when p_accept_terms then '2026-10-22' end)
    on conflict(id) do update set nickname=excluded.nickname,bio=excluded.bio,avatar=excluded.avatar,updated_at=now(),
      accepted_terms_at=coalesce(excluded.accepted_terms_at,public.profiles.accepted_terms_at),
      accepted_terms_version=coalesce(excluded.accepted_terms_version,public.profiles.accepted_terms_version)
    returning * into result;
  return to_jsonb(result);
end $$;

create function public.submit_post(p_media_key text,p_content text,p_rating integer default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid:=auth.uid(); result public.posts%rowtype;
begin
  if u is null then raise exception 'Authentification requise'; end if;
  perform 1 from auth.users where id=u for update;
  if not exists(select 1 from public.profiles where id=u and accepted_terms_version='2026-10-22') then
    raise exception 'Accepte les conditions de la communauté'; end if;
  if length(trim(p_content)) not between 1 and 700 or p_content is null or p_media_key is null
    or p_media_key !~ '^(movie|tv):[1-9][0-9]{0,9}$' or (p_rating is not null and p_rating not between 1 and 5)
    then raise exception 'Message invalide'; end if;
  if (select count(*) from public.posts where author_id=u and created_at>now()-interval '1 minute')>=6 then
    raise exception 'Trop de messages'; end if;
  insert into public.posts(author_id,media_key,content,rating) values(u,p_media_key,trim(p_content),p_rating) returning * into result;
  return to_jsonb(result);
end $$;

create function public.community_feed(p_media_key text default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(feed)), '[]'::jsonb) from (
    select p.id,p.author_id,p.media_key,p.content,p.rating,p.created_at,pr.nickname,pr.avatar
    from public.posts p join public.profiles pr on pr.id=p.author_id
    where auth.uid() is not null and p.status='approved' and (p_media_key is null or p.media_key=p_media_key)
    and not exists(select 1 from public.blocks b where (b.owner_id=auth.uid() and b.blocked_id=p.author_id)
      or (b.blocked_id=auth.uid() and b.owner_id=p.author_id))
    order by p.created_at desc,p.id limit 60
  ) feed;
$$;

create function public.set_block(p_user_id uuid,p_blocked boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or p_user_id=auth.uid() or p_user_id is null or p_blocked is null then raise exception 'Blocage invalide'; end if;
  if p_blocked then insert into public.blocks(owner_id,blocked_id) values(auth.uid(),p_user_id) on conflict do nothing;
  else delete from public.blocks where owner_id=auth.uid() and blocked_id=p_user_id; end if;
end $$;

create function public.report_post(p_post_id uuid,p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  if length(trim(p_reason)) not between 1 and 500 or p_reason is null then raise exception 'Motif invalide'; end if;
  if not exists(select 1 from jsonb_array_elements(public.community_feed(null)) item where item->>'id'=p_post_id::text)
    then raise exception 'Message introuvable'; end if;
  insert into public.reports(reporter_id,post_id,reason) values(auth.uid(),p_post_id,trim(p_reason)) on conflict(reporter_id,post_id) do nothing;
end $$;

create function public.blocked_users() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('blocked_id',b.blocked_id,'nickname',coalesce(p.nickname,'Utilisateur bloqué'))),'[]'::jsonb)
  from public.blocks b left join public.profiles p on p.id=b.blocked_id where b.owner_id=auth.uid();
$$;

create function public.moderation_queue() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt()->'app_metadata'->>'frame_moderator','false')<>'true' then raise exception 'Accès modération refusé'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) from (
    select p.*,pr.nickname,(select count(*) from public.reports r where r.post_id=p.id) as report_count,
      (select coalesce(jsonb_agg(jsonb_build_object('reason',r.reason,'created_at',r.created_at)),'[]'::jsonb) from public.reports r where r.post_id=p.id) as reports
    from public.posts p join public.profiles pr on pr.id=p.author_id
    where p.status='pending' or (p.status='approved' and exists(select 1 from public.reports r where r.post_id=p.id))
    order by p.created_at limit 100
  ) q);
end $$;

create function public.moderate_post(p_post_id uuid,p_status text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt()->'app_metadata'->>'frame_moderator','false')<>'true' then raise exception 'Accès modération refusé'; end if;
  if p_status is null or p_status not in ('approved','rejected') then raise exception 'Statut invalide'; end if;
  update public.posts set status=p_status,moderated_at=now() where id=p_post_id;
  if not found then raise exception 'Message introuvable'; end if;
  delete from public.reports where post_id=p_post_id;
end $$;

revoke all on function public.apply_library_mutation(jsonb),public.save_profile(text,text,text,boolean),
  public.submit_post(text,text,integer),public.community_feed(text),public.set_block(uuid,boolean),
  public.report_post(uuid,text),public.blocked_users(),public.moderation_queue(),public.moderate_post(uuid,text) from public,anon;
grant execute on function public.apply_library_mutation(jsonb),public.save_profile(text,text,text,boolean),
  public.submit_post(text,text,integer),public.community_feed(text),public.set_block(uuid,boolean),
  public.report_post(uuid,text),public.blocked_users(),public.moderation_queue(),public.moderate_post(uuid,text) to authenticated;

commit;
