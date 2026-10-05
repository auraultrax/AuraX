import { corsHeaders } from 'npm:@supabase/supabase-js@^2/cors';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'GET') return new Response('Method Not Allowed', { status: 405, headers: corsHeaders });
  const key = Deno.env.get('YOUTUBE_API_KEY');
  if (!key) return new Response(JSON.stringify({ error: 'YOUTUBE_API_KEY secret eksik.' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  const q = new URL(req.url).searchParams.get('q')?.trim();
  if (!q) return new Response(JSON.stringify({ items: [] }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  const url = new URL('https://www.googleapis.com/youtube/v3/search');
  url.searchParams.set('part', 'snippet');
  url.searchParams.set('type', 'video');
  url.searchParams.set('maxResults', '10');
  url.searchParams.set('q', q);
  url.searchParams.set('key', key);
  const response = await fetch(url);
  const body = await response.text();
  return new Response(body, { status: response.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
});
