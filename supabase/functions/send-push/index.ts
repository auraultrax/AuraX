// Aura X — uygulama kapalıyken cihaz bildirimi gönderir (Web Push).
// Frontend, bildirim DB'ye yazıldıktan sonra bu fonksiyonu çağırır.
// Fonksiyon çağrısı Supabase oturum JWT'siyle doğrulanır ve bildirimin from alanı
// çağıran kullanıcıyla eşleşmiyorsa kesinlikle push gönderilmez.
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@example.com",
  Deno.env.get("VAPID_PUBLIC_KEY") ?? "",
  Deno.env.get("VAPID_PRIVATE_KEY") ?? "",
);

const TITLES: Record<string, string> = {
  like: "Yeni beğeni",
  comment: "Yeni yorum",
  reply: "Yeni yanıt",
  follow: "Yeni takipçi",
  vote: "Yeni oy",
  roommsg: "Oda mesajı",
  room_reply: "Odada yanıt",
  room_private: "Özel mesaj",
  room_invite: "Oda daveti",
  room_invite_request: "Oda isteği",
  draw: "Çizim daveti",
  admin_message: "Duyuru",
  restriction: "Hesap doğrulaması gerekli",
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: corsHeaders });

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!jwt) return json({ error: "Unauthorized" }, 401);

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: authData, error: authError } = await supabase.auth.getUser(jwt);
  if (authError || !authData?.user) return json({ error: "Unauthorized" }, 401);

  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: "Bad request" }, 400); }
  const notificationId = String(payload?.notificationId ?? "");
  if (!notificationId) return json({ error: "notificationId required" }, 400);

  const { data: userRows, error: userError } = await supabase
    .from("users")
    .select("id,data")
    .eq("data->>authUid", authData.user.id)
    .limit(1);
  if (userError) return json({ error: userError.message }, 500);
  const callerUsername = userRows?.[0]?.data?.username;
  if (!callerUsername) return json({ error: "Aura kullanıcı hesabı bulunamadı" }, 403);

  const { data: notificationRow, error: notificationError } = await supabase
    .from("notifications")
    .select("id,data")
    .eq("id", notificationId)
    .limit(1)
    .maybeSingle();
  if (notificationError) return json({ error: notificationError.message }, 500);
  if (!notificationRow) return json({ skipped: "notification not found" });

  const n = notificationRow.data ?? {};
  if (!n.to || n.from !== callerUsername || n.direction === "sent" || n.type === "room_private_sent") {
    return json({ skipped: "not owned incoming notification" });
  }

  const { data: rows, error: tokenError } = await supabase
    .from("push_tokens")
    .select("id,data")
    .eq("data->>username", n.to);
  if (tokenError) return json({ error: tokenError.message }, 500);

  const message = JSON.stringify({
    title: n.title || TITLES[n.type] || "Aura Ultra X",
    body: String(n.text ?? "Yeni bildirim").slice(0, 140),
    roomId: n.roomId ?? null,
    tag: `aurax-${notificationId}`,
  });

  let sent = 0;
  let removed = 0;
  await Promise.all((rows ?? []).map(async (row) => {
    const subscription = row.data?.subscription;
    if (!subscription?.endpoint) return;
    try {
      await webpush.sendNotification(subscription, message);
      sent++;
    } catch (e: any) {
      if (e?.statusCode === 404 || e?.statusCode === 410) {
        await supabase.from("push_tokens").delete().eq("id", row.id);
        removed++;
      } else {
        console.error("push hatası", e?.statusCode, e?.body ?? e?.message);
      }
    }
  }));

  return json({ sent, removed });
});
