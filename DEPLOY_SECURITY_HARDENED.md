# Güvenlikli Aura X sürümünü deploy etme

Bu paket, Firestore Rules ve Cloud Functions değişikliklerini birlikte içerir. İkisini birlikte deploy edin.

```bash
firebase deploy --only firestore:rules,functions
```

Deploy sonrasında:

1. Eski kullanıcılar normal kullanıcı adı/şifreleriyle ilk kez giriş yaptığında eski `users.password` kaydı server-side `privateCredentials` alanına taşınır ve `users.password` silinir.
2. Sistem yöneticisi giriş yaptığında eski düz metin oda şifreleri varsa `roomSecrets` alanına taşınır ve `rooms.password` silinir.
3. Yeni oda oluşturma, oda katılımı ve oda adı/şifre değişimi Cloud Functions üzerinden yapılır.
4. FCM bildirim tokenı istemci tarafından doğrudan Firestore'a yazılmaz; `savePushToken` function'ı kullanılır.

Bu çalışma alanında statik JavaScript/JSON kontrolleri yapıldı. Firebase projesine gerçek deploy ve gerçek cihazla FCM testi bu ortamdan yapılmadı.
