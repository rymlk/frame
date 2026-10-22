export class APIError extends Error {
  constructor(status,message){super(message);this.status=status;}
}

export class SupabaseGateway {
  constructor({url,publishableKey,secretKey}) {
    this.url=url.replace(/\/$/,'');this.key=publishableKey;this.secret=secretKey;
  }
  async request(path,{token,method='GET',body,admin=false}={}) {
    let response;
    try {
      response=await fetch(this.url+path,{method,headers:{apikey:admin?this.secret:this.key,
        ...(token?{Authorization:`Bearer ${token}`} : {}),
        ...(body!==undefined?{'Content-Type':'application/json'}:{})},
        body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(12000)});
    }catch{throw new APIError(502,'Service temporairement indisponible.');}
    const text=await response.text();let data;try{data=text?JSON.parse(text):null;}catch{throw new APIError(502,'Réponse du service invalide.');}
    if(!response.ok){
      if(response.status===401)throw new APIError(401,'Session expirée. Reconnecte-toi.');
      if(response.status===429)throw new APIError(429,'Trop de demandes. Réessaie plus tard.');
      if(response.status===403)throw new APIError(403,'Accès refusé.');
      // Database errors expose only known user-facing messages, never SQL details.
      const allowed=/^(Mutation invalide|Valeur invalide|Note invalide|Avis invalide|Épisode invalide|Média invalide|Profil invalide|Message invalide|Motif invalide|Blocage invalide|Statut invalide|Message introuvable|Accepte les conditions de la communauté|Trop de messages|mutation_id déjà utilisé)$/;
      if(allowed.test(data?.message||''))throw new APIError(400,data.message);
      throw new APIError(response.status>=500?502:400,'La demande n’a pas pu être traitée.');
    }
    return data;
  }
  async verify(token){const user=await this.request('/auth/v1/user',{token});if(!user?.id)throw new APIError(401,'Session invalide.');return user;}
  rpc(name,args,token){return this.request('/rest/v1/rpc/'+name,{method:'POST',body:args,token});}
  rows(table,query,token){return this.request(`/rest/v1/${table}?${query}`,{token});}
  deleteAccount(id){if(!this.secret)throw new APIError(503,'Suppression temporairement indisponible.');return this.request('/auth/v1/admin/users/'+encodeURIComponent(id),{method:'DELETE',admin:true,body:{should_soft_delete:false}});}
}
