# İstenen Güncellemeler

1. Oda kurucuları ve yardımcı oda yöneticileri oda adını ve şifresini değiştirebilir.
2. Normal Giriş Yap akışında Google hesap seçimi kaldırıldı. Google yalnızca kayıt ve şifre sıfırlama akışlarında kullanılır.
3. Profil ekranına Şifremi Değiştir ve Hesabımı Sil eklendi.
4. Bildirim kayıtları FCM Cloud Function ile sistem dışı web/masaüstü bildirimlerine gönderilir.
5. Mevcut mavi tik ve sarı yıldız verme/kaldırma yönetimi korunmuştur.
6. Kilitlenen/sistem tarafından kapatılan/kullanıcıya kısıtlanan odalara admin oturumuyla da girilemez.

## Deploy

Firebase Functions ve Firestore Rules birlikte deploy edilmelidir:

`firebase login`
`firebase use aura-ultra-x`
`cd functions && npm install`
`firebase deploy --only functions,firestore:rules`

Bildirimlerin sistem dışında çalışması için tarayıcı/işletim sistemi bildirim izni de verilmelidir.
