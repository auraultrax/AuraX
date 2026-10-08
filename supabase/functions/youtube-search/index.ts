import { createClient } from 'npm:@supabase/supabase-js@2';

// Yalnızca giriş yapmış Aura kullanıcıları arama yapabilir. Böylece API anahtarı
// anonim istemciler tarafından kota tüketimi için kötüye kullanılamaz.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'GET') return json({ error: 'Method Not Allowed' }, 405);

  const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  if (!jwt || jwt === anonKey) return json({ error: 'Yetkisiz.' }, 401);

  const authClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
  if (authError || !authData?.user) return json({ error: 'Yetkisiz.' }, 401);

  const key = Deno.env.get('YOUTUBE_API_KEY');
  if (!key) return json({ error: 'YOUTUBE_API_KEY secret eksik.' }, 500);

  const q = new URL(req.url).searchParams.get('q')?.trim();
  if (!q) return json({ items: [] });
  if (q.length > 200) return json({ error: 'Arama metni çok uzun.' }, 400);

  const url = new URL('https://www.googleapis.com/youtube/v3/search');
  url.searchParams.set('part', 'snippet');
  url.searchParams.set('type', 'video');
  url.searchParams.set('maxResults', '10');
  url.searchParams.set('q', q);
  url.searchParams.set('key', key);
  try {
    const response = await fetch(url);
    const body = await response.text();
    if (!response.ok) return json({ error: 'YouTube araması başarısız oldu.' }, 502);
    return new Response(body, { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    console.error('youtube-search upstream error', error);
    return json({ error: 'YouTube araması başarısız oldu.' }, 502);
  }
});
