# Aura X Push Bildirim Kurulumu

Bu sürüm bildirim kayıtlarını Firestore `notifications` koleksiyonuna yazarken aynı anda Firebase Cloud Messaging tokenlarını da kullanır. Arka planda/uygulama kapalıyken gerçek cihaz bildirimi için `functions/` içindeki Cloud Function Firebase projesine deploy edilmelidir.

## Deploy

1. Firebase CLI ile proje hesabınıza giriş yapın.
2. Bu klasörde `npm install` komutunu çalıştırın (Functions için `functions/` klasöründe de `npm install` çalıştırılabilir).
3. `firebase deploy --only functions` ile `sendAuraNotificationPush` fonksiyonunu yayınlayın.

Cloud Functions 2nd gen için Firebase projesinde ilgili faturalandırma/Blaze gereksinimleri geçerli olabilir.

## iPhone / Safari

iPhone ve iPad tarafında web push Apple tarafından Ana Ekrana eklenmiş web uygulamalarında çalışır. Aura X, Safari içinden install düğmesine basıldığında kullanıcıyı modern bir kurulum paneliyle yönlendirir; Apple'ın izin verdiği şekilde JavaScript ile Safari'nin “Ana Ekrana Ekle” işlemi doğrudan programatik olarak çalıştırılamaz.
