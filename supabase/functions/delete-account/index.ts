import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  const authHeader = req.headers.get('Authorization') || '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!jwt) return new Response('Unauthorized', { status: 401 });

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: `Bearer ${jwt}` } } });
  const { data: authData, error: authError } = await userClient.auth.getUser(jwt);
  if (authError || !authData.user) return new Response('Unauthorized', { status: 401 });

  const uid = authData.user.id;
  const { data: rows } = await admin.from('users').select('id,data').eq('data->>authUid', uid).limit(1);
  const username = rows?.[0]?.id;
  if (!username) return new Response('Aura X user not found', { status: 404 });

  const tables = ['push_tokens','account_links','notifications','reports','posts','statuses','votes','restrictions','users'];
  for (const table of tables) {
    if (table === 'users') {
      const { error } = await admin.from(table).delete().eq('id', username);
      if (error) return new Response(error.message, { status: 500 });
    } else {
      await admin.from(table).delete().eq('data->>username', username);
      await admin.from(table).delete().eq('data->>author', username);
      await admin.from(table).delete().eq('data->>from', username);
      await admin.from(table).delete().eq('data->>to', username);
    }
  }

  const { error: authDeleteError } = await admin.auth.admin.deleteUser(uid);
  if (authDeleteError) return new Response(authDeleteError.message, { status: 500 });
  return Response.json({ ok: true });
});
