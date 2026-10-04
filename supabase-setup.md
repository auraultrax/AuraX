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

### Apple ile kayıt / şifremi unuttum

Apple Developer Program üyeliği gerekir.

1. Apple Developer → Identifiers → **Services ID** oluştur (Sign in with Apple açık). Domain: `<PROJECT-REF>.supabase.co`, Return URL: `https://<PROJECT-REF>.supabase.co/auth/v1/callback`
2. Keys bölümünden Sign in with Apple için bir key oluştur, `.p8` dosyasını sakla (Key ID ve Team ID'yi not al).
3. `.p8` dosyasından Apple client secret üret (Supabase dokümanındaki araç).
4. Authentication → Providers → **Apple: ON**. Client IDs alanına Services ID'yi, Secret alanına üretilen secret'ı yaz.
5. Authentication → URL Configuration → Site URL ve Redirect URLs'e sitenin adresini ekle (Google için de gerekli).

Apple'ın OAuth secret'ı **6 ayda bir** süresi dolar; takvime hatırlatıcı koy, dolunca Apple girişi sessizce çalışmayı bırakır.
Apple, "E-postamı gizle" seçilirse gerçek e-posta yerine rastgele bir röle adresi verir; uygulama bunu da kabul eder.

## 3. Database

SQL Editor'da `supabase_schema.sql` dosyasının tamamını tek seferde çalıştır.

Bu dosya Aura X'in kullandığı tabloları, RLS'yi, admin kontrol fonksiyonlarını ve Realtime publication kayıtlarını oluşturur.

Ardından `supabase_security_patch.sql` dosyasının tamamını da çalıştır. Bu yama:

- admin yetkisini yalnızca `A_UR_A_XX` hesabına bağlar (kullanıcıların kendini admin yapmasını engeller),
- mavi tik / ban / oy / lider gibi alanları kullanıcının kendi satırında değiştirilemez yapar,
- `media` bucket'ı için Storage policy'lerini oluşturur (video ve fotoğraf yükleme için gerekli).

Storage policy'lerini yamadan önce `media` bucket'ını oluşturmuş olman gerekmez, ama yükleme için bucket'ın var olması gerekir (4. adım).

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
