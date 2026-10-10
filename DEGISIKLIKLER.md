# Aura X - Bu sürümdeki değişiklikler

## Önce yapılması gerekenler (sırayla)
1. `supabase_username_change.sql` dosyasını Supabase SQL Editor'da çalıştırın (önce test projesinde).
2. Edge function'ları yeniden deploy edin: `username-login`, `youtube-search`.
3. `index.html` ve `supabase/` klasörünü GitHub'a yükleyin.

## Güvenlik
- youtube-search: yalnızca giriş yapmış kullanıcılar arama yapabilir (API kotası korunur).
- username-login / youtube-search: hatalı CORS import'u düzeltildi (fonksiyon çalışmıyordu).
- Sohbet: resim URL'si ve emoji tepki anahtarları artık kaçışlanıyor (XSS kapatıldı).

## Yeni / düzeltilen özellikler
- Duyuru: her duyuru kullanıcıya bir kez gösterilir. Hiç oda girmemiş kullanıcılar akışta görür; daha önce oda girmiş kullanıcılar duyuruyu odanın içinde görür.
- Oda içi (+) menüsü: resim, video, kişiye özel mesaj, çıkartma gönder/oluştur.
- Medya artık Supabase Storage'a yüklenir (oda belgesi şişmez, gönderim hızlanır). Resimler gönderilmeden önce küçültülür.
- Klavye açılınca mesaj kutusu klavyenin hemen üstünde kalır (siyah boşluk düzeltildi).
- Keşfet akışı tek kez yüklenir (tetiklemeler birleştirildi).
- Profilde kullanıcı adı değiştirilebilir. Aynı ad (büyük/küçük harf farkı dahil) kabul edilmez. Tüm mesaj ve referanslar yeni ada taşınır.
- Çıkartma oluşturma (512px, kare) ve odada paylaşma. Başkasının çıkartmasını "Çıkartmaya ekle" ile kaydetme.
- Mobil: profil, oda listesi ve oda oluşturma butonları alt çentik/ev çubuğunun altında kalmaz.
- Mobil: yazı alanları 16px (iOS'un otomatik yakınlaştırmasını önler).

## AURAI (yapay zekâ asistanı)
1. `supabase_aurai_setup.sql` dosyasını SQL Editor'da çalıştır.
2. Secret'ları tanımla: `AURAI_API_URL`, `AURAI_MODEL`, `AURAI_API_KEY` (ayrıntı: `AURAI_KURULUM.md`).
3. `supabase functions deploy aurai-chat` komutuyla fonksiyonu yükle.
4. `index.html`, `aurai-widget.js`, `sw.js` ve `supabase/` klasörünü GitHub'a yükle.
- Giriş yapmış kullanıcıya sağ altta "✨ AURAI" düğmesi çıkar. Kişi başı günlük limit ve site geneli bütçe sigortası vardır; kriz mesajları limitten muaftır.
