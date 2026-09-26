const crypto = require('crypto');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { setGlobalOptions } = require('firebase-functions/v2');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');

initializeApp();
setGlobalOptions({ maxInstances: 20 });
const db = getFirestore();
const auth = getAuth();
const messaging = getMessaging();

function verifyPassword(password, stored) {
  if (typeof stored === 'string') return stored === password;
  if (!stored || stored.algo !== 'PBKDF2-SHA256' || !stored.hash || !stored.salt) return false;
  const iterations = Number(stored.iterations || 120000);
  const derived = crypto.pbkdf2Sync(Buffer.from(String(password), 'utf8'), Buffer.from(String(stored.salt), 'base64'), iterations, 32, 'sha256').toString('base64');
  const a = Buffer.from(derived); const b = Buffer.from(String(stored.hash));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

exports.auraxLogin = onCall(async (request) => {
  const username = String(request.data?.username || '').trim();
  const password = String(request.data?.password || '');
  if (!username || !password) throw new HttpsError('invalid-argument', 'Kullanıcı adı ve şifre gereklidir.');
  if (/[<>"'`&]/.test(username)) throw new HttpsError('invalid-argument', 'Geçersiz kullanıcı adı.');
  const snap = await db.collection('users').doc(username).get();
  if (!snap.exists) throw new HttpsError('unauthenticated', 'Hatalı kullanıcı adı veya şifre.');
  const user = snap.data() || {};
  if (user.banned === true) throw new HttpsError('permission-denied', 'Bu hesap engellenmiştir.');
  if (!user.googleUid || typeof user.googleUid !== 'string') throw new HttpsError('failed-precondition', 'Bu hesap için Firebase kullanıcı kimliği bulunamadı.');
  if (!verifyPassword(password, user.password)) throw new HttpsError('unauthenticated', 'Hatalı kullanıcı adı veya şifre.');
  return { token: await auth.createCustomToken(user.googleUid, { aurax: true, username }) };
});

function chunks(items, size) { const out=[]; for(let i=0;i<items.length;i+=size) out.push(items.slice(i,i+size)); return out; }

exports.sendAuraNotificationPush = onDocumentCreated('notifications/{notificationId}', async (event) => {
  const snap = event.data; if (!snap) return null;
  const n = snap.data() || {};
  if (!n.to || n.direction === 'sent') return null;
  const tokensSnap = await db.collection('users').doc(String(n.to)).collection('pushTokens').get();
  const tokenDocs = tokensSnap.docs.filter(d => d.get('token'));
  if (!tokenDocs.length) return null;
  const text = String(n.text || 'Yeni bildirim').slice(0, 240);
  const data = { title:'Aura Ultra X', body:text, text, type:String(n.type||'notification'), notificationId:String(event.params.notificationId), roomId:String(n.roomId||''), tag:`aurax-${event.params.notificationId}` };
  for (const group of chunks(tokenDocs, 500)) {
    const response = await messaging.sendEach(group.map(d => ({ token:String(d.get('token')), data })));
    const deletions=[];
    response.responses.forEach((result,index) => {
      const code=result.error?.code||'';
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') deletions.push(group[index].ref.delete());
    });
    if (deletions.length) await Promise.all(deletions);
  }
  return null;
});
