# Aura Ultra X — Güvenli sunucu tarafı kurulum

Bu ZIP içindeki `index.html` istemci tarafında ek savunmalar içerir; ancak tarayıcıdaki hiçbir JavaScript F12/DevTools üzerinden değiştirilmeye karşı tek başına güvenlik duvarı değildir.

Gerçek güvenlik için Firebase Authentication ile alınan özel token içindeki `username` ve `admin` claim'leri kullanılmalı, ardından `firestore.rules` etkinleştirilmelidir.

Önemli noktalar:
- Tüm admin yetkileri Firestore Rules tarafından da doğrulanmalıdır.
- Banlı kullanıcılar için `bannedUsers`, `bannedIPs` ve `bannedDevices` server-side olarak kontrol edilmelidir.
- IP adresini Firestore Rules doğrudan göremez; IP ban kontrolü Cloud Functions/Worker gibi sunucu tarafı bir uç noktada yapılmalıdır.
- İstemciye YouTube Data API anahtarı koyulmamalıdır. `YOUTUBE_SEARCH_ENDPOINT` bir server proxy'ye yönlendirilmelidir.
- Mevcut kullanıcı parola kayıtları istemci tarafından okunabiliyorsa, bunlar güvenli backend giriş akışına taşınmalıdır. `firestore.rules` bunun server-side token yapısına göre kullanılacağını varsayar.

`firebase.json` içine Rules dosyasını bağlamak için `firestore: { "rules": "firestore.rules" }` eklenmesi ve Firebase Console'da Authentication/Rules yapılandırmasının tamamlanması gerekir.
