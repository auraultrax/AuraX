import { corsHeaders } from 'npm:@supabase/supabase-js@^2/cors';
import { createClient } from 'npm:@supabase/supabase-js@^2';

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function clientIp(req: Request): string | null {
  const cf = req.headers.get('cf-connecting-ip')?.trim();
  if (cf) return cf;
  const forwarded = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim();
  return forwarded || null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method Not Allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const authClient = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const ip = clientIp(req);
  const userAgent = req.headers.get('user-agent');

  async function audit(action: string, username: string | null, uid: string | null, metadata: Record<string, unknown> = {}) {
    try {
      await admin.from('audit_logs').insert({
        action,
        table_name: 'auth',
        row_id: username,
        actor_uid: uid,
        actor_username: username,
        client_ip: ip,
        user_agent: userAgent,
        request_path: '/functions/v1/username-login',
        changed_keys: [],
        metadata,
      });
    } catch (e) {
      console.error('AUDIT_LOG_WRITE_FAILED', e);
    }
  }

  try {
    let body: any;
    try { body = await req.json(); }
    catch { return json({ error: 'Giriş başarısız.' }, 400); }

    const cleanUsername = String(body?.username ?? '').trim();
    const cleanPassword = String(body?.password ?? '');
    if (!cleanUsername || !cleanPassword) return json({ error: 'Giriş başarısız.' }, 401);
    if (cleanUsername.length > 64 || cleanPassword.length > 512) return json({ error: 'Giriş başarısız.' }, 401);
    if (/[<>"'`&]/.test(cleanUsername)) return json({ error: 'Giriş başarısız.' }, 401);

    // Brute-force koruması: aynı kullanıcı+istemci IP için 15 dakikada en fazla 8 başarısız deneme.
    // Başarısız denemeler parola veya ham secret içermez; yalnızca güvenlik olayı kaydı tutulur.
    const since = new Date(Date.now() - 15 * 60 * 1000).toISOString();
    let failedQuery = admin
      .from('audit_logs')
      .select('id', { count: 'exact', head: true })
      .eq('action', 'LOGIN_FAILED')
      .eq('actor_username', cleanUsername)
      .gte('created_at', since);
    if (ip) failedQuery = failedQuery.eq('client_ip', ip);
    const { count: failedCount, error: rateReadError } = await failedQuery;
    if (rateReadError) {
      await audit('LOGIN_RATE_LIMIT_ERROR', cleanUsername, null, { reason: 'rate_query_failed' });
      return json({ error: 'Giriş sistemi geçici olarak kullanılamıyor.' }, 503);
    }
    if ((failedCount ?? 0) >= 8) {
      await audit('LOGIN_RATE_LIMITED', cleanUsername, null, { windowSeconds: 900, limit: 8 });
      return json({ error: 'Çok fazla başarısız giriş denemesi. Daha sonra tekrar deneyin.' }, 429);
    }

    await audit('LOGIN_ATTEMPT', cleanUsername, null, { method: 'username_password' });

    const { data: row, error: rowError } = await admin
      .from('users')
      .select('id,data')
      .eq('id', cleanUsername)
      .maybeSingle();
    if (rowError) {
      await audit('LOGIN_INTERNAL_ERROR', cleanUsername, null, { stage: 'user_lookup' });
      return json({ error: 'Giriş başarısız.' }, 500);
    }
    if (!row) {
      await audit('LOGIN_FAILED', cleanUsername, null, { reason: 'invalid_credentials' });
      return json({ error: 'Hatalı kullanıcı adı veya şifre.' }, 401);
    }

    const user = row.data || {};
    if (user.banned === true) {
      await audit('LOGIN_FAILED', cleanUsername, String(user.authUid || '') || null, { reason: 'blocked_account' });
      // Hesabın gerçekten var olduğunu açığa çıkarmamak için aynı genel yanıt.
      return json({ error: 'Hatalı kullanıcı adı veya şifre.' }, 401);
    }

    const email = String(user.authEmail || `${cleanUsername.toLowerCase()}@auth.aurax.local`);
    const { data: authData, error: authError } = await authClient.auth.signInWithPassword({ email, password: cleanPassword });
    if (authError || !authData.session) {
      await audit('LOGIN_FAILED', cleanUsername, String(user.authUid || '') || null, { reason: 'invalid_credentials' });
      return json({ error: 'Hatalı kullanıcı adı veya şifre.' }, 401);
    }

    await audit('LOGIN_SUCCESS', cleanUsername, authData.user?.id || String(user.authUid || '') || null, { method: 'username_password' });
    return json({ session: authData.session }, 200);
  } catch (error) {
    console.error('username-login internal error', error);
    return json({ error: 'Giriş başarısız.' }, 500);
  }
});
