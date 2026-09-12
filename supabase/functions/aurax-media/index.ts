import { createClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@6";

const PROJECT_ID = Deno.env.get("AURAX_FIREBASE_PROJECT_ID") || "aura-ultra-x";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("AURAX_SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKET = "media";
const JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com")
);
const adminDb = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-aura-path",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function actor(req: Request) {
  const raw = req.headers.get("authorization") || "";
  const token = raw.startsWith("Bearer ") ? raw.slice(7) : "";
  if (!token) throw new Error("Firebase oturumu gerekli.");
  const { payload } = await jwtVerify(token, JWKS, {
    algorithms: ["RS256"],
    issuer: `https://securetoken.google.com/${PROJECT_ID}`,
    audience: PROJECT_ID
  });
  if (!payload.sub || typeof payload.sub !== "string") throw new Error("Geçersiz kullanıcı.");
  const { data: identity } = await adminDb.from("aurax_identities")
    .select("username").eq("firebase_uid", payload.sub).maybeSingle();
  if (!identity?.username) throw new Error("Aura X profili bulunamadı.");
  const { data: admin } = await adminDb.from("aurax_admins")
    .select("username").eq("firebase_uid", payload.sub).eq("active", true).maybeSingle();
  return { uid: payload.sub, username: identity.username, isAdmin: !!admin };
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" }
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const me = await actor(req);
    const path = (req.headers.get("x-aura-path") || "").replace(/^\/+/, "");
    const url = new URL(req.url);
    const action = url.searchParams.get("action") || "upload";

    if (!path || path.includes("..") || path.length > 500) {
      return json({ error: "Geçersiz medya yolu." }, 400);
    }

    const ownPrefix = [
      `avatars/${me.username}_`,
      `postImages/${me.username}_`,
      `postVideos/${me.username}_`,
      `statusImages/${me.username}_`
    ];
    const canUsePath = me.isAdmin || ownPrefix.some(prefix => path.startsWith(prefix)) ||
      (me.isAdmin && path.startsWith("announcements/"));

    if (action === "delete") {
      if (!canUsePath) return json({ error: "Bu medya dosyasını silme yetkiniz yok." }, 403);
      const { error } = await adminDb.storage.from(BUCKET).remove([path]);
      if (error) throw error;
      return json({ ok: true });
    }

    const contentType = req.headers.get("content-type") || "application/octet-stream";
    const bytes = new Uint8Array(await req.arrayBuffer());
    if (!bytes.length) return json({ error: "Boş dosya." }, 400);
    if (bytes.length > 200 * 1024 * 1024) return json({ error: "Dosya 200 MB sınırını aşamaz." }, 413);

    // Dosya yolları kullanıcı/medya biçiminde tutulur; kullanıcı başkasının
    // klasörüne keyfi yazamaz. Admin tüm yolları kullanabilir.
    if (!canUsePath) return json({ error: "Bu medya yoluna yazma yetkiniz yok." }, 403);

    const { error } = await adminDb.storage.from(BUCKET).upload(path, bytes, {
      contentType,
      upsert: true,
      cacheControl: "31536000"
    });
    if (error) throw error;

    const publicUrl = `${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${encodeURI(path)}`;
    return json({ ok: true, path, publicUrl });
  } catch (e: any) {
    console.error(e);
    return json({ error: e?.message || "Medya işlemi başarısız." }, 500);
  }
});
