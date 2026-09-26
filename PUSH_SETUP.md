# Aura X Push Bildirim Kurulumu

Bu sürüm bildirim kayıtlarını Firestore `notifications` koleksiyonuna yazar ve `functions/` içindeki Cloud Function üzerinden Firebase Cloud Messaging ile dış/cihaz bildirimi gönderir. Aynı Functions projesi kullanıcı adı + şifre girişini Google seçimi olmadan doğrulamak için `auraxLogin` fonksiyonunu da yayınlar.

## Deploy

1. Firebase CLI ile proje hesabınıza giriş yapın.
2. Bu klasörde `npm install` komutunu çalıştırın (Functions için `functions/` klasöründe de `npm install` çalıştırılabilir).
3. `firebase deploy --only functions` ile `auraxLogin` ve `sendAuraNotificationPush` fonksiyonlarını yayınlayın.

Cloud Functions 2nd gen için Firebase projesinde ilgili faturalandırma/Blaze gereksinimleri geçerli olabilir.

## iPhone / Safari

iPhone ve iPad tarafında web push Apple tarafından Ana Ekrana eklenmiş web uygulamalarında çalışır. Aura X, Safari içinden install düğmesine basıldığında kullanıcıyı modern bir kurulum paneliyle yönlendirir; Apple'ın izin verdiği şekilde JavaScript ile Safari'nin “Ana Ekrana Ekle” işlemi doğrudan programatik olarak çalıştırılamaz.
