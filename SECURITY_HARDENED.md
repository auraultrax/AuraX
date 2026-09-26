# Aura X güvenlik sertleştirmesi

Bu sürümde hassas kimlik bilgileri istemci tarafından okunamaz hale getirildi.

- Kullanıcı parolaları `users` belgesinden çıkarılır ve yalnızca server-side `privateCredentials` koleksiyonunda tutulur.
- Eski `users.password` kayıtları başarılı ilk girişte otomatik olarak taşınır ve silinir.
- Oda parolaları `roomSecrets` koleksiyonunda server-side PBKDF2 ile saklanır; oda belgesine düz metin parola yazılmaz.
- Eski oda parolaları sistem yöneticisinin başarılı girişinde otomatik olarak taşınır.
- Odaya katılım ve oda adı/şifre değişimi Cloud Functions üzerinden doğrulanır.
- Kilitli oda, sistem yöneticisi dahil kimse için girişe açılamaz.
- Bildirim yazma işlemleri doğrudan Firestore istemci yazısından çıkarıldı; Cloud Functions üzerinden yapılır.
- FCM push tokenları da yalnızca Cloud Functions üzerinden kaydedilir.
- Sistem yöneticisi dışındaki kullanıcıların ban, kısıtlama, onay rozeti ve duyuru yönetimi Rules seviyesinde engellenir.
- Raporlar yalnızca sistem yöneticisine okunabilir.
- Kullanıcıların kendi profil alanlarında izin verilen alanlar beyaz listeyle sınırlandırılmıştır.
- Firebase Auth normal girişte Google popup kullanılmaz; Google yalnızca kayıt ve şifre sıfırlama akışında kullanılır.
