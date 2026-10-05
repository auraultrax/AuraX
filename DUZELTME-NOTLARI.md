# Aura X — Supabase geçişi sonrası düzeltmeler

## Kök nedenler
1. **Oda ekranı çöküyordu**: `supabase-bridge.js` içinde tek belge için `onSnapshot` yoktu. Odaya girince `enterRoomUI` hata veriyor, başlıktaki Çık / Çizim / YouTube / Üyeler butonları ve sohbet hiç çizilmiyordu. Aynı eksik yüzünden normal kullanıcı girişi ve sayfa yenilemede otomatik giriş de `onSnapshot is not a function` ile düşüyordu (yalnızca admin bu satırı atlıyordu).
2. **Bildirim sistemi kapatılmıştı**: `subscribeNotifications` hiçbir şeyi dinlemiyor, rozetler siliniyor, `openNotifPanel` hemen `return` ediyor, zil `display:none!important` ile gizliydi, "Özel Bildirimler" butonu hiçbir yere bağlı değildi.
3. **Durum paylaşılamıyordu**: `createStatus` içinde `supabaseUid` / `SupabaseUid` yazım hatası.
4. **RLS sessiz hatası**: başkasının gönderisine beğeni/yorum, oy verme, şifreyle odaya katılma veritabanı kuralları yüzünden reddediliyordu ve uygulama hata göstermiyordu.
5. **`doc.ref` eksikti**: özel mesaj düzenleme/silme, ay sonu oy sıfırlama, hesap silme toplu işlemleri çöküyordu.
6. **Google/Apple redirect_uri_mismatch**: kod değil, Google/Apple konsol ayarı (bkz. `supabase-setup.md` 11. bölüm).

## Değişen dosyalar
- `index.html`, `supabase-bridge.js`, `sw.js` (önbellek sürümü v10)
- Yeni: `supabase_fix_patch.sql`, `supabase/functions/send-push/index.ts`, `supabase/config.toml` (send-push eklendi), `supabase-setup.md` (10-12. bölüm)

## Yapman gerekenler
1. `supabase_fix_patch.sql` dosyasını SQL Editor'da çalıştır.
2. Google/Apple konsol ayarını yap (`supabase-setup.md` → 11).
3. İstersen kapalıyken bildirim için `supabase-setup.md` → 12.

7. **Oda RLS güvenliği**: eski `rooms` UPDATE politikası odadaki her üyeye tüm oda JSONB belgesini değiştirme imkânı veriyordu. Yeni `aurax_rooms_guard` + yönetici-aware RLS ile normal üyeler yalnızca izinli sohbet etkileşimlerini yapabiliyor; oda yönetimi gerçek oda yöneticisi/sistem admini ile sınırlandırılıyor.
8. **Şikâyet alanı uyumu**: şikâyet kaydında `reportedBy` ana alanı kullanıldı; eski `reporter` kayıtları da geriye dönük okunabiliyor.
