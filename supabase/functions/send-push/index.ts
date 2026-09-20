import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
Deno.serve(async req=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  try{
    const auth=req.headers.get('Authorization')||'';
    const token=auth.replace(/^Bearer\s+/i,'');
    if(!token) return new Response(JSON.stringify({error:'Unauthorized'}),{status:401,headers:{...cors,'Content-Type':'application/json'}});
    const anon=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!);
    const {data:{user},error:userErr}=await anon.auth.getUser(token);
    if(userErr||!user) return new Response(JSON.stringify({error:'Unauthorized'}),{status:401,headers:{...cors,'Content-Type':'application/json'}});
    const body=await req.json();
    const to=String(body?.to||'').trim();
    if(!to) throw new Error('Missing recipient');
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const {data:subs,error}=await admin.from('push_subscriptions').select('id,endpoint,subscription').eq('username',to);
    if(error) throw error;
    const pub=Deno.env.get('VAPID_PUBLIC_KEY')!, priv=Deno.env.get('VAPID_PRIVATE_KEY')!, subject=Deno.env.get('VAPID_SUBJECT')||'mailto:xauraultra@gmail.com';
    webpush.setVapidDetails(subject,pub,priv);
    const payload=JSON.stringify({title:String(body?.title||'Aura Ultra X'),text:String(body?.text||'Yeni bildirim'),type:body?.type||null,roomId:body?.roomId||null,tag:`aurax-${Date.now()}`});
    const results=[];
    for(const s of subs||[]){
      try{await webpush.sendNotification(s.subscription,payload);results.push({id:s.id,ok:true});}
      catch(e){const status=e?.statusCode||0;results.push({id:s.id,ok:false,status});if(status===404||status===410) await admin.from('push_subscriptions').delete().eq('id',s.id);}
    }
    return new Response(JSON.stringify({ok:true,results}),{headers:{...cors,'Content-Type':'application/json'}});
  }catch(e){return new Response(JSON.stringify({error:e?.message||String(e)}),{status:500,headers:{...cors,'Content-Type':'application/json'}})}
});
