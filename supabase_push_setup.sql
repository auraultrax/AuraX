-- Aura X: Push bildirimlerinin üretim kurulumu
-- Reklam kampanyası kuralları supabase_final_security_setup.sql içindedir.

create extension if not exists pgcrypto;

-- Push teslimatlarının denetlenebilmesi için durum tablosu.
create table if not exists public.push_delivery_log (
  notification_id text primary key,
  attempted_at timestamptz not null default now(),
  sent_count integer not null default 0,
  removed_count integer not null default 0,
  last_error text
);
alter table public.push_delivery_log enable row level security;
revoke all on public.push_delivery_log from anon, authenticated;

-- Push subscription endpoint/key bilgileri sadece aboneliğin sahibine açıktır.
revoke all on public.push_tokens from anon;
drop policy if exists push_tokens_owner on public.push_tokens;
create policy push_tokens_owner on public.push_tokens
for all to authenticated
using ((data->>'username') = public.aurax_current_username() or public.aurax_is_admin())
with check ((data->>'username') = public.aurax_current_username() or public.aurax_is_admin());

-- Supabase Dashboard > Database > Webhooks:
-- notifications / INSERT -> Edge Function: send-push
-- Authorization: Bearer <SERVICE_ROLE_KEY>
-- Content-Type: application/json
-- Edge Function tarafındaki service-role kontrolü korunmalıdır.
