import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  const authHeader = req.headers.get('Authorization') || '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!jwt) return new Response('Unauthorized', { status: 401 });

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${jwt}` } } });

  try {
    const { data: authData, error: authError } = await userClient.auth.getUser(jwt);
    if (authError || !authData.user) return new Response('Unauthorized', { status: 401 });
    const uid = authData.user.id;

    // Public application verileri tek PostgreSQL transaction'ında temizlenir.
    // Böylece Edge Function içindeki ardışık DELETE çağrılarından kaynaklanan sessiz
    // kısmi silinmeler ortadan kalkar. Auth kullanıcısının silinmesi en son yapılır.
    const { data: deletion, error: deletionError } = await userClient.rpc('aurax_delete_current_user_data');
    if (deletionError || deletion !== true) {
      console.error('delete-account app-data deletion failed', deletionError);
      return new Response('Hesap verileri güvenli biçimde silinemedi.', { status: 500 });
    }

    const { error: authDeleteError } = await admin.auth.admin.deleteUser(uid);
    if (authDeleteError) {
      console.error('delete-account auth deletion failed', authDeleteError);
      // Uygulama verileri tek transaction'da temizlendi; Auth silme başarısızsa
      // hesabı tekrar veriyle eşleştirmeden güvenli şekilde hata döndür.
      return new Response('Hesap silme işlemi tamamlanamadı. Yönetici loglarını kontrol edin.', { status: 500 });
    }
    return Response.json({ ok: true });
  } catch (error) {
    console.error('delete-account internal error', error);
    return new Response('Hesap silme işlemi başarısız.', { status: 500 });
  }
});
