// Aura X — Web Push dispatcher.
// Desteklenen çağrı şekilleri:
// 1) Supabase Database Webhook -> notifications INSERT -> Edge Function.
// 2) (Geriyedönük/manuel) Kullanıcı JWT'si + { notificationId }.
//
// Webhook tarafında Authorization header olarak Supabase Service Role key kullanılmalıdır.
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const VAPID_PRIVATE = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@example.com";

if (!VAPID_PUBLIC || !VAPID_PRIVATE) console.error('VAPID anahtarları eksik: VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY');
else webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

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
  admin_message: "Yönetim mesajı",
  restriction: "Hesap doğrulaması gerekli",
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...corsHeaders } });
}

function isServiceRoleRequest(req: Request) {
  const auth = req.headers.get('Authorization') ?? '';
  return auth === `Bearer ${SERVICE_KEY}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const webhookTrusted = isServiceRoleRequest(req);
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  if (!VAPID_PUBLIC || !VAPID_PRIVATE) return json({ error: 'Web Push VAPID anahtarları sunucuda yapılandırılmamış.' }, 500);

  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: "Bad request" }, 400); }

  const notificationId = String(
    payload?.notificationId ??
    payload?.record?.id ??
    payload?.data?.record?.id ??
    ''
  );
  if (!notificationId) return json({ error: "notificationId required" }, 400);

  let callerUsername: string | null = null;
  if (!webhookTrusted) {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!jwt || jwt === SERVICE_KEY) return json({ error: "Unauthorized" }, 401);
    const { data: authData, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !authData?.user) return json({ error: "Unauthorized" }, 401);
    const { data: userRows, error: userError } = await supabase.from("users").select("id,data").eq("data->>authUid", authData.user.id).limit(1);
    if (userError || !userRows?.[0]) return json({ error: "Aura kullanıcı hesabı bulunamadı" }, 403);
    callerUsername = userRows[0].id;
  }

  const { data: priorDispatch } = await supabase
    .from('push_delivery_log')
    .select('notification_id,sent_count,attempted_at')
    .eq('notification_id', notificationId)
    .maybeSingle();
  if (priorDispatch?.sent_count > 0) return json({ skipped: 'already dispatched', sent: priorDispatch.sent_count });

  const { data: notificationRow, error: notificationError } = await supabase
    .from("notifications").select("id,data").eq("id", notificationId).maybeSingle();
  if (notificationError) { console.error('notification lookup', notificationError); return json({ error: 'Bildirim servisi kullanılamıyor.' }, 500); }
  if (!notificationRow) return json({ skipped: "notification not found" });

  const n = notificationRow.data ?? {};
  if (!n.to || n.direction === 'sent' || n.type === 'room_private_sent') return json({ skipped: "not incoming notification" });
  if (!webhookTrusted && n.from !== callerUsername) return json({ skipped: "caller does not own notification" }, 403);

  if (!webhookTrusted && n.from === n.to) return json({ skipped: "self notification" });

  const { data: rows, error: tokenError } = await supabase.from("push_tokens").select("id,data").eq("data->>username", n.to);
  if (tokenError) { console.error('token lookup', tokenError); return json({ error: 'Bildirim servisi kullanılamıyor.' }, 500); }

  const message = JSON.stringify({
    title: String(n.title || TITLES[n.type] || "Aura Ultra X").slice(0, 80),
    body: String(n.text ?? "Yeni bildirim").slice(0, 240),
    roomId: n.roomId ?? null,
    postId: n.postId ?? null,
    notificationId,
    tag: `aurax-${notificationId}`,
    url: './'
  });

  let sent = 0;
  let removed = 0;
  const results = await Promise.all((rows ?? []).map(async row => {
    const subscription = row.data?.subscription;
    if (!subscription?.endpoint || !subscription?.keys?.p256dh || !subscription?.keys?.auth) return { sent: 0, removed: 0 };
    try {
      await webpush.sendNotification(subscription, message, { TTL: 300 });
      return { sent: 1, removed: 0 };
    } catch (e: any) {
      if (e?.statusCode === 404 || e?.statusCode === 410) {
        await supabase.from("push_tokens").delete().eq("id", row.id);
        return { sent: 0, removed: 1 };
      }
      console.error("push hatası", e?.statusCode, e?.body ?? e?.message);
      return { sent: 0, removed: 0 };
    }
  }));
  for (const r of results) { sent += r.sent; removed += r.removed; }

  // Tekrar denemelerin kontrolü için ayrı push teslimat kaydı tutulur.
  // Ham push endpoint/key bilgileri audit/log alanına yazılmaz.
  try {
    await supabase.from('push_delivery_log').upsert({ notification_id: notificationId, attempted_at: new Date().toISOString(), sent_count: sent, removed_count: removed, last_error: sent === 0 ? 'Aktif push aboneliği bulunamadı veya gönderim başarısız oldu.' : null });
  } catch (e) { console.warn('Push teslimat kaydı yazılamadı', e); }

  return json({ sent, removed, webhook: webhookTrusted });
});
