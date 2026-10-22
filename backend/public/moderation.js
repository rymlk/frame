let config,session;
const element=id=>document.getElementById(id);
const status=message=>{element('status').textContent=message;};
async function request(url,options={}){
  const response=await fetch(url,{...options,headers:{'Content-Type':'application/json',...options.headers}});
  const text=await response.text();let data;try{data=text?JSON.parse(text):null;}catch{throw Error('Réponse du service invalide.');}
  if(!response.ok)throw Error(data?.error_description||data?.message||data?.error||'La demande a échoué.');
  return data;
}
async function auth(path,data){return request(config.supabaseURL+'/auth/v1/'+path,{method:'POST',headers:{apikey:config.supabaseKey},body:JSON.stringify(data)});}
async function api(path,options={}){
  if(!session)throw Error('Connecte-toi.');
  if(Date.now()/1000>session.expires_at-60){session=await auth('token?grant_type=refresh_token',{refresh_token:session.refresh_token});session.expires_at ||= Date.now()/1000+session.expires_in;}
  return request(path,{...options,headers:{Authorization:'Bearer '+session.access_token}});
}
function node(tag,text,css){const n=document.createElement(tag);n.textContent=text;if(css)n.className=css;return n;}
async function load(){
  status('Chargement…');
  try{
    const posts=await api('/v1/moderation');
    element('posts').replaceChildren();
    for(const post of posts){
      const card=node('article','');
      card.append(node('h2',post.nickname),node('small',`${post.media_key} · ${post.status==='pending'?'En attente':'Signalé'} · ${post.created_at}`),node('p',post.content));
      if(post.rating)card.append(node('p',`${post.rating}/5`));
      for(const report of post.reports||[])card.append(node('p','Signalement : '+report.reason));
      const controls=node('div','','controls');
      for(const [label,state,css] of [['Approuver','approved','approve'],['Rejeter / retirer','rejected','reject']]){
        const button=node('button',label,css);
        button.onclick=async()=>{
          if(!window.confirm(`${label} ce message ?`))return;
          button.disabled=true;
          try{await api('/v1/moderation',{method:'POST',body:JSON.stringify({postID:post.id,status:state})});await load();}catch(error){status(error.message);button.disabled=false;}
        };
        controls.append(button);
      }
      card.append(controls);element('posts').append(card);
    }
    status(posts.length?`${posts.length} message(s) à traiter.`:'Aucun message en attente.');
  }catch(error){status(error.message);}
}
element('email-form').onsubmit=async event=>{
  event.preventDefault();const button=event.submitter;button.disabled=true;
  try{await auth('otp',{email:element('email').value.trim(),create_user:false});element('code-form').hidden=false;status('Code envoyé.');}catch(error){status(error.message);}finally{button.disabled=false;}
};
element('code-form').onsubmit=async event=>{
  event.preventDefault();const button=event.submitter;button.disabled=true;
  try{
    session=await auth('verify',{email:element('email').value.trim(),token:element('code').value.trim(),type:'email'});
    session.expires_at ||= Date.now()/1000+session.expires_in;
    await api('/v1/moderation');
    element('login').hidden=true;element('console').hidden=false;await load();
  }catch(error){session=null;status(error.message);}finally{button.disabled=false;}
};
element('reload').onclick=load;
element('logout').onclick=async()=>{
  try{await request(config.supabaseURL+'/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:config.supabaseKey,Authorization:'Bearer '+session.access_token},body:'{}'});}catch{}finally{session=null;element('console').hidden=true;element('login').hidden=false;element('code').value='';element('posts').replaceChildren();status('Déconnexion effectuée.');}
};
request('/v1/config').then(value=>{config=value;if(!config.communityEnabled){element('login').hidden=true;status('La communauté est désactivée.');}}).catch(error=>status(error.message));
