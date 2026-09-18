# Aura Ultra X — Supabase güvenli kurulum

1. `AURAX_SUPABASE_SQL.sql` dosyasını Supabase Dashboard > SQL Editor'da çalıştırın.
2. `supabase/functions/aurax-data/index.ts` ve `supabase/functions/aurax-media/index.ts` Edge Function olarak deploy edin.
3. Edge Function secrets içine `AURAX_SUPABASE_SERVICE_ROLE_KEY` ve `AURAX_FIREBASE_PROJECT_ID=aura-ultra-x` koyun. Service-role anahtarını HTML'e koymayın.
4. `aurax_admins` tablosuna gerçek Firebase UID'nizi tek aktif admin olarak ekleyin.
5. Storage'da `media` bucket'ı bulunmalı. SQL bunu oluşturur; istemci yazma/silme işlemleri Edge Function'a yönlendirilmiştir.

Supabase Edge Functions, Firebase Auth JWT'sini doğrudan Supabase Auth JWT'si gibi kabul etmez; bu projede Edge Function Firebase token'ını ayrıca doğrular. Firebase ID token doğrulamasında issuer, audience ve imza kontrolü zorunludur.
