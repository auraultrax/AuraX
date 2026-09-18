# Aura Ultra X — Güvenlik mimarisi

Firebase yalnızca Authentication katmanında kullanılır. Tarayıcıdaki admin değişkeni güvenlik sınırı değildir.

Uygulama verisi Supabase `aurax_documents` üzerinde tutulur. Tarayıcı bu tabloya doğrudan erişemez; Firebase ID token'ı `aurax-data` Edge Function tarafından Google'ın Firebase imzalama anahtarları ile doğrulanır ve sonra server-side yetki kontrolü yapılır.

Medya yükleme/silme `aurax-media` Edge Function üzerinden yapılır. Supabase service-role anahtarı tarayıcıya konulmaz.

`aurax_admins` tablosunda aynı anda yalnızca bir aktif admin bulunabilir. Oda kilitleme/silme, kullanıcı ban/kısıtlama ve diğer yönetim işlemleri backend tarafından admin UID ile doğrulanır.

Kullanıcı profili, oda, mesaj, rapor ve yönetim işlemleri `aurax_audit_log` tablosuna işlem bazında kaydedilir.
