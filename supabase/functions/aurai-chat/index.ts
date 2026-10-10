import { createClient } from 'npm:@supabase/supabase-js@2';

// AURAI: yalnızca giriş yapmış AuraX kullanıcıları kullanabilir. Model, kendi sunucundaki
// OpenAI uyumlu bir uç noktadır (AURAI_API_URL). Secret'lar: AURAI_API_URL, AURAI_MODEL,
// AURAI_API_KEY (isteğe bağlı), AURAI_DAILY_LIMIT (kişi başı, varsayılan 30), AURAI_DAILY_BUDGET (tüm site, varsayılan 5000).
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

const norm = (s: string) =>
  s.toLocaleLowerCase('tr-TR').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/ı/g, 'i').replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
const CRISIS_RE = /\b(intihar|kendimi (oldur|as(ac|mak|iy)|atac|atmak)|kendime zarar|canima kiy|olmek istiyorum|yasamak istemiyorum|hayatima son|bilegimi kes)/;

const BASE = "Sen AURAI'sin, Beray'ın Türkçe öncelikli yapay zekâ asistanısın ve AuraX (Aura Ultra X) sosyal uygulamasının içinde çalışıyorsun. Doğal, doğru ve kısa Türkçe yanıt ver. Web araması yapamazsın; güncel bilgi gerektiren sorularda bunu açıkça söyle. Emin olmadığın şeyi kesinmiş gibi söyleme. Diğer kullanıcılar, hesaplar veya uygulamanın içindeki özel veriler hakkında bilgin yok; bunları bilmiyormuş gibi davran, tahmin etme. Beray ürünleri hakkında yalnızca şunları söyle, listede olmayan özellik, fiyat veya tarih uydurma: Beray, Türkiye'den doğan bir teknoloji girişimidir. AuraX; odalar, Keşfet akışı, liderlik tablosu, özel mesajlar, bildirimler ve arkadaşlarla birlikte YouTube izleme ya da çizim özellikleri olan sosyal bir uygulamadır. Beray Sağlık, genel sağlık bilgilendirmesi hedefleyen bir uygulamadır; tıbbi tavsiye veya teşhis vermez.";
const LISTEN = "Sen AURAI'sin ve dinleme modundasın. Önce dinle: kullanıcının anlattığını kendi sözcüklerinle yansıt, acele öğüt verme, yargılama. Sıcak, sakin ve sade Türkçe kullan; kısa yanıtlar ver ve genelde tek bir açık uçlu soru sor. Terapist değilsin; teşhis koyma, tedavi önerme ve bunu gerektiğinde nazikçe belirt. Kullanıcıyı sana bağımlı kılma; uygun olduğunda güvendiği insanlarla da konuşmasını destekle. Her şeye hak verme; gerektiğinde nazik ve dürüst ol.";
const CRISIS = " Kullanıcı kendine zarar verme ya da yaşamdan vazgeçme sinyali verdi. Sakin ve sıcak yanıt ver; yalnız olmadığını söyle. Yöntem veya ayrıntı verme. Hemen 112'yi aramasını ve yanındaki birine haber vermesini nazikçe öner. Konuyu geçiştirme; konuşmaya devam etmeye davet et.";
const LIMITED = 'Bugünkü AURAI hakkın doldu. Yarın tekrar dene.';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method Not Allowed' }, 405);

  // Giriş zorunlu (anon anahtar kabul edilmez).
  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  if (!jwt || jwt === anonKey) return json({ error: 'Yetkisiz.' }, 401);
  const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !authData?.user) return json({ error: 'Yetkisiz.' }, 401);
  const userId = authData.user.id;

  const apiUrl = Deno.env.get('AURAI_API_URL');
  const model = Deno.env.get('AURAI_MODEL');
  if (!apiUrl || !model) return json({ error: 'AURAI henüz etkinleştirilmemiş.' }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: 'İstek okunamadı.' }, 400); }
  const raw = Array.isArray(body?.messages) ? body.messages.slice(-10) : [];
  const messages: { role: string; content: string }[] = [];
  for (const m of raw) {
    const content = typeof m?.content === 'string' ? m.content.trim().slice(0, 2000) : '';
    if (!content) continue;
    const role = m.role === 'assistant' ? 'assistant' : 'user';
    const last = messages[messages.length - 1];
    if (last && last.role === role) last.content += '\n\n' + content; else messages.push({ role, content });
  }
  while (messages.length && messages[0].role !== 'user') messages.shift();
  if (!messages.length || messages[messages.length - 1].role !== 'user') return json({ error: 'Bir mesaj yazmalısın.' }, 400);

  const lastText = messages[messages.length - 1].content;
  const crisis = CRISIS_RE.test(norm(lastText));
  const listen = body?.mode === 'listen';

  // Günlük limit ve bütçe sigortası (kriz mesajları sınırdan muaf).
  if (!crisis) {
    const admin = createClient(supabaseUrl, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
    const perUser = Number(Deno.env.get('AURAI_DAILY_LIMIT')) || 30;
    const budget = Number(Deno.env.get('AURAI_DAILY_BUDGET')) || 5000;
    const total = await admin.rpc('aurai_bump', { p_user: '00000000-0000-0000-0000-000000000000' });
    if (!total.error && Number(total.data) > budget) return json({ answer: LIMITED, limited: true });
    const mine = await admin.rpc('aurai_bump', { p_user: userId });
    if (!mine.error && Number(mine.data) > perUser) return json({ answer: LIMITED, limited: true });
  }

  try {
    const r = await fetch(apiUrl.replace(/\/+$/, '') + '/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...(Deno.env.get('AURAI_API_KEY') ? { Authorization: 'Bearer ' + Deno.env.get('AURAI_API_KEY') } : {}) },
      body: JSON.stringify({
        model,
        messages: [{ role: 'system', content: (listen ? LISTEN : BASE) + (crisis ? CRISIS : '') }, ...messages],
        temperature: 0.5, max_tokens: 800, stream: false,
      }),
      signal: AbortSignal.timeout(50000),
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok) return json({ error: 'AURAI şu anda yanıt veremiyor.', crisis }, 502);
    const answer = String(d?.choices?.[0]?.message?.content || '').trim();
    if (!answer) return json({ error: 'AURAI yanıt alamadı.', crisis }, 502);
    return json({ answer, crisis });
  } catch (e) {
    console.error('aurai-chat upstream error', e);
    return json({ error: 'AURAI şu anda yanıt veremiyor.', crisis }, 502);
  }
});
