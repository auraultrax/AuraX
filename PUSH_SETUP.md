# Aura X — Dış/Web Push Bildirim Kurulumu

Ana uygulamadaki bildirim paneli ve rozetleri kullanıcı arayüzünde gösterilmez. Bildirim kayıtları Supabase üzerinde yalnızca dış cihaz/Web Push teslimatı için tutulur.

## Supabase
1. `supabase/schema.sql` dosyasını SQL Editor'da çalıştırın.
2. `supabase/functions/send-push` fonksiyonunu deploy edin.
3. Function Secrets: `SUPABASE_SERVICE_ROLE_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`.
4. `index.html` içindeki `VAPID_PUBLIC_KEY` değerine public anahtarı yazın.

Private VAPID anahtarını hiçbir HTML/JS dosyasına koymayın.

## Davranış
- Yorum beğenisi, yanıt, oda yanıtı, özel mesaj, oda daveti vb. olaylar `notifications` kaydına eklenir.
- Gönderici tarafı aynı anda `send-push` Edge Function'ı çağırır.
- Service Worker `push` olayıyla cihaz/işletim sistemi bildirimini gösterir.
- Uygulama içinde ayrıca bildirim toast'ı veya bildirim paneli açılmaz.

Web Push yapılandırılmamışsa uygulama kapalıyken dış bildirim garanti edilemez; kullanıcı tarafında tarayıcı bildirim izni ve geçerli VAPID aboneliği gerekir.
