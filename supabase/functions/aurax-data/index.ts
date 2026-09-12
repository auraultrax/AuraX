import { createClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@6";

const FIREBASE_PROJECT_ID = Deno.env.get("AURAX_FIREBASE_PROJECT_ID") || "aura-ultra-x";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("AURAX_SUPABASE_SERVICE_ROLE_KEY")!;
const GOOGLE_JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com")
);
const adminDb = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8"
};

type Actor = {
  uid: string;
  email: string | null;
  username: string | null;
  isAdmin: boolean;
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: CORS });
}

function bad(message: string, status = 400, code?: string) {
  return json({ error: message, code }, status);
}

async function verifyFirebase(req: Request): Promise<Actor> {
  const auth = req.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) throw Object.assign(new Error("Firebase oturumu gerekli."), { status: 401, code: "AUTH_REQUIRED" });

  const { payload } = await jwtVerify(token, GOOGLE_JWKS, {
    algorithms: ["RS256"],
    issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
    audience: FIREBASE_PROJECT_ID
  });

  if (!payload.sub || typeof payload.sub !== "string") {
    throw Object.assign(new Error("Geçersiz Firebase kullanıcı kimliği."), { status: 401, code: "AUTH_INVALID" });
  }

  const uid = payload.sub;
  const email = typeof payload.email === "string" ? payload.email : null;

  const { data: identity } = await adminDb
    .from("aurax_identities")
    .select("username,email")
    .eq("firebase_uid", uid)
    .maybeSingle();

  const { data: adminRow } = await adminDb
    .from("aurax_admins")
    .select("username,active")
    .eq("firebase_uid", uid)
    .eq("active", true)
    .maybeSingle();

  return {
    uid,
    email: identity?.email || email,
    username: adminRow?.username || identity?.username || null,
    isAdmin: !!adminRow
  };
}

function isSafeCollection(collection: string) {
  return /^[A-Za-z0-9_\/-]{1,180}$/.test(collection);
}

function isOwnUserDoc(actor: Actor, collection: string, docId: string) {
  return collection === "users" && actor.username === docId;
}

function pathParts(collection: string) {
  return collection.split("/").filter(Boolean);
}

async function resolveDocActor(collection: string, docId: string) {
  if (collection === "users") {
    const { data } = await adminDb
      .from("aurax_documents")
      .select("data")
      .eq("collection", "users")
      .eq("doc_id", docId)
      .maybeSingle();
    return data?.data || null;
  }
  return null;
}

function canReadCollection(actor: Actor, collection: string, docId?: string) {
  if (actor.isAdmin) return true;
  if (collection === "users" || collection === "posts" || collection === "rooms" ||
      collection === "statuses" || collection === "announcements") return true;
  if (collection === "notifications" && docId) return true;
  return false;
}

async function canReadDoc(actor: Actor, collection: string, docId: string, rowData: any) {
  if (actor.isAdmin) return true;
  if (collection === "notifications") return rowData?.to === actor.username || rowData?.from === actor.username;
  if (collection === "users") return true;
  if (collection.startsWith(`users/${actor.username}/pushTokens`)) return true;
  if (["posts", "statuses", "announcements"].includes(collection)) return true;
  if (collection === "rooms") return true;
  return false;
}

async function canCreate(actor: Actor, collection: string, docId: string, data: any) {
  if (actor.isAdmin) return true;
  if (collection === "users") return data?.googleUid === actor.uid && data?.username === actor.username;
  if (collection === "posts" || collection === "statuses") return data?.author === actor.username || data?.username === actor.username;
  if (collection === "rooms") return data?.ownerUid === actor.uid || data?.admin === actor.username;
  if (collection === "notifications") return data?.from === actor.username || data?.to === actor.username;
  if (collection === "reports") return !!actor.username;
  if (collection === `users/${actor.username}/pushTokens`) return true;
  return false;
}

function changedOnly(data: Record<string, any>, allowed: string[]) {
  return Object.keys(data).every(k => allowed.includes(k) || allowed.some(a => k.startsWith(a + ".")));
}

async function canUpdate(
  actor: Actor,
  collection: string,
  docId: string,
  oldData: any,
  patch: Record<string, any>
) {
  if (actor.isAdmin) return true;

  if (collection === "users" && docId === actor.username) {
    return changedOnly(patch, [
      "firstName","lastName","displayName","bio","avatarUrl","avatarPath",
      "region","birthDate","followers","following","votes","verified","special",
      "lastSeenAt","lastIpHash","lastDeviceHash","roomInvite","updatedAt","settings"
    ]);
  }

  if (collection === "posts") return oldData?.author === actor.username && changedOnly(patch, ["text","edited","editedAt","imageUrls","videoUrl"]);
  if (collection === "statuses") return oldData?.username === actor.username || oldData?.author === actor.username;
  if (collection === "notifications") return oldData?.to === actor.username || oldData?.from === actor.username;
  if (collection === `users/${actor.username}/pushTokens`) return true;

  if (collection === "rooms") {
    const isOwner = oldData?.ownerUid === actor.uid || oldData?.admin === actor.username ||
      (Array.isArray(oldData?.admins) && oldData.admins.includes(actor.username));
    if (isOwner) return true;

    const isMember = Array.isArray(oldData?.members) && oldData.members.includes(actor.username);
    if (!isMember) return false;

    const allowed = [
      "members","messages","drawing","youtubeQueue","youtubeCurrentIndex","youtubeSync",
      "videoAccess","drawingAccess","roomPresence","lastMessageAt"
    ];
    return changedOnly(patch, allowed);
  }

  return false;
}

async function canDelete(actor: Actor, collection: string, docId: string, oldData: any) {
  if (actor.isAdmin) return true;
  if (collection === "users") return docId === actor.username;
  if (collection === "posts" || collection === "statuses") return oldData?.author === actor.username || oldData?.username === actor.username;
  if (collection === "notifications") return oldData?.to === actor.username || oldData?.from === actor.username;
  if (collection === `users/${actor.username}/pushTokens`) return true;
  if (collection === "rooms") {
    return oldData?.ownerUid === actor.uid ||
      oldData?.admin === actor.username ||
      (Array.isArray(oldData?.admins) && oldData.admins.includes(actor.username));
  }
  return false;
}

function getPath(obj: any, path: string) {
  return path.split(".").reduce((acc, key) => acc == null ? undefined : acc[key], obj);
}

function setPath(obj: any, path: string, value: any) {
  const keys = path.split(".");
  let cur = obj;
  for (let i = 0; i < keys.length - 1; i++) {
    if (!cur[keys[i]] || typeof cur[keys[i]] !== "object" || Array.isArray(cur[keys[i]])) cur[keys[i]] = {};
    cur = cur[keys[i]];
  }
  cur[keys[keys.length - 1]] = value;
}

function equalValue(a: any, b: any) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function resolveValue(v: any, existing: any) {
  if (!v || typeof v !== "object" || !v.__auraxFieldValue) return v;
  if (v.__auraxFieldValue === "serverTimestamp") return Date.now();
  if (v.__auraxFieldValue === "arrayUnion") {
    const arr = Array.isArray(existing) ? [...existing] : [];
    for (const item of (v.values || [])) if (!arr.some(x => equalValue(x, item))) arr.push(item);
    return arr;
  }
  if (v.__auraxFieldValue === "arrayRemove") {
    const arr = Array.isArray(existing) ? [...existing] : [];
    return arr.filter(x => !(v.values || []).some((item: any) => equalValue(x, item)));
  }
  return v;
}

function mergeData(base: any, patch: any) {
  const out = (base && typeof base === "object" && !Array.isArray(base)) ? structuredClone(base) : {};
  for (const [k, value] of Object.entries(patch || {})) {
    if (k.includes(".")) {
      setPath(out, k, resolveValue(value, getPath(out, k)));
    } else if (value && typeof value === "object" && !Array.isArray(value) && !value.__auraxFieldValue) {
      out[k] = { ...(out[k] && typeof out[k] === "object" && !Array.isArray(out[k]) ? out[k] : {}), ...structuredClone(value) };
    } else {
      out[k] = resolveValue(value, out[k]);
    }
  }
  return out;
}

async function getRow(collection: string, docId: string) {
  return await adminDb.from("aurax_documents")
    .select("collection,doc_id,data,version,created_at,updated_at")
    .eq("collection", collection).eq("doc_id", docId).maybeSingle();
}

function sanitizeUserForClient(data: any, self: boolean, admin: boolean) {
  const out = structuredClone(data || {});
  if (!admin && !self) {
    for (const key of ["googleEmail","googleUid","firebaseUid","ipHash","deviceHash","lastIpHash","lastDeviceHash","kvkkAcceptedAt"]) delete out[key];
  } else if (!admin) {
    // Own sensitive security fields remain usable by the account holder, but never
    // a password hash; passwords are now managed only by Firebase Auth.
    delete out.password;
  } else {
    delete out.password;
  }
  return out;
}

function sanitizeRoomForClient(data: any, isMember: boolean, admin: boolean) {
  const out = structuredClone(data || {});
  if (!admin) {
    delete out.password;
    delete out.restrictedMembers;
    delete out.muted;
    if (!isMember) {
      for (const key of ["messages","drawing","youtubeQueue","youtubeCurrentIndex","youtubeSync"]) delete out[key];
    }
  }
  return out;
}

async function audit(actor: Actor, action: string, collection: string, docId: string | null, metadata: any = {}) {
  await adminDb.from("aurax_audit_log").insert({
    firebase_uid: actor.uid,
    username: actor.username,
    action,
    collection,
    doc_id: docId,
    metadata
  });
}

async function listRows(actor: Actor, body: any) {
  const collection = String(body.collection || "");
  if (!isSafeCollection(collection)) throw Object.assign(new Error("Geçersiz koleksiyon."), { status: 400 });

  let q = adminDb.from("aurax_documents")
    .select("collection,doc_id,data,version,created_at,updated_at")
    .eq("collection", collection);

  const filters = Array.isArray(body.filters) ? body.filters : [];
  for (const f of filters) {
    if (!f?.field || !["==","!="].includes(f.op)) continue;
    // JSONB text extraction for simple equality filters used by the app.
    const value = String(f.value ?? "");
    if (f.op === "==") q = q.eq(`data->>${f.field}`, value);
    else q = q.neq(`data->>${f.field}`, value);
  }

  if (body.orderBy?.field) {
    // Sort in JS because nested JSON keys are not uniformly typed.
  }

  const { data, error } = await q.limit(Math.min(Number(body.limit || 500), 500));
  if (error) throw error;

  let rows = data || [];
  if (body.orderBy?.field) {
    const field = body.orderBy.field;
    const desc = String(body.orderBy.direction || "asc").toLowerCase() === "desc";
    rows = rows.sort((a: any, b: any) => {
      const av = getPath(a.data, field);
      const bv = getPath(b.data, field);
      const na = Number(av); const nb = Number(bv);
      const va = Number.isFinite(na) && av !== "" ? na : (av == null ? "" : String(av));
      const vb = Number.isFinite(nb) && bv !== "" ? nb : (bv == null ? "" : String(bv));
      return (va < vb ? -1 : va > vb ? 1 : 0) * (desc ? -1 : 1);
    });
  }

  if (!actor.isAdmin && !canReadCollection(actor, collection)) {
    rows = [];
  }

  if (!actor.isAdmin && collection === "notifications") {
    rows = rows.filter((r: any) => r.data?.to === actor.username || r.data?.from === actor.username);
  }
  if (!actor.isAdmin && collection === "rooms") {
    rows = rows.map((r: any) => {
      const member = Array.isArray(r.data?.members) && r.data.members.includes(actor.username);
      return { ...r, data: sanitizeRoomForClient(r.data, member, false) };
    });
  } else if (collection === "users") {
    rows = rows.map((r: any) => ({
      ...r,
      data: sanitizeUserForClient(r.data, r.doc_id === actor.username, actor.isAdmin)
    }));
  } else if (!actor.isAdmin && collection === "announcements") {
    rows = rows.map((r: any) => ({ ...r, data: structuredClone(r.data || {}) }));
  }
  return rows;
}

async function setOne(actor: Actor, body: any) {
  const collection = String(body.collection || "");
  const docId = String(body.id || "");
  const data = body.data || {};
  if (!isSafeCollection(collection) || !docId) throw Object.assign(new Error("Geçersiz belge."), { status: 400 });

  const existing = await getRow(collection, docId);
  const oldData = existing.data?.data || null;

  if (!existing.data) {
    if (!(await canCreate(actor, collection, docId, data))) throw Object.assign(new Error("Yetki reddedildi."), { status: 403, code: "PERMISSION_DENIED" });
    const next = mergeData({}, data);
    const { error } = await adminDb.from("aurax_documents").insert({
      collection, doc_id: docId, data: next, version: 1
    });
    if (error) throw error;
    await audit(actor, "create", collection, docId);
    return;
  }

  if (!(await canUpdate(actor, collection, docId, oldData, data))) throw Object.assign(new Error("Yetki reddedildi."), { status: 403, code: "PERMISSION_DENIED" });
  const next = body.merge === false ? mergeData({}, data) : mergeData(oldData, data);
  const nextVersion = Number(existing.data.version || 0) + 1;
  const { error } = await adminDb.from("aurax_documents")
    .update({ data: next, version: nextVersion, updated_at: new Date().toISOString() })
    .eq("collection", collection).eq("doc_id", docId).eq("version", Number(existing.data.version || 0));
  if (error) throw error;
  await audit(actor, "update", collection, docId);
}

async function updateOne(actor: Actor, body: any) {
  return await setOne(actor, { ...body, merge: true });
}

async function deleteOne(actor: Actor, body: any) {
  const collection = String(body.collection || "");
  const docId = String(body.id || "");
  const existing = await getRow(collection, docId);
  if (!existing.data) return;
  if (!(await canDelete(actor, collection, docId, existing.data.data))) {
    throw Object.assign(new Error("Yetki reddedildi."), { status: 403, code: "PERMISSION_DENIED" });
  }
  const { error } = await adminDb.from("aurax_documents")
    .delete().eq("collection", collection).eq("doc_id", docId).eq("version", Number(existing.data.version || 0));
  if (error) throw error;
  await audit(actor, "delete", collection, docId);
}

async function addOne(actor: Actor, body: any) {
  const collection = String(body.collection || "");
  const data = body.data || {};
  if (!isSafeCollection(collection)) throw Object.assign(new Error("Geçersiz koleksiyon."), { status: 400 });
  let id = crypto.randomUUID();
  for (let i = 0; i < 4; i++) {
    const allowed = await canCreate(actor, collection, id, data);
    if (!allowed) throw Object.assign(new Error("Yetki reddedildi."), { status: 403, code: "PERMISSION_DENIED" });
    const { error } = await adminDb.from("aurax_documents").insert({ collection, doc_id: id, data: mergeData({}, data), version: 1 });
    if (!error) {
      await audit(actor, "add", collection, id);
      return id;
    }
    if (error.code !== "23505") throw error;
    id = crypto.randomUUID();
  }
  throw new Error("Belge kimliği oluşturulamadı.");
}

async function transactionOne(actor: Actor, body: any) {
  const reads = body.reads || {};
  const writes = Array.isArray(body.writes) ? body.writes : [];

  // Re-read every document and enforce optimistic concurrency.
  for (const [key, expected] of Object.entries(reads)) {
    const [collection, ...rest] = String(key).split("/");
    const docId = rest.pop() || "";
    const coll = rest.length ? [collection, ...rest].join("/") : collection;
    const row = await getRow(coll, docId);
    const actual = row.data ? Number(row.data.version || 0) : null;
    if (actual !== expected) throw Object.assign(new Error("Veri değişti, işlemi tekrar deneyin."), { status: 409, code: "TRANSACTION_CONFLICT" });
  }

  for (const w of writes) {
    if (w.kind === "set") await setOne(actor, w);
    else if (w.kind === "update") await updateOne(actor, w);
    else if (w.kind === "delete") await deleteOne(actor, w);
  }
}


async function joinRoom(actor: Actor, body: any) {
  const roomId = String(body.id || "");
  const password = String(body.password || "");
  const row = await getRow("rooms", roomId);
  if (!row.data) throw Object.assign(new Error("ROOM_NOT_FOUND"), { status: 404, code: "ROOM_NOT_FOUND" });
  const room = row.data.data || {};
  if (room.deleted === true) throw Object.assign(new Error("Bu oda silinmiş."), { status: 410, code: "ROOM_DELETED" });
  if (!actor.isAdmin && ((room.roomAccess?.locked === true) || room.locked === true))
    throw Object.assign(new Error("Bu oda şu anda girişe kapalıdır."), { status: 403, code: "ROOM_LOCKED" });
  if (!actor.isAdmin && Array.isArray(room.restrictedMembers) && room.restrictedMembers.includes(actor.username))
    throw Object.assign(new Error("Bu odaya girişiniz yönetici tarafından kısıtlandı."), { status: 403, code: "ROOM_RESTRICTED" });
  if (room.password !== password && !actor.isAdmin)
    throw Object.assign(new Error("Oda şifresi hatalı."), { status: 403, code: "ROOM_PASSWORD_INVALID" });

  const members = Array.isArray(room.members) ? [...room.members] : [];
  if (!members.includes(actor.username)) members.push(actor.username);
  const next = { ...room, members };
  const { error } = await adminDb.from("aurax_documents")
    .update({ data: next, version: Number(row.data.version || 0) + 1, updated_at: new Date().toISOString() })
    .eq("collection","rooms").eq("doc_id",roomId).eq("version",Number(row.data.version || 0));
  if (error) throw error;
  await audit(actor, "join_room", "rooms", roomId);
  return { ok: true, room: sanitizeRoomForClient(next, true, actor.isAdmin) };
}

async function registerOne(actor: Actor, body: any) {
  if (!body.username || body.googleUid !== actor.uid) throw Object.assign(new Error("Kayıt kimliği doğrulanamadı."), { status: 403, code: "PERMISSION_DENIED" });
  const username = String(body.username).trim();
  if (!/^[A-Za-z0-9_.-]{3,32}$/.test(username)) throw Object.assign(new Error("Geçersiz kullanıcı adı."), { status: 400 });

  const { data: taken } = await adminDb.from("aurax_documents").select("doc_id").eq("collection","users").eq("doc_id",username).maybeSingle();
  if (taken) throw Object.assign(new Error("USERNAME_EXISTS"), { status: 409, code: "USERNAME_EXISTS" });

  const { data: linked } = await adminDb.from("aurax_identities").select("username").eq("firebase_uid", actor.uid).maybeSingle();
  if (linked) throw Object.assign(new Error("ACCOUNT_LINK_EXISTS"), { status: 409, code: "ACCOUNT_LINK_EXISTS" });

  const payload = {
    id: actor.uid,
    username,
    firstName: String(body.firstName || "").trim(),
    lastName: String(body.lastName || "").trim(),
    displayName: String(body.displayName || "").trim(),
    region: String(body.region || ""),
    birthDate: String(body.birthDate || ""),
    passwordProvider: "firebase",
    googleUid: actor.uid,
    googleEmail: actor.email,
    firebaseUid: actor.uid,
    ipHash: body.ipHash || null,
    deviceHash: body.deviceHash || null,
    createdAt: Date.now(),
    lastSeenAt: Date.now(),
    kvkkAcceptedAt: Number(body.kvkkAcceptedAt || Date.now()),
    restricted: false,
    banned: false,
    votes: 0,
    followers: [],
    following: [],
    verified: false,
    special: false,
    avatarUrl: null,
    avatarPath: null
  };

  // SQL unique constraints protect this insert from concurrent registrations.
  const { error: userErr } = await adminDb.from("aurax_documents").insert({
    collection: "users", doc_id: username, data: payload, version: 1
  });
  if (userErr) {
    if (userErr.code === "23505") throw Object.assign(new Error("USERNAME_EXISTS"), { status: 409, code: "USERNAME_EXISTS" });
    throw userErr;
  }

  const { error: idErr } = await adminDb.from("aurax_identities").insert({
    firebase_uid: actor.uid, username, email: actor.email, provider: "google+password"
  });
  if (idErr) {
    await adminDb.from("aurax_documents").delete().eq("collection","users").eq("doc_id",username);
    if (idErr.code === "23505") throw Object.assign(new Error("ACCOUNT_LINK_EXISTS"), { status: 409, code: "ACCOUNT_LINK_EXISTS" });
    throw idErr;
  }

  await audit(actor, "register", "users", username, { firebaseUid: actor.uid });
  return { ok: true, username };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const actor = await verifyFirebase(req);
    const body = await req.json();
    const op = String(body.op || "");

    if (op === "me") {
      return json({ ok: true, username: actor.username, isAdmin: actor.isAdmin, firebaseUid: actor.uid, email: actor.email });
    }
    if (op === "register") return json(await registerOne(actor, body));
    if (op === "join_room") return json(await joinRoom(actor, body));
    if (op === "get") {
      const collection = String(body.collection || "");
      const docId = String(body.id || "");
      const row = await getRow(collection, docId);
      if (!row.data) return json({ row: null });
      if (!(await canReadDoc(actor, collection, docId, row.data.data))) return bad("Yetki reddedildi.", 403, "PERMISSION_DENIED");
      const out = { ...row.data, data: structuredClone(row.data.data || {}) };
      if (collection === "users") out.data = sanitizeUserForClient(row.data.data, docId === actor.username, actor.isAdmin);
      if (collection === "rooms") {
        const member = actor.isAdmin || (Array.isArray(row.data.data?.members) && row.data.data.members.includes(actor.username));
        out.data = sanitizeRoomForClient(row.data.data, member, actor.isAdmin);
      }
      return json({ row: out });
    }
    if (op === "list") return json({ rows: await listRows(actor, body) });
    if (op === "set") { await setOne(actor, body); return json({ ok: true }); }
    if (op === "update") { await updateOne(actor, body); return json({ ok: true }); }
    if (op === "delete") { await deleteOne(actor, body); return json({ ok: true }); }
    if (op === "add") return json({ id: await addOne(actor, body) });
    if (op === "transaction") { await transactionOne(actor, body); return json({ ok: true }); }

    return bad("Bilinmeyen işlem.", 400, "UNKNOWN_OP");
  } catch (e: any) {
    console.error(e);
    const status = Number(e?.status || 500);
    return bad(e?.message || "Sunucu hatası.", status, e?.code);
  }
});
