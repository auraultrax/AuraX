import { createClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@6";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const FIREBASE_PROJECT='aura-ultra-x';
const GOOGLE_JWKS=createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
Deno.serve(async req=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  try{
    const body=await req.json();
    const idToken=String(body?.firebaseIdToken||'');
    const password=String(body?.newPassword||'');
    if(!idToken||password.length<8) throw new Error('Geçersiz istek.');
    const {payload}=await jwtVerify(idToken,GOOGLE_JWKS,{audience:FIREBASE_PROJECT,issuer:`https://securetoken.google.com/${FIREBASE_PROJECT}`});
    const email=String(payload.email||'').trim().toLowerCase();
    if(!email) throw new Error('Google hesabında e-posta bulunamadı.');
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let userId:string|null=null;
    for(let page=1;page<=20 && !userId;page++){
      const {data,error}=await admin.auth.admin.listUsers({page,perPage:1000});
      if(error) throw error;
      const found=(data.users||[]).find(u=>String(u.email||'').toLowerCase()===email);
      if(found) userId=found.id;
      if((data.users||[]).length<1000) break;
    }
    if(!userId) throw new Error('Bu Google hesabına bağlı Supabase hesabı bulunamadı. Önce Aura X ile giriş yapın.');
    const {error:updateErr}=await admin.auth.admin.updateUserById(userId,{password});
    if(updateErr) throw updateErr;
    const {data:docs}=await admin.from('aurax_documents').select('collection,doc_id,data').eq('collection','users');
    const match=(docs||[]).find(r=>String(r.data?.googleEmail||r.data?.email||'').toLowerCase()===email);
    if(match){
      await admin.from('aurax_documents').update({data:{...(match.data||{}),passwordResetAt:Date.now()}}).eq('collection','users').eq('doc_id',match.doc_id);
    }
    return new Response(JSON.stringify({ok:true}),{headers:{...cors,'Content-Type':'application/json'}});
  }catch(e){return new Response(JSON.stringify({error:e?.message||String(e)}),{status:400,headers:{...cors,'Content-Type':'application/json'}})}
});
