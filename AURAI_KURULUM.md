# AURAI kurulumu (kendi modelin)

## Önce bilmen gerekenler
- Sıfırdan bir dil modeli eğitmek (Meta'nın yaptığı gibi) çok büyük veri, aylarca GPU ve çok yüksek bütçe ister. Bu pakette böyle bir model yoktur.
- Gerçekçi yol: açık ağırlıklı hazır bir modeli (Llama, Qwen, Gemma, Mistral gibi; lisansını kontrol et) **kendi sunucunda** çalıştırmak ve "AURAI / Beray" adıyla sunmak. İleride kendi verinle ince ayar (fine-tune) yapılabilir.
- Türkçe kalitesi modele göre çok değişir; seçmeden önce Türkçe sorularla dene.
- Kullanıcı mesajları yalnızca senin sunucuna ve Supabase'e gider. Gizlilik metnini ve KVKK uyumunu bir uzmana kontrol ettir.

## 1. Modeli çalıştır
Önce kendi bilgisayarında Ollama ile dene (OpenAI uyumlu adres sunar). Canlı kullanım için GPU'lu bir sunucu kirala; vLLM veya Ollama aynı şekilde `/v1/chat/completions` sunar.
Supabase fonksiyonu **internetten HTTPS ile** erişebilmeli (localhost çalışmaz). Test için Cloudflare Tunnel gibi bir tünel kullanabilirsin. Sunucuyu bir API anahtarıyla koru.

## 2. Supabase tarafı
1. `supabase_aurai_setup.sql` dosyasını SQL Editor'da çalıştır.
2. Secret'ları ekle:
   `supabase secrets set AURAI_API_URL=https://sunucun.com/v1 AURAI_MODEL=model-adi AURAI_API_KEY=anahtar`
   İsteğe bağlı: `AURAI_DAILY_LIMIT` (kişi başı, varsayılan 30), `AURAI_DAILY_BUDGET` (tüm site, varsayılan 5000).
3. `supabase functions deploy aurai-chat`

## 3. Siteyi güncelle
`index.html`, `aurai-widget.js`, `sw.js` ve `supabase/` klasörünü GitHub'a yükle. Giriş yapan kullanıcıda sağ altta "✨ AURAI" düğmesi çıkar. Düğme alt menüyle çakışırsa `aurai-widget.js` içindeki `bottom: calc(88px ...)` değerini ayarla.

## Güvenlik notları
- Fonksiyon yalnızca giriş yapmış kullanıcıyı kabul eder; sayaç tablosuna istemci erişemez.
- AURAI diğer kullanıcıların verilerini görmez; sadece o sohbette yazılanları bilir.
- Kriz algılama anahtar kelimelidir ve her ifadeyi yakalamaz; canlıya almadan önce bir ruh sağlığı uzmanına gösterilmesi önerilir.
- Canlı sunucu ve gerçek Supabase projesiyle doğrulanmadı; önce test projesinde dene.
