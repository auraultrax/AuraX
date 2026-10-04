import { corsHeaders } from 'npm:@supabase/supabase-js@^2/cors';
import { createClient } from 'npm:@supabase/supabase-js@^2';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'Method Not Allowed' }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  try {
    const { username, password } = await req.json();
    const cleanUsername = String(username || '').trim();
    const cleanPassword = String(password || '');
    if (!cleanUsername || !cleanPassword) throw new Error('Kullanıcı adı ve şifre gereklidir.');
    if (/[<>"'`&]/.test(cleanUsername)) throw new Error('Geçersiz kullanıcı adı.');

    const url = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const authClient = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });

    const { data: row, error: rowError } = await admin.from('users').select('id,data').eq('id', cleanUsername).maybeSingle();
    if (rowError) throw rowError;
    if (!row) return new Response(JSON.stringify({ error: 'Hatalı kullanıcı adı veya şifre.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

    const user = row.data || {};
    if (user.banned === true) return new Response(JSON.stringify({ error: 'Bu hesap Aura Ultra X sisteminden kalıcı olarak engellenmiştir.' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

    const email = String(user.authEmail || `${cleanUsername.toLowerCase()}@auth.aurax.local`);
    const { data: authData, error: authError } = await authClient.auth.signInWithPassword({ email, password: cleanPassword });
    if (authError || !authData.session) return new Response(JSON.stringify({ error: 'Hatalı kullanıcı adı veya şifre.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

    return new Response(JSON.stringify({ session: authData.session }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Giriş başarısız.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
