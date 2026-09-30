-- Aura X / Supabase sıfır kurulum şeması
-- Uygulama verilerini JSONB içinde tutar; mevcut frontend veri şeklini korumak için tasarlanmıştır.

create extension if not exists pgcrypto;

create table if not exists public.users (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.account_links (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.posts (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.rooms (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.room_messages (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.statuses (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.notifications (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.announcements (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.reports (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.votes (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.restrictions (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.banned_users (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.banned_ips (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.banned_devices (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.banned_emails (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.push_tokens (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create or replace function public.aurax_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

do $$
declare r record;
begin
  for r in select table_name from information_schema.tables where table_schema='public' and table_name in ('users','account_links','posts','rooms','room_messages','statuses','notifications','announcements','reports','votes','restrictions','banned_users','banned_ips','banned_devices','banned_emails','push_tokens') loop
    execute format('drop trigger if exists %I_touch on public.%I', r.table_name, r.table_name);
    execute format('create trigger %I_touch before update on public.%I for each row execute function public.aurax_touch_updated_at()', r.table_name, r.table_name);
  end loop;
end $$;

create or replace function public.aurax_current_username()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select data->>'username'
  from public.users
  where data->>'authUid' = auth.uid()::text
  limit 1;
$$;

create or replace function public.aurax_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.users
    where data->>'authUid' = auth.uid()::text
      and coalesce(data->>'role','user') = 'admin'
  );
$$;

-- RLS

do $$
declare r record;
begin
  for r in select table_name from information_schema.tables where table_schema='public' and table_name in ('users','account_links','posts','rooms','room_messages','statuses','notifications','announcements','reports','votes','restrictions','banned_users','banned_ips','banned_devices','banned_emails','push_tokens') loop
    execute format('alter table public.%I enable row level security', r.table_name);
  end loop;
end $$;

-- USERS
 drop policy if exists users_select_authenticated on public.users;
create policy users_select_authenticated on public.users for select to authenticated using (true);
drop policy if exists users_insert_self on public.users;
create policy users_insert_self on public.users for insert to authenticated with check ((data->>'authUid') = auth.uid()::text or public.aurax_is_admin());
drop policy if exists users_update_self_or_admin on public.users;
create policy users_update_self_or_admin on public.users for update to authenticated using ((data->>'authUid') = auth.uid()::text or public.aurax_is_admin()) with check ((data->>'authUid') = auth.uid()::text or public.aurax_is_admin());
drop policy if exists users_delete_self_or_admin on public.users;
create policy users_delete_self_or_admin on public.users for delete to authenticated using ((data->>'authUid') = auth.uid()::text or public.aurax_is_admin());

-- Generic application tables

drop policy if exists posts_select_authenticated on public.posts;
create policy posts_select_authenticated on public.posts for select to authenticated using (true);
drop policy if exists posts_insert_authenticated on public.posts;
create policy posts_insert_authenticated on public.posts for insert to authenticated with check ((data->>'author') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists posts_update_owner_or_admin on public.posts;
create policy posts_update_owner_or_admin on public.posts for update to authenticated using ((data->>'author') = public.aurax_current_username() or public.aurax_is_admin()) with check ((data->>'author') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists posts_delete_owner_or_admin on public.posts;
create policy posts_delete_owner_or_admin on public.posts for delete to authenticated using ((data->>'author') = public.aurax_current_username() or public.aurax_is_admin());

-- Rooms: members/admin/owner/admin can read; writes are limited to participants/admin.
drop policy if exists rooms_select_authenticated on public.rooms;
create policy rooms_select_authenticated on public.rooms for select to authenticated using (true);
drop policy if exists rooms_insert_authenticated on public.rooms;
create policy rooms_insert_authenticated on public.rooms for insert to authenticated with check ((data->>'admin') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists rooms_update_owner_or_admin on public.rooms;
create policy rooms_update_owner_or_admin on public.rooms for update to authenticated using ((data->>'admin') = public.aurax_current_username() or public.aurax_is_admin() or exists (select 1 from jsonb_array_elements_text(coalesce(data->'members','[]'::jsonb)) m where m = public.aurax_current_username())) with check ((data->>'admin') = public.aurax_current_username() or public.aurax_is_admin() or exists (select 1 from jsonb_array_elements_text(coalesce(data->'members','[]'::jsonb)) m where m = public.aurax_current_username()));
drop policy if exists rooms_delete_owner_or_admin on public.rooms;
create policy rooms_delete_owner_or_admin on public.rooms for delete to authenticated using ((data->>'admin') = public.aurax_current_username() or public.aurax_is_admin());

-- Room messages (available for a future normalized message path)
drop policy if exists room_messages_select_authenticated on public.room_messages;
create policy room_messages_select_authenticated on public.room_messages for select to authenticated using (true);
drop policy if exists room_messages_insert_authenticated on public.room_messages;
create policy room_messages_insert_authenticated on public.room_messages for insert to authenticated with check ((data->>'author') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists room_messages_update_owner_or_admin on public.room_messages;
create policy room_messages_update_owner_or_admin on public.room_messages for update to authenticated using ((data->>'author') = public.aurax_current_username() or public.aurax_is_admin()) with check ((data->>'author') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists room_messages_delete_owner_or_admin on public.room_messages;
create policy room_messages_delete_owner_or_admin on public.room_messages for delete to authenticated using ((data->>'author') = public.aurax_current_username() or public.aurax_is_admin());

-- Statuses
 drop policy if exists statuses_select_authenticated on public.statuses;
create policy statuses_select_authenticated on public.statuses for select to authenticated using (true);
drop policy if exists statuses_insert_self on public.statuses;
create policy statuses_insert_self on public.statuses for insert to authenticated with check ((data->>'author') = public.aurax_current_username() or data->>'username' = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists statuses_update_self on public.statuses;
create policy statuses_update_self on public.statuses for update to authenticated using ((data->>'author') = public.aurax_current_username() or id = public.aurax_current_username() or public.aurax_is_admin()) with check ((data->>'author') = public.aurax_current_username() or id = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists statuses_delete_self on public.statuses;
create policy statuses_delete_self on public.statuses for delete to authenticated using ((data->>'author') = public.aurax_current_username() or id = public.aurax_current_username() or public.aurax_is_admin());

-- Notifications
 drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications for select to authenticated using ((data->>'to') = public.aurax_current_username() or (data->>'from') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists notifications_insert_authenticated on public.notifications;
create policy notifications_insert_authenticated on public.notifications for insert to authenticated with check ((data->>'from') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications for update to authenticated using ((data->>'to') = public.aurax_current_username() or public.aurax_is_admin()) with check ((data->>'to') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists notifications_delete_admin on public.notifications;
create policy notifications_delete_admin on public.notifications for delete to authenticated using (public.aurax_is_admin() or (data->>'to') = public.aurax_current_username());

-- Announcements
 drop policy if exists announcements_select_authenticated on public.announcements;
create policy announcements_select_authenticated on public.announcements for select to authenticated using (true);
drop policy if exists announcements_admin_write on public.announcements;
create policy announcements_admin_write on public.announcements for all to authenticated using (public.aurax_is_admin()) with check (public.aurax_is_admin());

-- Reports
 drop policy if exists reports_select_admin on public.reports;
create policy reports_select_admin on public.reports for select to authenticated using (public.aurax_is_admin());
drop policy if exists reports_insert_authenticated on public.reports;
create policy reports_insert_authenticated on public.reports for insert to authenticated with check ((data->>'reportedBy') = public.aurax_current_username() or (data->>'author') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists reports_delete_admin on public.reports;
create policy reports_delete_admin on public.reports for delete to authenticated using (public.aurax_is_admin());

-- Votes: signed-in users can read/write their own vote; admin can manage all.
drop policy if exists votes_select_authenticated on public.votes;
create policy votes_select_authenticated on public.votes for select to authenticated using (true);
drop policy if exists votes_insert_self on public.votes;
create policy votes_insert_self on public.votes for insert to authenticated with check ((data->>'voter') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists votes_update_self_or_admin on public.votes;
create policy votes_update_self_or_admin on public.votes for update to authenticated using ((data->>'voter') = public.aurax_current_username() or public.aurax_is_admin()) with check ((data->>'voter') = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists votes_delete_self_or_admin on public.votes;
create policy votes_delete_self_or_admin on public.votes for delete to authenticated using ((data->>'voter') = public.aurax_current_username() or public.aurax_is_admin());

-- Admin/security collections

do $$
declare t text;
begin
  foreach t in array array['restrictions','banned_users','banned_ips','banned_devices','banned_emails'] loop
    execute format('drop policy if exists %I_admin_all on public.%I',t,t);
    execute format('create policy %I_admin_all on public.%I for all to authenticated using (public.aurax_is_admin() or (case when %L = ''restrictions'' then id = public.aurax_current_username() else false end)) with check (public.aurax_is_admin() or (case when %L = ''restrictions'' then id = public.aurax_current_username() else false end))',t,t,t,t);
  end loop;
end $$;

-- Push tokens: each record stores `username` in data.
drop policy if exists push_tokens_owner on public.push_tokens;
create policy push_tokens_owner on public.push_tokens for all to authenticated using ((data->>'username') = public.aurax_current_username() or public.aurax_is_admin()) with check ((data->>'username') = public.aurax_current_username() or public.aurax_is_admin());

-- Account links: owner/admin only
drop policy if exists account_links_owner on public.account_links;
create policy account_links_owner on public.account_links for all to authenticated using ((data->>'authUid') = auth.uid()::text or public.aurax_is_admin()) with check ((data->>'authUid') = auth.uid()::text or public.aurax_is_admin());

-- Realtime publication

do $$
declare t text;
begin
  foreach t in array array['users','account_links','posts','rooms','room_messages','statuses','notifications','announcements','reports','votes','restrictions','banned_users','banned_ips','banned_devices','banned_emails','push_tokens'] loop
    begin execute format('alter publication supabase_realtime add table public.%I', t); exception when duplicate_object then null; end;
  end loop;
end $$;

-- Replace admin-only ban read policies with owner/admin read so login security checks can run.
drop policy if exists banned_users_admin_all on public.banned_users;
drop policy if exists banned_users_user_read on public.banned_users;
create policy banned_users_user_read on public.banned_users for select to authenticated using (id = public.aurax_current_username() or public.aurax_is_admin());
drop policy if exists banned_ips_admin_all on public.banned_ips;
drop policy if exists banned_ips_user_read on public.banned_ips;
create policy banned_ips_user_read on public.banned_ips for select to authenticated using (
  public.aurax_is_admin() or exists (select 1 from public.users u where u.data->>'authUid' = auth.uid()::text and u.data->>'ipHash' = public.banned_ips.id)
);
drop policy if exists banned_devices_admin_all on public.banned_devices;
drop policy if exists banned_devices_user_read on public.banned_devices;
create policy banned_devices_user_read on public.banned_devices for select to authenticated using (
  public.aurax_is_admin() or exists (select 1 from public.users u where u.data->>'authUid' = auth.uid()::text and u.data->>'deviceHash' = public.banned_devices.id)
);
drop policy if exists reports_select_owner_or_admin on public.reports;
create policy reports_select_owner_or_admin on public.reports for select to authenticated using (public.aurax_is_admin() or (data->>'reportedBy') = public.aurax_current_username() or (data->>'author') = public.aurax_current_username());

-- The frontend adapter uses the Data API; RLS remains the actual authorization layer.
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on function public.aurax_current_username() to authenticated;
grant execute on function public.aurax_is_admin() to authenticated;

drop policy if exists banned_users_admin_write on public.banned_users;
create policy banned_users_admin_write on public.banned_users for all to authenticated using (public.aurax_is_admin()) with check (public.aurax_is_admin());
drop policy if exists banned_ips_admin_write on public.banned_ips;
create policy banned_ips_admin_write on public.banned_ips for all to authenticated using (public.aurax_is_admin()) with check (public.aurax_is_admin());
drop policy if exists banned_devices_admin_write on public.banned_devices;
create policy banned_devices_admin_write on public.banned_devices for all to authenticated using (public.aurax_is_admin()) with check (public.aurax_is_admin());
drop policy if exists banned_emails_admin_write on public.banned_emails;
create policy banned_emails_admin_write on public.banned_emails for all to authenticated using (public.aurax_is_admin()) with check (public.aurax_is_admin());

-- Anon kullanıcı adı kontrolü; kullanıcı verisinin kendisini expose etmez.
create or replace function public.aurax_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists(select 1 from public.users where id = trim(p_username));
$$;
grant execute on function public.aurax_username_available(text) to anon, authenticated;

-- Giriş/registration öncesi ağ yasağını, yalnızca boolean döndüren RPC ile kontrol eder.
create or replace function public.aurax_network_banned(p_ip_hash text, p_device_hash text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.banned_ips where id = p_ip_hash)
      or exists(select 1 from public.banned_devices where id = p_device_hash);
$$;
grant execute on function public.aurax_network_banned(text, text) to anon, authenticated;

-- Duyuru splash ekranı giriş yapılmadan da okunabilsin.
drop policy if exists announcements_public_read on public.announcements;
create policy announcements_public_read on public.announcements for select to anon using (true);

grant select on public.announcements to anon;
