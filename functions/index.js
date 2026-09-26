const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const ADMIN_USERNAME = "A_UR_A_XX";

function normalizeUsername(value) {
  return String(value || "").trim();
}
function requireAuth(request) {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");
  return request.auth.uid;
}
async function getUsername(uid) {
  const snap = await db.collection("accountLinks").doc(uid).get();
  const username = normalizeUsername(snap.data()?.username);
  if (!username) throw new HttpsError("failed-precondition", "Hesap bağlantısı bulunamadı.");
  return username;
}
async function isSystemAdminUid(uid) {
  const snap = await db.collection("users").doc(ADMIN_USERNAME).get();
  return snap.exists && snap.data()?.googleUid === uid;
}
function ensureString(value, name, max = 5000) {
  const v = String(value ?? "").trim();
  if (!v || v.length > max) throw new HttpsError("invalid-argument", `${name} geçersiz.`);
  return v;
}
function makePasswordRecord(password, iterations = 150000) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.pbkdf2Sync(String(password), salt, iterations, 32, "sha256");
  return { algo: "PBKDF2-SHA256", iterations, salt: salt.toString("base64"), hash: hash.toString("base64") };
}
function verifyPassword(password, stored) {
  if (!stored || stored.algo !== "PBKDF2-SHA256" || !stored.hash || !stored.salt) return false;
  const iterations = Number(stored.iterations) || 150000;
  const salt = Buffer.from(stored.salt, "base64");
  const expected = Buffer.from(stored.hash, "base64");
  const derived = crypto.pbkdf2Sync(String(password), salt, iterations, expected.length || 32, "sha256");
  return derived.length === expected.length && crypto.timingSafeEqual(derived, expected);
}
function safeUsername(username) {
  if (!/^[A-Za-z0-9._-]{3,32}$/.test(username)) {
    throw new HttpsError("invalid-argument", "Geçersiz kullanıcı adı.");
  }
}
function hashRoomPassword(password) {
  return makePasswordRecord(password, 180000);
}
function getRoomId(roomId) {
  const id = String(roomId || "").trim();
  if (!id || id.length > 80 || /[<>"'`&]/.test(id)) throw new HttpsError("invalid-argument", "Geçersiz oda adı.");
  return id;
}

exports.loginWithCredentials = onCall(async (request) => {
  const username = normalizeUsername(request.data?.username);
  const password = String(request.data?.password || "");
  const deviceHash = String(request.data?.deviceHash || "").slice(0, 256);
  safeUsername(username);
  if (!password) throw new HttpsError("invalid-argument", "Kullanıcı adı ve şifre gereklidir.");
  const rawIp = request.rawRequest?.ip || request.rawRequest?.headers?.['x-forwarded-for']?.split(',')[0]?.trim() || '';
  if (rawIp && username !== ADMIN_USERNAME) {
    const ipHash = crypto.createHash('sha256').update(String(rawIp)).digest('hex');
    if ((await db.collection('bannedIPs').doc(ipHash).get()).exists) throw new HttpsError('permission-denied', 'Bu ağ engellenmiştir.');
  }
  if (deviceHash && username !== ADMIN_USERNAME && (await db.collection('bannedDevices').doc(deviceHash).get()).exists) throw new HttpsError('permission-denied', 'Bu cihaz engellenmiştir.');
  let credSnap = await db.collection("privateCredentials").doc(username).get();
  let cred = credSnap.exists ? (credSnap.data() || {}) : null;
  const userSnap = await db.collection("users").doc(username).get();
  const user = userSnap.data() || {};
  if (!credSnap.exists) {
    // Tek seferlik legacy geçiş: eski password alanı doğruysa sunucu tarafında
    // privateCredentials'a taşınır ve kullanıcı belgesinden hassas alan kaldırılır.
    const legacy = user.password;
    let validLegacy = false;
    if (typeof legacy === "string") validLegacy = legacy === password;
    else if (legacy?.algo === "PBKDF2-SHA256") validLegacy = verifyPassword(password, legacy);
    if (!validLegacy || !user.googleUid) throw new HttpsError("unauthenticated", "Hatalı kullanıcı adı veya şifre.");
    const privateRef = db.collection("privateCredentials").doc(username);
    cred = { googleUid: user.googleUid, googleEmail: user.googleEmail || null, password: typeof legacy === "string" ? makePasswordRecord(password) : legacy, migratedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() };
    await db.runTransaction(async tx => {
      const freshCred = await tx.get(privateRef);
      if (!freshCred.exists) tx.set(privateRef, cred);
      tx.update(userSnap.ref, { password: FieldValue.delete(), passwordMigratedAt: FieldValue.serverTimestamp() });
    });
  }
  if (!cred?.googleUid || !verifyPassword(password, cred.password)) throw new HttpsError("unauthenticated", "Hatalı kullanıcı adı veya şifre.");
  const accountRef = db.collection("accountLinks").doc(cred.googleUid);
  const accountSnap = await accountRef.get();
  if (!accountSnap.exists) await accountRef.set({ username, googleUid: cred.googleUid, migratedAt: FieldValue.serverTimestamp() });
  else if (accountSnap.data()?.username !== username) throw new HttpsError("permission-denied", "Hesap bağlantısı uyuşmuyor.");
  if (user.banned === true && username !== ADMIN_USERNAME) throw new HttpsError("permission-denied", "Bu hesap engellenmiştir.");
  const token = await admin.auth().createCustomToken(cred.googleUid, { username, aurax: true });
  return { token, username };
});

exports.registerWithGoogle = onCall(async (request) => {
  const uid = requireAuth(request);
  const username = normalizeUsername(request.data?.username);
  const password = String(request.data?.password || "");
  const firstName = ensureString(request.data?.firstName, "Ad", 80);
  const lastName = ensureString(request.data?.lastName, "Soyad", 80);
  const region = ensureString(request.data?.region, "Bölge", 80);
  const birthDate = ensureString(request.data?.birthDate, "Doğum tarihi", 30);
  const kvkkAccepted = request.data?.kvkkAccepted === true;
  safeUsername(username);
  if (!kvkkAccepted) throw new HttpsError("failed-precondition", "Kayıt koşullarının onayı gerekli.");
  if (password.length < 8) throw new HttpsError("invalid-argument", "Şifre en az 8 karakter olmalıdır.");
  const authUser = await admin.auth().getUser(uid);
  if (!authUser.email || authUser.emailVerified === false) throw new HttpsError("failed-precondition", "Google hesabının e-posta doğrulaması gerekli.");
  const birth = new Date(`${birthDate}T00:00:00Z`);
  if (Number.isNaN(birth.getTime())) throw new HttpsError("invalid-argument", "Geçersiz doğum tarihi.");
  const today = new Date();
  let age = today.getUTCFullYear() - birth.getUTCFullYear();
  const md = today.getUTCMonth() - birth.getUTCMonth();
  if (md < 0 || (md === 0 && today.getUTCDate() < birth.getUTCDate())) age--;
  if (age < 15) throw new HttpsError("permission-denied", "Kayıt için minimum yaş koşulu sağlanmıyor.");

  const accountRef = db.collection("accountLinks").doc(uid);
  const userRef = db.collection("users").doc(username);
  const credRef = db.collection("privateCredentials").doc(username);
  await db.runTransaction(async tx => {
    const [linkSnap, userSnap, credSnap] = await Promise.all([tx.get(accountRef), tx.get(userRef), tx.get(credRef)]);
    if (linkSnap.exists || credSnap.exists) throw new HttpsError("already-exists", "Bu Google hesabı zaten bir Aura X hesabına bağlı.");
    if (userSnap.exists) throw new HttpsError("already-exists", "Bu kullanıcı adı önceden alınmış.");
    tx.set(accountRef, { username, googleUid: uid, createdAt: FieldValue.serverTimestamp() });
    tx.set(userRef, {
      username, firstName, lastName, displayName: `${firstName} ${lastName}`,
      region, birthDate, googleUid: uid, googleEmail: authUser.email,
      createdAt: FieldValue.serverTimestamp(), lastSeenAt: FieldValue.serverTimestamp(),
      restricted: false, banned: false, votes: 0, followers: [], following: [],
      verified: false, special: false, avatarUrl: null, avatarPath: null
    });
    tx.set(credRef, { googleUid: uid, googleEmail: authUser.email, password: makePasswordRecord(password), createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  });
  return { username };
});

exports.resetPasswordWithGoogle = onCall(async (request) => {
  const uid = requireAuth(request);
  const newPassword = String(request.data?.newPassword || "");
  if (newPassword.length < 8) throw new HttpsError("invalid-argument", "Yeni şifre en az 8 karakter olmalıdır.");
  const username = await getUsername(uid);
  const credRef = db.collection("privateCredentials").doc(username);
  const credSnap = await credRef.get();
  if (!credSnap.exists || credSnap.data()?.googleUid !== uid) throw new HttpsError("permission-denied", "Google hesabı bu kullanıcıya bağlı değil.");
  await credRef.update({ password: makePasswordRecord(newPassword), updatedAt: FieldValue.serverTimestamp(), passwordResetAt: FieldValue.serverTimestamp() });
  return { username };
});

exports.changeMyPassword = onCall(async (request) => {
  const uid = requireAuth(request);
  const currentPassword = String(request.data?.currentPassword || "");
  const newPassword = String(request.data?.newPassword || "");
  if (!currentPassword || newPassword.length < 8) throw new HttpsError("invalid-argument", "Şifre bilgileri geçersiz.");
  const username = await getUsername(uid);
  const ref = db.collection("privateCredentials").doc(username);
  const snap = await ref.get();
  const cred = snap.data() || {};
  if (!snap.exists || cred.googleUid !== uid || !verifyPassword(currentPassword, cred.password)) throw new HttpsError("unauthenticated", "Mevcut şifre hatalı.");
  await ref.update({ password: makePasswordRecord(newPassword), updatedAt: FieldValue.serverTimestamp(), passwordChangedAt: FieldValue.serverTimestamp() });
  return { changed: true };
});

exports.savePushToken = onCall(async (request) => {
  const uid = requireAuth(request);
  const username = await getUsername(uid);
  const token = ensureString(request.data?.token, "Bildirim anahtarı", 4096);
  const platform = String(request.data?.platform || "web").slice(0, 30);
  const tokenId = crypto.createHash("sha256").update(token).digest("hex").slice(0, 40);
  await db.collection("users").doc(username).collection("pushTokens").doc(tokenId).set({ token, platform, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { saved: true };
});

exports.sendAuraNotification = onCall(async (request) => {
  const uid = requireAuth(request);
  const from = await getUsername(uid);
  const to = normalizeUsername(request.data?.to);
  if (!to) throw new HttpsError("invalid-argument", "Bildirim hedefi gerekli.");
  const type = String(request.data?.type || "notification").slice(0, 60);
  const text = ensureString(request.data?.text, "Bildirim metni", 1000);
  if (["admin_message", "restriction"].includes(type) && !(await isSystemAdminUid(uid))) {
    throw new HttpsError("permission-denied", "Bu bildirim türünü yalnızca sistem yöneticisi gönderebilir.");
  }
  const extra = (request.data?.extra && typeof request.data.extra === "object") ? request.data.extra : {};
  const allowedExtra = {};
  for (const key of ["roomId","postId","messageId","replyToId","messageBody","recipientUsername","roomName","oldRoomId"]) {
    if (extra[key] !== undefined) allowedExtra[key] = String(extra[key]).slice(0, 500);
  }
  if (to === from && type !== "admin_message") {
    return { skipped: true };
  }
  const ref = db.collection("notifications").doc();
  await ref.set({ to, from, type, text, read: false, createdAt: FieldValue.serverTimestamp(), ...allowedExtra });
  return { id: ref.id };
});


exports.sendRoomInviteSecure = onCall(async (request) => {
  const uid = requireAuth(request);
  const from = await getUsername(uid);
  const to = normalizeUsername(request.data?.to);
  const roomName = getRoomId(request.data?.roomName);
  const password = String(request.data?.password || "");
  if (!to || to === from || !password) throw new HttpsError("invalid-argument", "Geçersiz oda daveti.");
  const roomSnap = await db.collection("rooms").doc(roomName).get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Oda bulunamadı.");
  const room = roomSnap.data() || {};
  const adminAllowed = room.ownerUid === uid || room.admin === from || (Array.isArray(room.admins) && room.admins.includes(from)) || await isSystemAdminUid(uid);
  if (!adminAllowed) throw new HttpsError("permission-denied", "Bu odaya davet gönderme yetkiniz yok.");
  const secretSnap = await db.collection("roomSecrets").doc(roomName).get();
  let valid = false;
  if (secretSnap.exists) valid = verifyPassword(password, secretSnap.data()?.password);
  else if (room.password) valid = String(room.password) === password;
  if (!valid) throw new HttpsError("permission-denied", "Oda şifresi hatalı.");
  const ref = db.collection("notifications").doc();
  await ref.set({ to, from, type: "room_invite", text: `${from} sizi "${roomName}" odasına davet etti.`, roomId: roomName, roomName, read: false, createdAt: FieldValue.serverTimestamp() });
  return { sent: true };
});

exports.createSelfNotification = onCall(async (request) => {
  const uid = requireAuth(request);
  const username = await getUsername(uid);
  const type = String(request.data?.type || "notification").slice(0, 60);
  const text = ensureString(request.data?.text, "Bildirim metni", 1000);
  const extra = (request.data?.extra && typeof request.data.extra === "object") ? request.data.extra : {};
  const ref = db.collection("notifications").doc();
  await ref.set({ to: username, from: username, type, text, read: false, direction: "sent", createdAt: FieldValue.serverTimestamp(), ...extra });
  return { id: ref.id };
});


exports.castVote = onCall(async (request) => {
  const uid = requireAuth(request);
  const voter = await getUsername(uid);
  const target = normalizeUsername(request.data?.target);
  if (!target || target === voter || target === ADMIN_USERNAME) throw new HttpsError("invalid-argument", "Geçersiz oy hedefi.");
  const voteId = `${voter}__${target}`.replace(/[^a-zA-Z0-9_-]/g, '_');
  const voteRef = db.collection("votes").doc(voteId);
  const targetRef = db.collection("users").doc(target);
  await db.runTransaction(async tx => {
    const [voteSnap, targetSnap] = await Promise.all([tx.get(voteRef), tx.get(targetRef)]);
    if (voteSnap.exists) throw new HttpsError("already-exists", "Bu kullanıcıya zaten oy verdiniz.");
    if (!targetSnap.exists) throw new HttpsError("not-found", "Kullanıcı bulunamadı.");
    tx.create(voteRef, { voter, target, createdAt: FieldValue.serverTimestamp() });
    tx.update(targetRef, { votes: Number(targetSnap.data()?.votes || 0) + 1 });
  });
  return { voted: true };
});

exports.createRoomSecure = onCall(async (request) => {
  const uid = requireAuth(request);
  const username = await getUsername(uid);
  const name = getRoomId(request.data?.roomName);
  const password = String(request.data?.password || "");
  if (!password) throw new HttpsError("invalid-argument", "Oda şifresi zorunludur.");
  const ref = db.collection("rooms").doc(name);
  const exists = await ref.get();
  if (exists.exists) throw new HttpsError("already-exists", "Bu isimde bir oda zaten mevcut.");
  const roomData = {
    admin: username, ownerUid: uid, admins: [], members: [username], muted: [], restrictedMembers: [], messages: [],
    createdAt: FieldValue.serverTimestamp(),
    videoAccess: { enabled: !!request.data?.youtubeEnabled, grantedMinutes: 0, grantedAt: request.data?.youtubeEnabled ? Date.now() : null, expiresAt: null },
    drawingAccess: { enabled: !!request.data?.drawingEnabled, grantedAt: request.data?.drawingEnabled ? Date.now() : null },
    roomAccess: { locked: false }, youtubeQueue: [], youtubeCurrentIndex: 0, pinnedMessageId: null
  };
  await db.runTransaction(async tx => {
    tx.create(ref, roomData);
    tx.create(db.collection("roomSecrets").doc(name), { password: hashRoomPassword(password), createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  });
  return { roomName: name };
});

async function checkRoomAccess(username, roomData) {
  if (!roomData) throw new HttpsError("not-found", "Oda bulunamadı.");
  const locked = roomData.systemLocked === true || roomData.auracellLocked === true || roomData.auraCellLocked === true || roomData.roomAccess?.systemLocked === true || (roomData.roomAccess?.locked === true);
  if (locked) throw new HttpsError("permission-denied", "Bu oda şu anda girişe kapalıdır.");
  if (Array.isArray(roomData.restrictedMembers) && roomData.restrictedMembers.includes(username)) throw new HttpsError("permission-denied", "Bu odaya girişiniz kısıtlandı.");
}

exports.joinRoomSecure = onCall(async (request) => {
  const uid = requireAuth(request);
  const username = await getUsername(uid);
  const roomName = getRoomId(request.data?.roomName);
  const suppliedPassword = String(request.data?.password || "");
  const roomRef = db.collection("rooms").doc(roomName);
  const secretRef = db.collection("roomSecrets").doc(roomName);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Böyle bir oda bulunamadı.");
  const room = roomSnap.data() || {};
  await checkRoomAccess(username, room);
  if (Array.isArray(room.members) && room.members.includes(username)) return { joined: true, alreadyMember: true };
  let secretSnap = await secretRef.get();
  if (!secretSnap.exists && room.password) {
    // Legacy migration: doğrula, ardından hassas alanı kaldır.
    if (String(room.password) !== suppliedPassword) throw new HttpsError("permission-denied", "Oda şifresi hatalı.");
    await db.runTransaction(async tx => {
      const fresh = await tx.get(roomRef);
      const freshSecret = await tx.get(secretRef);
      if (!fresh.exists) throw new HttpsError("not-found", "Oda bulunamadı.");
      if (!freshSecret.exists) tx.set(secretRef, { password: hashRoomPassword(suppliedPassword), migratedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
      tx.update(roomRef, { password: FieldValue.delete() });
    });
    secretSnap = await secretRef.get();
  }
  if (!secretSnap.exists || !verifyPassword(suppliedPassword, secretSnap.data()?.password)) throw new HttpsError("permission-denied", "Oda şifresi hatalı.");
  await roomRef.update({ members: FieldValue.arrayUnion(username) });
  return { joined: true };
});

exports.changeRoomSettingsSecure = onCall(async (request) => {
  const uid = requireAuth(request);
  const username = await getUsername(uid);
  const oldName = getRoomId(request.data?.roomName);
  const newName = getRoomId(request.data?.newRoomName || oldName);
  const newPassword = request.data?.newPassword === undefined ? null : String(request.data.newPassword);
  const roomRef = db.collection("rooms").doc(oldName);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Oda bulunamadı.");
  const room = roomSnap.data() || {};
  const adminAllowed = room.ownerUid === uid || room.admin === username || (Array.isArray(room.admins) && room.admins.includes(username)) || await isSystemAdminUid(uid);
  if (!adminAllowed) throw new HttpsError("permission-denied", "Bu işlem yalnızca oda yöneticilerine aittir.");
  const secretRef = db.collection("roomSecrets").doc(oldName);
  let secretSnap = await secretRef.get();
  const currentPassword = room.password || null;
  if (newName !== oldName) {
    const newRef = db.collection("rooms").doc(newName);
    if ((await newRef.get()).exists) throw new HttpsError("already-exists", "Bu isimde bir oda zaten mevcut.");
    let secretData = secretSnap.exists ? secretSnap.data() : null;
    if (!secretData && currentPassword) secretData = { password: hashRoomPassword(String(currentPassword)) };
    if (!secretData) throw new HttpsError("failed-precondition", "Oda şifresi kaydı bulunamadı.");
    const cleanRoom = { ...room };
    delete cleanRoom.password;
    cleanRoom.renamedFrom = oldName;
    cleanRoom.renamedBy = username;
    cleanRoom.renamedAt = FieldValue.serverTimestamp();
    const nextSecret = newPassword ? { ...secretData, password: hashRoomPassword(newPassword), updatedAt: FieldValue.serverTimestamp() } : { ...secretData, updatedAt: FieldValue.serverTimestamp() };
    await db.runTransaction(async tx => {
      tx.create(newRef, cleanRoom);
      tx.set(db.collection("roomSecrets").doc(newName), nextSecret);
      tx.delete(roomRef);
      tx.delete(secretRef);
    });
    return { roomName: newName, renamed: true };
  }
  const update = { password: FieldValue.delete(), passwordChangedAt: FieldValue.serverTimestamp(), passwordChangedBy: username };
  if (newPassword) await secretRef.set({ password: hashRoomPassword(newPassword), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  else if (!secretSnap.exists && currentPassword) await secretRef.set({ password: hashRoomPassword(String(currentPassword)), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await roomRef.update(update);
  return { roomName: oldName, changed: true };
});

exports.migrateLegacyRoomSecrets = onCall(async (request) => {
  const uid = requireAuth(request);
  if (!(await isSystemAdminUid(uid))) throw new HttpsError("permission-denied", "Yalnızca sistem yöneticisi.");
  let migrated = 0;
  const snap = await db.collection("rooms").limit(500).get();
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (!data.password) continue;
    const secretRef = db.collection("roomSecrets").doc(doc.id);
    const secretSnap = await secretRef.get();
    if (!secretSnap.exists) await secretRef.set({ password: hashRoomPassword(String(data.password)), migratedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    await doc.ref.update({ password: FieldValue.delete() });
    migrated++;
  }
  return { migrated };
});

exports.deleteMyAccount = onCall(async (request) => {
  const uid = requireAuth(request);
  const username = await getUsername(uid);
  if (!username || username === ADMIN_USERNAME) throw new HttpsError("permission-denied", "Bu hesap bu alandan silinemez.");
  const batch = db.batch();
  batch.delete(db.collection("users").doc(username));
  batch.delete(db.collection("accountLinks").doc(uid));
  batch.delete(db.collection("privateCredentials").doc(username));
  batch.delete(db.collection("statuses").doc(username));
  const roomsSnap = await db.collection("rooms").where("ownerUid", "==", uid).limit(400).get();
  for (const doc of roomsSnap.docs) {
    batch.delete(doc.ref);
    batch.delete(db.collection("roomSecrets").doc(doc.id));
  }
  const tokens = await db.collection("users").doc(username).collection("pushTokens").limit(400).get();
  for (const d of tokens.docs) batch.delete(d.ref);
  await batch.commit();
  await admin.auth().deleteUser(uid).catch(err => { if (err?.code !== "auth/user-not-found") throw err; });
  return { deleted: true, username };
});

exports.pushAuraNotification = onDocumentCreated("notifications/{notificationId}", async (event) => {
  const data = event.data?.data();
  if (!data?.to) return null;
  const tokenSnap = await db.collection("users").doc(String(data.to)).collection("pushTokens").get();
  const tokens = tokenSnap.docs.map(d => d.data()?.token).filter(Boolean);
  if (!tokens.length) return null;
  const message = { tokens, data: { title: "Aura Ultra X", body: String(data.text || "Yeni bildiriminiz var."), type: String(data.type || "notification"), roomId: String(data.roomId || ""), notificationId: event.params.notificationId } };
  const result = await admin.messaging().sendEachForMulticast(message);
  const invalidCodes = new Set(["messaging/invalid-registration-token", "messaging/registration-token-not-registered"]);
  const cleanup = [];
  result.responses.forEach((response, index) => { if (!response.success && invalidCodes.has(response.error?.code)) cleanup.push(tokenSnap.docs[index].ref.delete().catch(() => {})); });
  await Promise.all(cleanup);
  return null;
});
