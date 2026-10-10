-- AURAI günlük kullanım sayacı. Supabase SQL Editor'da bir kez çalıştır (önce test projesinde).
create table if not exists public.aurai_usage (
  user_id uuid not null,
  day date not null default current_date,
  count integer not null default 0,
  primary key (user_id, day)
);
alter table public.aurai_usage enable row level security;  -- politika yok: yalnızca service_role erişir
revoke all on public.aurai_usage from anon, authenticated;

create or replace function public.aurai_bump(p_user uuid)
returns integer language sql security definer set search_path = public as $$
  insert into public.aurai_usage (user_id, day, count) values (p_user, current_date, 1)
  on conflict (user_id, day) do update set count = public.aurai_usage.count + 1
  returning count;
$$;
revoke all on function public.aurai_bump(uuid) from public, anon, authenticated;
grant execute on function public.aurai_bump(uuid) to service_role;
