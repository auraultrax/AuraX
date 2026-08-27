/* Aura Ultra X - Cloudflare Worker
 * Routes:
 *   POST /api/register
 *   POST /api/login
 *
 * Required Worker secrets/vars:
 *   FIREBASE_PROJECT_ID
 *   FIREBASE_CLIENT_EMAIL
 *   FIREBASE_PRIVATE_KEY   (service-account PEM, with \n kept as literal newlines or escaped)
 *   FIREBASE_WEB_API_KEY   (Firebase Web API key)
 *   ADMIN_USERNAME         (default: A_UR_A_XX)
 */

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }
});

const cors = (req, res) => {
  const origin = req.headers.get('Origin') || '';
  const h = new Headers(res.headers);
  if (origin) h.set('Access-Control-Allow-Origin', origin);
  h.set('Vary', 'Origin');
  h.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  h.set('Access-Control-Allow-Headers', 'Content-Type');
  return new Response(res.body, { status: res.status, headers: h });
};

function b64url(bytes) {
  let s = '';
  if (typeof bytes === 'string') s = btoa(bytes);
  else { const a = new Uint8Array(bytes); let x=''; for (const b of a) x += String.fromCharCode(b); s=btoa(x); }
  return s.replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
}
function b64std(bytes) { const a = new Uint8Array(bytes); let x=''; for (const b of a) x += String.fromCharCode(b); return btoa(x); }
function utf8(s) { return new TextEncoder().encode(s); }
function fromB64(s) {
  const t = s.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(s.length/4)*4,'=');
  const raw = atob(t); return Uint8Array.from(raw, c => c.charCodeAt(0));
}

async function importPrivateKey(pem) {
  const clean = pem.replace(/\\n/g, '\n').replace(/\r/g, '');
  const body = clean.replace(/-----BEGIN PRIVATE KEY-----/,'').replace(/-----END PRIVATE KEY-----/,'').replace(/\s+/g,'');
  return crypto.subtle.importKey('pkcs8', fromB64(body), { name:'RSASSA-PKCS1-v1_5', hash:'SHA-256' }, false, ['sign']);
}

async function signJwt(header, payload, privateKey) {
  const input = `${b64url(utf8(JSON.stringify(header)))}.${b64url(utf8(JSON.stringify(payload)))}`;
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, utf8(input));
  return `${input}.${b64url(sig)}`;
}

async function googleAccessToken(env) {
  const now = Math.floor(Date.now()/1000);
  const key = await importPrivateKey(env.FIREBASE_PRIVATE_KEY);
  const assertion = await signJwt(
    { alg:'RS256', typ:'JWT' },
    {
      iss: env.FIREBASE_CLIENT_EMAIL,
      scope: 'https://www.googleapis.com/auth/datastore',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600
    }, key
  );
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method:'POST', headers:{'content-type':'application/x-www-form-urlencoded'},
    body:`grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${encodeURIComponent(assertion)}`
  });
  const d = await r.json();
  if (!r.ok || !d.access_token) throw new Error('Google servis yetkilendirmesi başarısız.');
  return d.access_token;
}

function firestoreValue(v) {
  if (v === null) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue:v };
  if (typeof v === 'number' && Number.isInteger(v)) return { integerValue:String(v) };
  if (typeof v === 'number') return { doubleValue:v };
  if (typeof v === 'string') return { stringValue:v };
  if (Array.isArray(v)) return { arrayValue:{ values:v.map(firestoreValue) } };
  if (typeof v === 'object') return { mapValue:{ fields:Object.fromEntries(Object.entries(v).map(([k,x])=>[k,firestoreValue(x)])) } };
  return { nullValue:null };
}
function firestoreFields(obj) { return Object.fromEntries(Object.entries(obj).map(([k,v])=>[k,firestoreValue(v)])); }

function decodeFirestoreValue(v) {
  if (!v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('nullValue' in v) return null;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeFirestoreValue);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k,x])=>[k,decodeFirestoreValue(x)]));
  return null;
}

async function firestoreGet(env, accessToken, collection, id) {
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/databases/(default)/documents/${collection}/${encodeURIComponent(id)}`;
  const r = await fetch(url, { headers:{ Authorization:`Bearer ${accessToken}` } });
  if (r.status === 404) return null;
  const d = await r.json();
  if (!r.ok) throw new Error(d.error?.message || 'Firestore okuma hatası.');
  return Object.fromEntries(Object.entries(d.fields || {}).map(([k,v])=>[k,decodeFirestoreValue(v)]));
}

async function firestoreWrite(env, accessToken, collection, id, obj, exists = false) {
  const base = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(env.FIREBASE_PROJECT_ID)}/databases/(default)/documents/${collection}/${encodeURIComponent(id)}`;
  const url = exists ? base : `${base}?documentId=${encodeURIComponent(id)}`;
  const r = await fetch(url, {
    method: exists ? 'PATCH' : 'POST',
    headers:{ Authorization:`Bearer ${accessToken}`, 'content-type':'application/json' },
    body:JSON.stringify({ fields:firestoreFields(obj) })
  });
  const d = await r.json();
  if (!r.ok) throw new Error(d.error?.message || 'Firestore yazma hatası.');
  return d;
}

async function pbkdf2(password, saltB64, iterations=120000) {
  let salt;
  if (saltB64) salt = fromB64(saltB64);
  else { salt = crypto.getRandomValues(new Uint8Array(16)); }
  const keyMaterial = await crypto.subtle.importKey('raw', utf8(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({name:'PBKDF2', salt, iterations, hash:'SHA-256'}, keyMaterial, 256);
  return { hash:b64std(bits), salt:b64std(salt), algo:'PBKDF2-SHA256', iterations };
}

async function constantTimeEqual(a,b) {
  const aa=utf8(a||''), bb=utf8(b||'');
  if (aa.length !== bb.length) return false;
  let x=0; for(let i=0;i<aa.length;i++) x |= aa[i]^bb[i];
  return x===0;
}

async function customToken(env, username) {
  const now=Math.floor(Date.now()/1000);
  const key=await importPrivateKey(env.FIREBASE_PRIVATE_KEY);
  return signJwt(
    { alg:'RS256', typ:'JWT' },
    {
      iss:env.FIREBASE_CLIENT_EMAIL,
      sub:env.FIREBASE_CLIENT_EMAIL,
      aud:'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
      iat:now,
      exp:now+3600,
      uid:username,
      claims:{ username, admin: username === (env.ADMIN_USERNAME || 'A_UR_A_XX') }
    }, key
  );
}

function validUsername(u) { return typeof u === 'string' && /^[A-Za-z0-9_.-]{3,32}$/.test(u); }
function age(dateStr) {
  const b=new Date(`${dateStr}T00:00:00`); if(Number.isNaN(b.getTime())) return -1;
  const t=new Date(); let a=t.getFullYear()-b.getFullYear(); const m=t.getMonth()-b.getMonth(); if(m<0 || (m===0 && t.getDate()<b.getDate())) a--; return a;
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return cors(request, new Response(null,{status:204}));
    const url=new URL(request.url);
    if (request.method !== 'POST' || !['/api/register','/api/login'].includes(url.pathname)) return cors(request,json({ok:false,message:'Not found.'},404));
    try {
      const body=await request.json();
      const username=String(body.username||'').trim();
      if (!validUsername(username)) return cors(request,json({ok:false,message:'Kullanıcı adı 3-32 karakter olmalı ve yalnızca harf, rakam, ., _, - içerebilir.'},400));
      const access=await googleAccessToken(env);
      const existing=await firestoreGet(env,access,'users',username);

      if (url.pathname === '/api/login') {
        if (!existing) return cors(request,json({ok:false,message:'Hatalı kullanıcı adı veya şifre.'},401));
        const password=String(body.password||'');
        const stored=existing.password;
        let valid=false;
        if (stored && stored.algo === 'PBKDF2-SHA256') {
          const calc=await pbkdf2(password,stored.salt,Number(stored.iterations)||120000);
          valid=await constantTimeEqual(calc.hash,stored.hash);
        } else if (typeof stored === 'string') valid=await constantTimeEqual(stored,password);
        if (!valid) return cors(request,json({ok:false,message:'Hatalı kullanıcı adı veya şifre.'},401));
        const updated={...existing,lastIpHash:body.clientIpHash||null,lastDeviceHash:body.clientDeviceHash||null,lastSeenAt:Date.now()};
        await firestoreWrite(env,access,'users',username,updated,true);
        return cors(request,json({ok:true,customToken:await customToken(env,username)}));
      }

      const firstName=String(body.firstName||'').trim();
      const lastName=String(body.lastName||'').trim();
      const region=String(body.region||'').trim();
      const birthDate=String(body.birthDate||'').trim();
      if (existing) return cors(request,json({ok:false,message:'Bu kullanıcı adı önceden alınmış.'},409));
      if (!firstName || !lastName || !region || !birthDate) return cors(request,json({ok:false,message:'Ad, soyad, bölge ve doğum tarihi zorunludur.'},400));
      if (age(birthDate) < 15) return cors(request,json({ok:false,message:'Aura Ultra X\'e üye olabilmek için en az 15 yaşında olmanız gerekmektedir.'},400));
      if (body.kvkkAccepted !== true && body.kvkkAccepted !== 'true') return cors(request,json({ok:false,message:'KVKK onayı gerekli.'},400));
      const passwordRecord=body.passwordRecord;
      if (!passwordRecord || passwordRecord.algo !== 'PBKDF2-SHA256' || !passwordRecord.hash || !passwordRecord.salt) return cors(request,json({ok:false,message:'Geçersiz şifre kaydı.'},400));
      const doc={
        username, firstName, lastName, displayName:`${firstName} ${lastName}`.trim(), region, birthDate,
        password:passwordRecord, googleUid:body.googleUid||null, googleEmail:body.googleEmail||null,
        createdAt:Date.now(), lastSeenAt:Date.now(), lastIpHash:body.clientIpHash||null, lastDeviceHash:body.clientDeviceHash||null,
        verified:false, isLider:false, bio:'', mood:''
      };
      await firestoreWrite(env,access,'users',username,doc,false);
      return cors(request,json({ok:true,customToken:await customToken(env,username)}));
    } catch (e) {
      console.error(e);
      return cors(request,json({ok:false,message:e?.message || 'Sunucu hatası.'},500));
    }
  }
};
