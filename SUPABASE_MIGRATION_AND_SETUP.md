# Aura X — Supabase geçişi ve çalıştırma

## 1. Supabase SQL
Supabase Dashboard → SQL Editor → `supabase/schema.sql` dosyasını bir kez çalıştırın. Bu dosya `aurax_documents`, `push_subscriptions` ve hesap silme RPC'sini oluşturur.

## 2. Eski Firestore verilerini taşıma
Geçici olarak `migrate-firestore-to-supabase.html` sayfasını yayınlayın. **Google ile Yetkili Aktarımı Başlat** düğmesine basın. Bilinen Firestore koleksiyonları Supabase `aurax_documents` tablosuna kopyalanır. Ana Aura X uygulamasının normal çalışma yolu Firestore kullanmaz.

## 3. Normal giriş
Ana Aura X girişinde kullanıcı adı + şifre için **Supabase Auth** kullanılır. Google hesap seçici normal `Giriş Yap` akışından kaldırılmıştır. Eski PBKDF2 kullanıcı kayıtlarında başarılı ilk giriş sırasında Supabase Auth hesabı oluşturulabilir. Otomatik giriş için Supabase Auth → Providers → Email bölümünde email confirmation kapalı olmalıdır.

## 4. Google ile Kayıt Ol
Google doğrulaması yalnızca kayıt ekranında Firebase üzerinden yapılır. Seçilen Google hesabı, Supabase Auth hesabındaki e-posta ile eşleştirilir; uygulama verileri Supabase'de tutulur.

## 5. Şifremi Unuttum
Kullanıcı yalnızca **Şifremi Unuttum** akışında Google hesabını seçer. Firebase ID token `aurax-google-reset` Edge Function tarafından doğrulanır ve eşleşen Supabase Auth hesabının şifresi güncellenir.

Edge Function için Supabase Dashboard → Edge Functions üzerinden `aurax-google-reset` deploy edilmelidir. `SUPABASE_SERVICE_ROLE_KEY` secret'ı gerekir.

## 6. Uygulama verileri
Gönderiler, beğeniler, yazışmalar, yanıtlar, sabitlemeler, odalar, kullanıcı kayıtları, şikayetler ve mevcut diğer Firestore koleksiyonları Supabase `aurax_documents` içinde tutulur. Medya zaten Supabase Storage üzerindedir.

Uygulama, eski Firestore API çağrılarını bozmadan korumak için küçük bir uyumluluk katmanı kullanır; bu katman verileri Supabase tablosunda saklar.

## 7. Bildirimler — yalnızca dışarıda
Uygulama içindeki bildirim paneli, rozetleri ve oda içi özel bildirim paneli gizlenmiştir. Bildirim kaydı yalnızca teslimat için tutulur.

Uygulama tamamen kapalıyken cihaz bildirimlerinin çalışması için Web Push yapılandırılmalıdır:
1. `supabase/functions/send-push` fonksiyonunu deploy edin.
2. Supabase Function Secrets içine `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` ve `SUPABASE_SERVICE_ROLE_KEY` tanımlayın.
3. `index.html` içindeki `VAPID_PUBLIC_KEY` alanına aynı public anahtarı yazın.
4. Kullanıcı giriş yaptıktan sonra tarayıcı bildirim iznini verirse abonelik `push_subscriptions` tablosuna kaydedilir.

Web Push anahtarları proje/alanınıza özel olmalıdır; private anahtarı HTML içine koymayın.

## 8. Profil
Profilde `Şifremi Değiştir` ve `Hesabımı Sil` alanları vardır. Hesap silme için `aurax_delete_my_account()` RPC'si kullanılır.

## 9. Odalar
Oda yöneticileri oda adını ve oda şifresini yeniden değiştirebilir. Oda kilidi normal kullanıcılar kadar yöneticiler için de geçerlidir.

## 10. AuraCell
İkinci ZIP'teki AuraCell paneli oda listesini Supabase üzerinden kullanır ve kilitli odayı **herkese kapalı** gösterir. AuraCell'in mevcut backend `aurax-data` sözleşmesi Firebase ID token beklediği için bu ayrı yönetim panelinin Google yönetici girişi korunmuştur; bu, ana Aura X kullanıcı giriş akışı değildir.
