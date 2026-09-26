# Aura X sistem dışı bildirimler

Bu sürümde `notifications/{id}` oluşturulduğunda `functions/index.js` içindeki
`pushAuraNotification` Cloud Function, kullanıcının `users/{username}/pushTokens`
altındaki FCM tokenlarına sistem dışı web/masaüstü bildirimi gönderir.

Kurulum:
1. `firebase login`
2. `firebase use aura-ultra-x`
3. `cd functions && npm install`
4. proje kökünde `firebase deploy --only functions,firestore:rules`

Tarayıcı/Uygulama tarafında bildirim izni verildiğinde FCM token otomatik olarak
kullanıcının pushTokens altına kaydedilir.

Not: Tarayıcı bildirimi için kullanıcı işletim sistemi/tarayıcı bildirimlerine izin
vermelidir. PWA/uygulama kapalıyken teslimat için Cloud Function'ın deploy edilmiş
olması gerekir.
