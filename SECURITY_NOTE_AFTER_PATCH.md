# Aura X – 4 soruna ilişkin not

1. Oda YouTube sistemi artık URL alanı yerine YouTube Data API v3 arama arayüzü kullanır. `index.html` içindeki `YOUTUBE_API_KEY` alanına bir API anahtarı gerekir. GitHub Pages alan adını API anahtarında HTTP referrer olarak kısıtlayın.
2. YouTube IFrame oynatıcı daha sağlam başlatılır ve oynatılamayan/embedding kapalı videolar için hata gösterir.
3. Keşfet video yüklemesinin 60 saniyede yanlışlıkla kesilmemesi için bekleme süresi 10 dakikaya çıkarıldı. Firebase Storage'ın proje planı ve Rules'u yine doğru olmalıdır.
4. Admin şifre kurtarma için uygulamada güvensiz bir "herkes sıfırlasın" yolu eklenmedi. `generateAdminPasswordRecord("YeniSifre")` yardımcı fonksiyonu yeni PBKDF2 kaydı üretir; çıktı Firebase users/A_UR_A_XX belgesindeki `password` alanına yalnızca sahibi tarafından konulmalıdır.

Mevcut dosyalar silinmedi; yalnızca index.html değiştirildi ve bu not eklendi.
