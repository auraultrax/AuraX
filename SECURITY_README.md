# Aura Ultra X - Güvenlik Notları

Bu sürümde istemci tarafında şu düzeltmeler yapıldı:

- Kullanıcı şifreleri artık düz metin yerine PBKDF2-SHA256 ile hashleniyor.
- Eski düz metin şifreler, başarılı girişte otomatik olarak hashlenmiş biçime yükseltiliyor.
- Şifre sıfırlama da hashlenmiş kayıt oluşturuyor.
- Admin oturumu yalnızca `currentUser` yazısına bağlı değil; ayrıca oturum başına rastgele bir admin session token gerekiyor.
- Admin girişinden sonra admin token oluşturuluyor; çıkışta temizleniyor.
- Admin bildirim gönderimi artık Firestore yazısının tamamlanmasını bekliyor.
- Yönetim fonksiyonlarının frontend tarafındaki kontrolleri `isAdminSession()` üzerinden yapılıyor.

## ÖNEMLİ

Bu dosya tek başına Firestore güvenlik kurallarının yerine geçmez. Gerçek güvenlik için Firebase Console > Firestore Database > Rules bölümünde, özellikle `users`, `notifications`, `posts`, `rooms`, `bannedUsers`, `bannedIPs`, `bannedDevices` ve `reports` koleksiyonlarında yazma yetkilerinin `request.auth` ve kullanıcı sahipliği ile server-side doğrulanması gerekir.

Frontend'deki hiçbir JavaScript kontrolü, tek başına güvenlik duvarı değildir.


## PWA / ikon düzeltmeleri (v3)

- `manifest.json` artık ZIP içindeki gerçek `AuraX-icon-192.png` ve `AuraX-icon-512.png` dosyalarını kullanıyor.
- `index.html` artık favicon ve Apple touch icon için doğru dosya yollarını kullanıyor.
- Service Worker `aura-x-v3` olarak sürümlendi ve eski cache'leri aktivasyon sırasında siliyor.
- Service Worker artık uygulama HTML'ini network-first, statik dosyaları cache-first stratejisiyle ele alıyor.
- Service Worker aynı origin dışındaki Firebase/CDN isteklerine müdahale etmiyor.
- Kurulum kabuğuna ikonlar da eklendi.
