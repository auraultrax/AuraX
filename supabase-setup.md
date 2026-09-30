# Aura X — sıfır Supabase kurulumu

Bu paket Firebase içermez. Yeni Supabase projesi tek backend olarak kullanılır.

## 1. index.html

`SUPABASE_URL` ve `SUPABASE_PUBLISHABLE_KEY` alanlarını yeni projenin değerleriyle doldur.

`SUPABASE_PUBLISHABLE_KEY` tarayıcıda kullanılabilir anahtardır. Secret/service-role anahtarını index.html'e koyma.

## 2. Authentication

Authentication → Providers → Email: **ON**

Email → Confirm email: **OFF** (Aura X kayıt sonrası doğrudan oturum açabilsin diye).

Google ile kayıt özelliği kullanılacaksa Google provider: **ON**.

Google Cloud OAuth istemcisinde Authorized redirect URI:

`https://<PROJECT-REF>.supabase.co/auth/v1/callback`

## 3. Database

SQL Editor'da `supabase_schema.sql` dosyasının tamamını tek seferde çalıştır.

Bu dosya Aura X'in kullandığı tabloları, RLS'yi, admin kontrol fonksiyonlarını ve Realtime publication kayıtlarını oluşturur.

## 4. Storage

Storage → Buckets → `media` oluştur.

Aura X'in mevcut davranışı nedeniyle bucket'ı public görüntülemeye açabilirsin. Upload/delete yetkisini Storage policy ile `authenticated` kullanıcı ve admin kontrolüne bağla.

## 5. Admin A_UR_A_XX

Yeni Supabase projesinde Authentication → Users → Add user ile admin Auth hesabını oluştur.

Örnek email biçimi:

`a_ur_a_xx@auth.aurax.local`

Sonra Table Editor veya SQL Editor'da `users` tablosuna aynı Auth UID ile şu veriyi oluştur:

```sql
insert into public.users (id, data)
values (
  'A_UR_A_XX',
  jsonb_build_object(
    'username','A_UR_A_XX',
    'authUid','AUTH-USER-UUID-BURAYA',
    'authEmail','a_ur_a_xx@auth.aurax.local',
    'role','admin',
    'displayName','Aura X',
    'createdAt', extract(epoch from now()) * 1000,
    'verified', true,
    'special', true,
    'banned', false,
    'restricted', false,
    'votes', 0,
    'followers', jsonb_build_array(),
    'following', jsonb_build_array(),
    'avatarUrl', null,
    'avatarPath', null
  )
);
```

`AUTH-USER-UUID-BURAYA` yerine Authentication → Users ekranındaki gerçek UUID'yi yaz.

## 6. Realtime

Database → Publications → `supabase_realtime` altında Aura tablolarını doğrula. SQL zaten bunları publication'a eklemeyi dener.

## 7. YouTube

Edge Function `supabase/functions/youtube-search` deploy edilir.

Supabase Functions Secrets'e:

`YOUTUBE_API_KEY`

eklenir.

Frontend endpointi otomatik olarak:

`<SUPABASE_URL>/functions/v1/youtube-search`

kullanır.

## 8. Hesap silme

`supabase/functions/delete-account` deploy edilir.

Function tarafında service role yetkisi gerekir. Secret/service-role anahtar frontend'e eklenmez.

## 9. Web Push

`SUPABASE_VAPID_PUBLIC_KEY` doldurulursa Web Push aboneliği oluşturulur. Boşsa uygulama içi Supabase Realtime bildirimleri çalışmaya devam eder.
