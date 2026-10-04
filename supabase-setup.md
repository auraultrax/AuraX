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
- oda sahibi/yöneticisi olmayan üyelerin oda şifresi, admin listesi, susturma/kısıtlama ve sabitleme gibi yönetim alanlarını doğrudan Supabase üzerinden değiştirmesini engeller; normal üyelerin mesaj/emoji/çıkış gibi mevcut sohbet işlemlerini korur,
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

## 10. Düzeltme yaması (ZORUNLU)

`supabase_schema.sql` ve `supabase_security_patch.sql` çalıştırıldıktan sonra `supabase_fix_patch.sql` dosyasının tamamını SQL Editor'da çalıştır. Tekrar çalıştırmak güvenlidir.

Bu yama olmadan: başkasının gönderisini beğenme/yorumlama, oy verme ve şifreyle odaya ilk kez katılma çalışmaz (RLS bunları engeller). Ayrıca bu paketteki oda güvenlik yaması çalıştırılmadan eski geniş oda UPDATE kuralı kullanılmamalıdır.

## 11. Google / Apple "Hata 400: redirect_uri_mismatch"

Bu hata kodda değil, Google/Apple tarafındaki ayardadır. Giriş sayfasına Google gösterir; yani Supabase'in kullandığı OAuth istemcisinde Supabase geri dönüş adresi tanımlı değildir.

1. Google Cloud Console → APIs & Services → Credentials → kullandığın **Web application** OAuth istemcisi → **Authorized redirect URIs** listesine tam olarak şunu ekle (başka karakter, sonda `/` yok):
   `https://rzdvezdccgkfzfpizwmj.supabase.co/auth/v1/callback`
2. Supabase → Authentication → Providers → Google: **Client ID** ve **Client Secret**, 1. adımdaki aynı istemciye ait olmalı (eski Firebase istemcisinin bilgileri kalmış olabilir).
3. Supabase → Authentication → URL Configuration: **Site URL** = sitenin adresi; **Redirect URLs** listesine sitenin adresini ekle (ör. `https://siteadresin.com/**`).
4. Apple için: Services ID → Return URL aynı Supabase callback adresi olmalı (bkz. 2. bölüm).

Ayar yapıldıktan sonra uygulama, sağlayıcıdan dönen hatayı artık ekranda gösterir.

## 12. Uygulama kapalıyken bildirim (Web Push)

Uygulama açıkken / arka plandayken bildirimler zaten çalışır (Bildirimler sekmesi + zil + cihaz bildirimi). Uygulama TAMAMEN kapalıyken bildirim için:

1. VAPID anahtarı üret: `npx web-push generate-vapid-keys`
2. `index.html` içindeki `SUPABASE_VAPID_PUBLIC_KEY` değerine **public** anahtarı yaz.
3. Edge Functions → Secrets: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` (örn. `mailto:sen@ornek.com`), `PUSH_WEBHOOK_SECRET` (uzun rastgele bir metin).
4. `supabase/functions/send-push` fonksiyonunu deploy et.
5. Database → Webhooks → yeni webhook: tablo `notifications`, olay **Insert**, tür **Supabase Edge Functions** → `send-push`, HTTP header: `x-webhook-secret: <PUSH_WEBHOOK_SECRET değeri>`.
6. iPhone'da Web Push yalnızca uygulama "Ana Ekrana Ekle" ile kurulduysa çalışır (iOS 16.4+).
