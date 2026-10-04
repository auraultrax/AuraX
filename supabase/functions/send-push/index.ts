// Aura X — uygulama KAPALIYKEN cihaz bildirimi gönderir (Web Push).
// notifications tablosuna her yeni satır eklendiğinde Supabase "Database Webhook" bu fonksiyonu çağırır.
//
// Gerekli secret'lar (Edge Functions → Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (ör. mailto:sen@ornek.com), PUSH_WEBHOOK_SECRET
//   (SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY Supabase tarafından otomatik verilir.)
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";

webpush.setVapidDetails(
  Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@example.com",
  Deno.env.get("VAPID_PUBLIC_KEY") ?? "",
  Deno.env.get("VAPID_PRIVATE_KEY") ?? "",
);

const TITLES: Record<string, string> = {
  like: "Yeni beğeni",
  comment: "Yeni yorum",
  reply: "Yeni yanıt",
  vote: "Yeni oy",
  roommsg: "Oda mesajı",
  room_reply: "Odada yanıt",
  room_private: "Özel mesaj",
  room_invite: "Oda daveti",
  room_invite_request: "Oda isteği",
  draw: "Çizim daveti",
  admin_message: "Duyuru",
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!WEBHOOK_SECRET || req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  let payload: any;
  try { payload = await req.json(); } catch { return new Response("Bad request", { status: 400 }); }
  if (payload?.type !== "INSERT" || payload?.table !== "notifications") {
    return Response.json({ skipped: "not a notifications insert" });
  }

  const record = payload.record ?? {};
  const n = record.data ?? {};
  const to = n.to;
  if (!to || n.from === to || n.direction === "sent" || n.type === "room_private_sent") {
    return Response.json({ skipped: "not an incoming notification" });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const { data: rows, error } = await supabase.from("push_tokens").select("id,data").eq("data->>username", to);
  if (error) return Response.json({ error: error.message }, { status: 500 });

  const message = JSON.stringify({
    title: TITLES[n.type] ?? "Aura Ultra X",
    body: String(n.text ?? "Yeni bildirim").slice(0, 140),
    roomId: n.roomId ?? null,
    tag: `aurax-${record.id}`, // uygulama açıkken yerel bildirimle aynı etiket: çift bildirim olmaz
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

  return Response.json({ sent, removed });
});
