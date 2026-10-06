-- Aura Ultra X — FINAL SUPABASE SECURITY SETUP
-- Fresh project: full schema + legacy compatibility patches + final hardening in one transaction.
begin;

-- ===== supabase_schema.sql =====
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
create policy rooms_update_owner_or_admin on public.rooms
for update to authenticated
using (
  public.aurax_is_admin()
  or (data->>'admin') = public.aurax_current_username()
  or exists (
    select 1 from jsonb_array_elements_text(coalesce(data->'admins','[]'::jsonb)) m
    where m = public.aurax_current_username()
  )
  or exists (
    select 1 from jsonb_array_elements_text(coalesce(data->'members','[]'::jsonb)) m
    where m = public.aurax_current_username()
  )
)
with check (true);

drop policy if exists rooms_delete_owner_or_admin on public.rooms;
create policy rooms_delete_owner_or_admin on public.rooms for delete to authenticated using ((data->>'admin') = public.aurax_current_username() or public.aurax_is_admin());

-- Room security guard: ordinary members may update only safe room-interaction fields.
-- Room owner/co-admin/system admin may manage room settings and membership.
create or replace function public.aurax_rooms_guard()
returns trigger
language plpgsql
as $$
declare
  v_user text := public.aurax_current_username();
  v_is_room_admin boolean;
  old_members jsonb := coalesce(old.data->'members', '[]'::jsonb);
  new_members jsonb := coalesce(new.data->'members', '[]'::jsonb);
  old_messages jsonb := coalesce(old.data->'messages', '[]'::jsonb);
  new_messages jsonb := coalesce(new.data->'messages', '[]'::jsonb);
  old_msg jsonb;
  new_msg jsonb;
  old_id text;
  new_id text;
  old_author text;
  k text;
  old_non_self_reactions jsonb;
  new_non_self_reactions jsonb;
begin
  -- SQL editor/service role and explicit trusted RPC updates bypass the guard.
  if auth.uid() is null or coalesce(current_setting('aurax.bypass_room_guard', true), '') = '1' then
    return new;
  end if;

  if v_user is null then
    raise exception 'Oturum doğrulanamadı.';
  end if;

  v_is_room_admin := public.aurax_is_admin()
    or old.data->>'admin' = v_user
    or exists (
      select 1
      from jsonb_array_elements_text(coalesce(old.data->'admins', '[]'::jsonb)) a
      where a = v_user
    );

  -- Oda sahibi / oda yöneticisi / sistem yöneticisi mevcut davranışı koruyarak
  -- oda yönetiminin tamamını yapabilir.
  if v_is_room_admin then
    return new;
  end if;

  -- Normal üyeler oda ayarlarını, yönetici listesini, şifreyi, susturma/kısıtlama
  -- listelerini veya sabit mesajı değiştiremez. Yalnızca aşağıdaki etkileşim alanları
  -- istemci tarafından normal üyeye açıktır.
  foreach k in array array[
    'admin','admins','password','displayName','ownerUid','muted','restrictedMembers',
    'roomAccess','drawingAccess','videoAccess','pinnedMessageId','deleted'
  ] loop
    if (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'Bu alanı değiştirme yetkiniz yok: %', k;
    end if;
  end loop;

  -- Üye yalnızca kendisini odadan çıkarabilir; başka kullanıcı ekleme/çıkarma yok.
  if new_members is distinct from old_members then
    if jsonb_array_length(new_members) > jsonb_array_length(old_members) then
      raise exception 'Odaya kullanıcı ekleme yetkiniz yok.';
    end if;
    if jsonb_array_length(new_members) <> (select count(distinct m) from jsonb_array_elements_text(new_members) m) then
      raise exception 'Oda üyelik listesi geçersiz.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(new_members) n
      where n <> v_user
        and not exists (
          select 1 from jsonb_array_elements_text(old_members) m where m = n
        )
    ) then
      raise exception 'Odaya kullanıcı ekleme yetkiniz yok.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(old_members) m
      where m <> v_user
        and not exists (
          select 1 from jsonb_array_elements_text(new_members) n where n = m
        )
    ) then
      raise exception 'Başka bir kullanıcıyı odadan çıkarma yetkiniz yok.';
    end if;
  end if;

  -- YouTube/çizim senkronu normal üyeler için mevcut uygulama davranışında açıktır;
  -- bu alanlar burada ayrıca engellenmez. Queue değişiminde ise üyenin yalnızca
  -- ekleme yapabilmesi için mevcut kayıtların korunmasını zorunlu tut.
  if (new.data->'youtubeQueue') is distinct from (old.data->'youtubeQueue') then
    old_non_self_reactions := coalesce(old.data->'youtubeQueue', '[]'::jsonb);
    new_non_self_reactions := coalesce(new.data->'youtubeQueue', '[]'::jsonb);
    for old_msg in select value from jsonb_array_elements(old_non_self_reactions) loop
      select value into new_msg
      from jsonb_array_elements(new_non_self_reactions)
      where value->>'id' = old_msg->>'id'
      limit 1;
      if new_msg is null then
        raise exception 'YouTube kuyruğundaki mevcut videoları silemezsiniz.';
      end if;
      if new_msg is distinct from old_msg then
        raise exception 'YouTube kuyruğundaki mevcut videoları değiştiremezsiniz.';
      end if;
    end loop;
  end if;

  -- Mesaj güvenliği:
  -- * Yeni mesaj yalnızca mevcut kullanıcı adına yazılabilir.
  -- * Başkasının mesajı metin/yazar/tarih vb. açıdan değiştirilemez; yalnızca kendi
  --   reaksiyonunu ekleyip kaldırabilir.
  -- * Kendi mesajını düzenleme/silme mevcut arayüz davranışına göre serbesttir.
  if new_messages is distinct from old_messages then
    -- Eski mesajların her biri için aynı id ile gelen yeni kaydı denetle.
    for old_msg in select value from jsonb_array_elements(old_messages) loop
      old_id := old_msg->>'id';
      select value into new_msg
      from jsonb_array_elements(new_messages)
      where value->>'id' = old_id
      limit 1;

      if new_msg is null then
        if old_msg->>'author' <> v_user then
          raise exception 'Başka bir kullanıcının mesajını silemezsiniz.';
        end if;
        continue;
      end if;

      old_author := old_msg->>'author';
      if old_author <> v_user then
        -- Başkasının mesajında reactions dışında hiçbir alan değişemez.
        for k in
          select key from jsonb_each(old_msg)
          union
          select key from jsonb_each(new_msg)
        loop
          if k <> 'reactions' and (old_msg->k) is distinct from (new_msg->k) then
            raise exception 'Başka bir kullanıcının mesajını değiştiremezsiniz.';
          end if;
        end loop;

        -- Reaksiyon değişikliği varsa yalnızca mevcut kullanıcının üyeliği değişebilir.
        old_non_self_reactions := '{}'::jsonb;
        new_non_self_reactions := '{}'::jsonb;
        for k in
          select key from jsonb_each(coalesce(old_msg->'reactions', '{}'::jsonb))
          union
          select key from jsonb_each(coalesce(new_msg->'reactions', '{}'::jsonb))
        loop
          old_non_self_reactions := jsonb_set(
            old_non_self_reactions,
            array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(old_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )),
            true
          );
          new_non_self_reactions := jsonb_set(
            new_non_self_reactions,
            array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(new_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )),
            true
          );
        end loop;
        if old_non_self_reactions is distinct from new_non_self_reactions then
          raise exception 'Başka kullanıcıların reaksiyonlarını değiştiremezsiniz.';
        end if;
      else
        -- Kendi mevcut mesajında yalnızca mesaj içeriği/medyası/düzenlendi bilgisi/
        -- yanıt ve reaksiyonlar değişsin; author/id korunur.
        for k in
          select key from jsonb_each(old_msg)
          union
          select key from jsonb_each(new_msg)
        loop
          if k not in ('id','author','text','img','edited','replyTo','timestamp','reactions','recipients')
             and (old_msg->k) is distinct from (new_msg->k) then
            raise exception 'Mesajın bu alanını değiştiremezsiniz.';
          end if;
        end loop;

        old_non_self_reactions := '{}'::jsonb;
        new_non_self_reactions := '{}'::jsonb;
        for k in
          select key from jsonb_each(coalesce(old_msg->'reactions', '{}'::jsonb))
          union
          select key from jsonb_each(coalesce(new_msg->'reactions', '{}'::jsonb))
        loop
          old_non_self_reactions := jsonb_set(
            old_non_self_reactions, array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(old_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )), true
          );
          new_non_self_reactions := jsonb_set(
            new_non_self_reactions, array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(new_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )), true
          );
        end loop;
        if old_non_self_reactions is distinct from new_non_self_reactions then
          raise exception 'Başka kullanıcıların reaksiyonlarını değiştiremezsiniz.';
        end if;
      end if;
    end loop;

    -- Yeni eklenen mesajların yazarı mutlaka mevcut kullanıcı olmalı.
    for new_msg in select value from jsonb_array_elements(new_messages) loop
      new_id := new_msg->>'id';
      if not exists (
        select 1 from jsonb_array_elements(old_messages) o where o->>'id' = new_id
      ) then
        if coalesce(new_msg->>'author','') <> v_user then
          raise exception 'Başka bir kullanıcı adına mesaj gönderemezsiniz.';
        end if;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists rooms_guard on public.rooms;
create trigger rooms_guard
before update on public.rooms
for each row execute function public.aurax_rooms_guard();


-- Şifreyle ilk giriş RPC'si, oda satırına üye olmayan kullanıcı adına kontrollü yazabilir.
create or replace function public.aurax_join_room(p_room text, p_password text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user text := public.aurax_current_username();
  v_data jsonb;
begin
  if v_user is null then
    raise exception 'Oturum doğrulanamadı.';
  end if;

  select data into v_data from public.rooms where id = p_room for update;
  if not found then
    return false;
  end if;

  if coalesce(v_data->>'password', '') <> coalesce(p_password, '') then
    return false;
  end if;

  if not public.aurax_is_admin() then
    if coalesce((v_data->'roomAccess'->>'locked')::boolean, false) or coalesce((v_data->>'locked')::boolean, false) then
      raise exception 'Bu oda şu anda girişe kapalıdır.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(coalesce(v_data->'restrictedMembers', '[]'::jsonb)) m
      where m = v_user
    ) then
      raise exception 'Bu odaya girişiniz yönetici tarafından kısıtlandı.';
    end if;
  end if;

  if not exists (
    select 1 from jsonb_array_elements_text(coalesce(v_data->'members', '[]'::jsonb)) m where m = v_user
  ) then
    perform set_config('aurax.bypass_room_guard', '1', true);
    update public.rooms
       set data = jsonb_set(data, '{members}', coalesce(data->'members', '[]'::jsonb) || to_jsonb(v_user))
     where id = p_room;
    perform set_config('aurax.bypass_room_guard', '', true);
  end if;
  return true;
end;
$$;
grant execute on function public.aurax_join_room(text, text) to authenticated;



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
create policy reports_insert_authenticated on public.reports for insert to authenticated with check ((data->>'reportedBy') = public.aurax_current_username() or (data->>'reporter') = public.aurax_current_username() or (data->>'author') = public.aurax_current_username() or public.aurax_is_admin());
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
create policy reports_select_owner_or_admin on public.reports for select to authenticated using (public.aurax_is_admin() or (data->>'reportedBy') = public.aurax_current_username() or (data->>'reporter') = public.aurax_current_username() or (data->>'author') = public.aurax_current_username());

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


-- ===== supabase_security_patch.sql =====
-- Aura X / Supabase güvenlik yaması
-- supabase_schema.sql çalıştırıldıktan SONRA, SQL Editor'da tek seferde çalıştırılır. Tekrar çalıştırmak güvenlidir.
--
-- Düzelttikleri:
--  1) Herhangi bir kullanıcının kendi satırına role='admin' yazıp admin olabilmesi
--  2) Kullanıcının kendi mavi tik / özel / ban / oy / lider alanlarını değiştirebilmesi
--  3) Başkasının "A_UR_A_XX" kullanıcı adıyla kayıt olup admin satırı oluşturabilmesi
--  4) media bucket'ında Storage policy olmadığı için video/fotoğraf yüklemenin reddedilmesi

-- 1) Admin yalnızca A_UR_A_XX satırına bağlı Auth hesabıdır.
create or replace function public.aurax_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.users
    where id = 'A_UR_A_XX'
      and data->>'authUid' = auth.uid()::text
      and coalesce(data->>'role','user') = 'admin'
  );
$$;
grant execute on function public.aurax_is_admin() to authenticated;

-- 2) + 3) users tablosunda yetki alanlarını koru
create or replace function public.aurax_users_guard()
returns trigger
language plpgsql
as $$
declare
  protected_keys text[] := array['role','verified','special','banned','bannedBy','bannedAt','votes','isLider'];
  k text;
begin
  -- SQL Editor / service role (auth.uid() yok) ve admin serbest
  if auth.uid() is null or public.aurax_is_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.id = 'A_UR_A_XX' then
      raise exception 'Bu kullanıcı adı ayrılmıştır.';
    end if;
    new.data := (new.data - protected_keys)
      || jsonb_build_object('role','user','verified',false,'special',false,'banned',false,'votes',0);
    return new;
  end if;

  -- UPDATE: normal kullanıcı yetki alanlarına dokunamaz
  foreach k in array protected_keys loop
    if (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'Bu alan değiştirilemez: %', k;
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists users_guard on public.users;
create trigger users_guard
  before insert or update on public.users
  for each row execute function public.aurax_users_guard();

-- 4) Storage: media bucket
drop policy if exists aurax_media_read on storage.objects;
create policy aurax_media_read on storage.objects
  for select to public
  using (bucket_id = 'media');

drop policy if exists aurax_media_insert on storage.objects;
create policy aurax_media_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'media'
    and (name not like 'announcements/%' or public.aurax_is_admin())
  );

drop policy if exists aurax_media_update on storage.objects;
create policy aurax_media_update on storage.objects
  for update to authenticated
  using (bucket_id = 'media' and (owner_id = auth.uid()::text or public.aurax_is_admin()))
  with check (bucket_id = 'media' and (owner_id = auth.uid()::text or public.aurax_is_admin()));

drop policy if exists aurax_media_delete on storage.objects;
create policy aurax_media_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'media' and (owner_id = auth.uid()::text or public.aurax_is_admin()));


-- Room security guard: ordinary members may update only safe room-interaction fields.
-- Room owner/co-admin/system admin may manage room settings and membership.
create or replace function public.aurax_rooms_guard()
returns trigger
language plpgsql
as $$
declare
  v_user text := public.aurax_current_username();
  v_is_room_admin boolean;
  old_members jsonb := coalesce(old.data->'members', '[]'::jsonb);
  new_members jsonb := coalesce(new.data->'members', '[]'::jsonb);
  old_messages jsonb := coalesce(old.data->'messages', '[]'::jsonb);
  new_messages jsonb := coalesce(new.data->'messages', '[]'::jsonb);
  old_msg jsonb;
  new_msg jsonb;
  old_id text;
  new_id text;
  old_author text;
  k text;
  old_non_self_reactions jsonb;
  new_non_self_reactions jsonb;
begin
  -- SQL editor/service role and explicit trusted RPC updates bypass the guard.
  if auth.uid() is null or coalesce(current_setting('aurax.bypass_room_guard', true), '') = '1' then
    return new;
  end if;

  if v_user is null then
    raise exception 'Oturum doğrulanamadı.';
  end if;

  v_is_room_admin := public.aurax_is_admin()
    or old.data->>'admin' = v_user
    or exists (
      select 1
      from jsonb_array_elements_text(coalesce(old.data->'admins', '[]'::jsonb)) a
      where a = v_user
    );

  -- Oda sahibi / oda yöneticisi / sistem yöneticisi mevcut davranışı koruyarak
  -- oda yönetiminin tamamını yapabilir.
  if v_is_room_admin then
    return new;
  end if;

  -- Normal üyeler oda ayarlarını, yönetici listesini, şifreyi, susturma/kısıtlama
  -- listelerini veya sabit mesajı değiştiremez. Yalnızca aşağıdaki etkileşim alanları
  -- istemci tarafından normal üyeye açıktır.
  foreach k in array array[
    'admin','admins','password','displayName','ownerUid','muted','restrictedMembers',
    'roomAccess','drawingAccess','videoAccess','pinnedMessageId','deleted'
  ] loop
    if (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'Bu alanı değiştirme yetkiniz yok: %', k;
    end if;
  end loop;

  -- Üye yalnızca kendisini odadan çıkarabilir; başka kullanıcı ekleme/çıkarma yok.
  if new_members is distinct from old_members then
    if jsonb_array_length(new_members) > jsonb_array_length(old_members) then
      raise exception 'Odaya kullanıcı ekleme yetkiniz yok.';
    end if;
    if jsonb_array_length(new_members) <> (select count(distinct m) from jsonb_array_elements_text(new_members) m) then
      raise exception 'Oda üyelik listesi geçersiz.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(new_members) n
      where n <> v_user
        and not exists (
          select 1 from jsonb_array_elements_text(old_members) m where m = n
        )
    ) then
      raise exception 'Odaya kullanıcı ekleme yetkiniz yok.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(old_members) m
      where m <> v_user
        and not exists (
          select 1 from jsonb_array_elements_text(new_members) n where n = m
        )
    ) then
      raise exception 'Başka bir kullanıcıyı odadan çıkarma yetkiniz yok.';
    end if;
  end if;

  -- YouTube/çizim senkronu normal üyeler için mevcut uygulama davranışında açıktır;
  -- bu alanlar burada ayrıca engellenmez. Queue değişiminde ise üyenin yalnızca
  -- ekleme yapabilmesi için mevcut kayıtların korunmasını zorunlu tut.
  if (new.data->'youtubeQueue') is distinct from (old.data->'youtubeQueue') then
    old_non_self_reactions := coalesce(old.data->'youtubeQueue', '[]'::jsonb);
    new_non_self_reactions := coalesce(new.data->'youtubeQueue', '[]'::jsonb);
    for old_msg in select value from jsonb_array_elements(old_non_self_reactions) loop
      select value into new_msg
      from jsonb_array_elements(new_non_self_reactions)
      where value->>'id' = old_msg->>'id'
      limit 1;
      if new_msg is null then
        raise exception 'YouTube kuyruğundaki mevcut videoları silemezsiniz.';
      end if;
      if new_msg is distinct from old_msg then
        raise exception 'YouTube kuyruğundaki mevcut videoları değiştiremezsiniz.';
      end if;
    end loop;
  end if;

  -- Mesaj güvenliği:
  -- * Yeni mesaj yalnızca mevcut kullanıcı adına yazılabilir.
  -- * Başkasının mesajı metin/yazar/tarih vb. açıdan değiştirilemez; yalnızca kendi
  --   reaksiyonunu ekleyip kaldırabilir.
  -- * Kendi mesajını düzenleme/silme mevcut arayüz davranışına göre serbesttir.
  if new_messages is distinct from old_messages then
    -- Eski mesajların her biri için aynı id ile gelen yeni kaydı denetle.
    for old_msg in select value from jsonb_array_elements(old_messages) loop
      old_id := old_msg->>'id';
      select value into new_msg
      from jsonb_array_elements(new_messages)
      where value->>'id' = old_id
      limit 1;

      if new_msg is null then
        if old_msg->>'author' <> v_user then
          raise exception 'Başka bir kullanıcının mesajını silemezsiniz.';
        end if;
        continue;
      end if;

      old_author := old_msg->>'author';
      if old_author <> v_user then
        -- Başkasının mesajında reactions dışında hiçbir alan değişemez.
        for k in
          select key from jsonb_each(old_msg)
          union
          select key from jsonb_each(new_msg)
        loop
          if k <> 'reactions' and (old_msg->k) is distinct from (new_msg->k) then
            raise exception 'Başka bir kullanıcının mesajını değiştiremezsiniz.';
          end if;
        end loop;

        -- Reaksiyon değişikliği varsa yalnızca mevcut kullanıcının üyeliği değişebilir.
        old_non_self_reactions := '{}'::jsonb;
        new_non_self_reactions := '{}'::jsonb;
        for k in
          select key from jsonb_each(coalesce(old_msg->'reactions', '{}'::jsonb))
          union
          select key from jsonb_each(coalesce(new_msg->'reactions', '{}'::jsonb))
        loop
          old_non_self_reactions := jsonb_set(
            old_non_self_reactions,
            array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(old_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )),
            true
          );
          new_non_self_reactions := jsonb_set(
            new_non_self_reactions,
            array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(new_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )),
            true
          );
        end loop;
        if old_non_self_reactions is distinct from new_non_self_reactions then
          raise exception 'Başka kullanıcıların reaksiyonlarını değiştiremezsiniz.';
        end if;
      else
        -- Kendi mevcut mesajında yalnızca mesaj içeriği/medyası/düzenlendi bilgisi/
        -- yanıt ve reaksiyonlar değişsin; author/id korunur.
        for k in
          select key from jsonb_each(old_msg)
          union
          select key from jsonb_each(new_msg)
        loop
          if k not in ('id','author','text','img','edited','replyTo','timestamp','reactions','recipients')
             and (old_msg->k) is distinct from (new_msg->k) then
            raise exception 'Mesajın bu alanını değiştiremezsiniz.';
          end if;
        end loop;

        old_non_self_reactions := '{}'::jsonb;
        new_non_self_reactions := '{}'::jsonb;
        for k in
          select key from jsonb_each(coalesce(old_msg->'reactions', '{}'::jsonb))
          union
          select key from jsonb_each(coalesce(new_msg->'reactions', '{}'::jsonb))
        loop
          old_non_self_reactions := jsonb_set(
            old_non_self_reactions, array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(old_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )), true
          );
          new_non_self_reactions := jsonb_set(
            new_non_self_reactions, array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(new_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )), true
          );
        end loop;
        if old_non_self_reactions is distinct from new_non_self_reactions then
          raise exception 'Başka kullanıcıların reaksiyonlarını değiştiremezsiniz.';
        end if;
      end if;
    end loop;

    -- Yeni eklenen mesajların yazarı mutlaka mevcut kullanıcı olmalı.
    for new_msg in select value from jsonb_array_elements(new_messages) loop
      new_id := new_msg->>'id';
      if not exists (
        select 1 from jsonb_array_elements(old_messages) o where o->>'id' = new_id
      ) then
        if coalesce(new_msg->>'author','') <> v_user then
          raise exception 'Başka bir kullanıcı adına mesaj gönderemezsiniz.';
        end if;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists rooms_guard on public.rooms;
create trigger rooms_guard
before update on public.rooms
for each row execute function public.aurax_rooms_guard();

-- Oda yöneticilerini RLS tarafında da gerçek yönetici olarak tanı.
drop policy if exists rooms_update_owner_or_admin on public.rooms;
create policy rooms_update_owner_or_admin on public.rooms
for update to authenticated
using (
  public.aurax_is_admin()
  or (data->>'admin') = public.aurax_current_username()
  or exists (
    select 1
    from jsonb_array_elements_text(coalesce(data->'admins','[]'::jsonb)) m
    where m = public.aurax_current_username()
  )
  or exists (
    select 1
    from jsonb_array_elements_text(coalesce(data->'members','[]'::jsonb)) m
    where m = public.aurax_current_username()
  )
)
with check (true);

-- Şifreyle ilk giriş RPC'si, oda satırına üye olmayan kullanıcı adına kontrollü yazabilir.
create or replace function public.aurax_join_room(p_room text, p_password text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user text := public.aurax_current_username();
  v_data jsonb;
begin
  if v_user is null then
    raise exception 'Oturum doğrulanamadı.';
  end if;

  select data into v_data from public.rooms where id = p_room for update;
  if not found then
    return false;
  end if;

  if coalesce(v_data->>'password', '') <> coalesce(p_password, '') then
    return false;
  end if;

  if not public.aurax_is_admin() then
    if coalesce((v_data->'roomAccess'->>'locked')::boolean, false) or coalesce((v_data->>'locked')::boolean, false) then
      raise exception 'Bu oda şu anda girişe kapalıdır.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(coalesce(v_data->'restrictedMembers', '[]'::jsonb)) m
      where m = v_user
    ) then
      raise exception 'Bu odaya girişiniz yönetici tarafından kısıtlandı.';
    end if;
  end if;

  if not exists (
    select 1 from jsonb_array_elements_text(coalesce(v_data->'members', '[]'::jsonb)) m where m = v_user
  ) then
    perform set_config('aurax.bypass_room_guard', '1', true);
    update public.rooms
       set data = jsonb_set(data, '{members}', coalesce(data->'members', '[]'::jsonb) || to_jsonb(v_user))
     where id = p_room;
    perform set_config('aurax.bypass_room_guard', '', true);
  end if;
  return true;
end;
$$;
grant execute on function public.aurax_join_room(text, text) to authenticated;




-- ===== supabase_fix_patch.sql =====
-- Aura X / Supabase düzeltme yaması
-- supabase_schema.sql ve supabase_security_patch.sql çalıştırıldıktan SONRA, SQL Editor'da tek seferde çalıştır.
-- Tekrar çalıştırmak güvenlidir.
--
-- Neden gerekli: Şemadaki RLS kuralları bir kullanıcının BAŞKASINA ait satırı değiştirmesini tamamen
-- engelliyor. Ama uygulama şu işlemleri tam olarak bunu yaparak yapıyor ve hata vermeden sessizce
-- başarısız oluyordu:
--   * başkasının gönderisini beğenme / yorumlama / yanıtlama   (posts.likedBy, posts.comments)
--   * birine oy verme                                          (users.votes)
--   * şifreyle bir odaya ilk kez katılma                       (rooms.members)
--   * özel mesajı gönderen kişinin düzenlemesi                 (notifications)

-- 1) users koruması: oy sayacını yalnızca votes tetikleyicisi (aşağıda) değiştirebilsin.
create or replace function public.aurax_users_guard()
returns trigger
language plpgsql
as $$
declare
  protected_keys text[] := array['role','verified','special','banned','bannedBy','bannedAt','votes','isLider'];
  k text;
begin
  -- SQL Editor / service role (auth.uid() yok), admin ve güvenilir sunucu fonksiyonları serbest
  if auth.uid() is null or public.aurax_is_admin() or coalesce(current_setting('aurax.bypass_guard', true), '') = '1' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.id = 'A_UR_A_XX' then
      raise exception 'Bu kullanıcı adı ayrılmıştır.';
    end if;
    new.data := (new.data - protected_keys)
      || jsonb_build_object('role','user','verified',false,'special',false,'banned',false,'votes',0);
    return new;
  end if;

  foreach k in array protected_keys loop
    if (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'Bu alan değiştirilemez: %', k;
    end if;
  end loop;
  return new;
end;
$$;

-- 2) Oy verme: oy kaydı eklenince hedef kullanıcının sayacını sunucu artırır.
create or replace function public.aurax_apply_vote()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target text := new.data->>'target';
  v_voter  text := new.data->>'voter';
begin
  if v_target is null or v_voter is null or v_target = v_voter or v_target = 'A_UR_A_XX' then
    raise exception 'Geçersiz oy.';
  end if;
  perform set_config('aurax.bypass_guard', '1', true);
  update public.users
     set data = jsonb_set(data, '{votes}', to_jsonb(coalesce((data->>'votes')::int, 0) + 1))
   where id = v_target;
  perform set_config('aurax.bypass_guard', '', true);
  return new;
end;
$$;

drop trigger if exists votes_apply on public.votes;
create trigger votes_apply after insert on public.votes
  for each row execute function public.aurax_apply_vote();

-- 3) Gönderiler: herkes beğenebilir/yorumlayabilir; geri kalan alanları yalnızca sahibi (ve admin) değiştirir.
drop policy if exists posts_update_owner_or_admin on public.posts;
drop policy if exists posts_update_authenticated on public.posts;
create policy posts_update_authenticated on public.posts
  for update to authenticated using (true) with check (true);

create or replace function public.aurax_posts_guard()
returns trigger
language plpgsql
as $$
declare
  k text;
  v_user text;
begin
  if auth.uid() is null or public.aurax_is_admin() then
    return new;
  end if;
  v_user := public.aurax_current_username();
  if v_user is null then
    raise exception 'Oturum doğrulanamadı.';
  end if;

  if (new.data->>'author') is distinct from (old.data->>'author') then
    raise exception 'Gönderi sahibi değiştirilemez.';
  end if;

  if (old.data->>'author') = v_user then
    -- sahibi: sabitleme yalnızca admin'e ait
    if (new.data->'pinned') is distinct from (old.data->'pinned') then
      raise exception 'Bu alan değiştirilemez: pinned';
    end if;
    return new;
  end if;

  -- başkasının gönderisi: yalnızca likedBy ve comments değişebilir
  for k in select jsonb_object_keys(old.data) union select jsonb_object_keys(new.data) loop
    if k not in ('likedBy','comments') and (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'Bu alan değiştirilemez: %', k;
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists posts_guard on public.posts;
create trigger posts_guard before update on public.posts
  for each row execute function public.aurax_posts_guard();

-- 4) Odaya şifreyle katılma artık aşağıdaki güvenlik bloğundaki hardened RPC ile uygulanır.

-- 5) Bildirimler: gönderen kişi kendi gönderdiği özel mesajı (alıcının kopyası dahil) düzenleyebilsin.
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using ((data->>'to') = public.aurax_current_username() or (data->>'from') = public.aurax_current_username() or public.aurax_is_admin())
  with check ((data->>'to') = public.aurax_current_username() or (data->>'from') = public.aurax_current_username() or public.aurax_is_admin());

drop policy if exists notifications_delete_admin on public.notifications;
create policy notifications_delete_admin on public.notifications
  for delete to authenticated
  using ((data->>'to') = public.aurax_current_username() or (data->>'from') = public.aurax_current_username() or public.aurax_is_admin());


-- Room security guard: ordinary members may update only safe room-interaction fields.
-- Room owner/co-admin/system admin may manage room settings and membership.
create or replace function public.aurax_rooms_guard()
returns trigger
language plpgsql
as $$
declare
  v_user text := public.aurax_current_username();
  v_is_room_admin boolean;
  old_members jsonb := coalesce(old.data->'members', '[]'::jsonb);
  new_members jsonb := coalesce(new.data->'members', '[]'::jsonb);
  old_messages jsonb := coalesce(old.data->'messages', '[]'::jsonb);
  new_messages jsonb := coalesce(new.data->'messages', '[]'::jsonb);
  old_msg jsonb;
  new_msg jsonb;
  old_id text;
  new_id text;
  old_author text;
  k text;
  old_non_self_reactions jsonb;
  new_non_self_reactions jsonb;
begin
  -- SQL editor/service role and explicit trusted RPC updates bypass the guard.
  if auth.uid() is null or coalesce(current_setting('aurax.bypass_room_guard', true), '') = '1' then
    return new;
  end if;

  if v_user is null then
    raise exception 'Oturum doğrulanamadı.';
  end if;

  v_is_room_admin := public.aurax_is_admin()
    or old.data->>'admin' = v_user
    or exists (
      select 1
      from jsonb_array_elements_text(coalesce(old.data->'admins', '[]'::jsonb)) a
      where a = v_user
    );

  -- Oda sahibi / oda yöneticisi / sistem yöneticisi mevcut davranışı koruyarak
  -- oda yönetiminin tamamını yapabilir.
  if v_is_room_admin then
    return new;
  end if;

  -- Normal üyeler oda ayarlarını, yönetici listesini, şifreyi, susturma/kısıtlama
  -- listelerini veya sabit mesajı değiştiremez. Yalnızca aşağıdaki etkileşim alanları
  -- istemci tarafından normal üyeye açıktır.
  foreach k in array array[
    'admin','admins','password','displayName','ownerUid','muted','restrictedMembers',
    'roomAccess','drawingAccess','videoAccess','pinnedMessageId','deleted'
  ] loop
    if (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'Bu alanı değiştirme yetkiniz yok: %', k;
    end if;
  end loop;

  -- Üye yalnızca kendisini odadan çıkarabilir; başka kullanıcı ekleme/çıkarma yok.
  if new_members is distinct from old_members then
    if jsonb_array_length(new_members) > jsonb_array_length(old_members) then
      raise exception 'Odaya kullanıcı ekleme yetkiniz yok.';
    end if;
    if jsonb_array_length(new_members) <> (select count(distinct m) from jsonb_array_elements_text(new_members) m) then
      raise exception 'Oda üyelik listesi geçersiz.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(new_members) n
      where n <> v_user
        and not exists (
          select 1 from jsonb_array_elements_text(old_members) m where m = n
        )
    ) then
      raise exception 'Odaya kullanıcı ekleme yetkiniz yok.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(old_members) m
      where m <> v_user
        and not exists (
          select 1 from jsonb_array_elements_text(new_members) n where n = m
        )
    ) then
      raise exception 'Başka bir kullanıcıyı odadan çıkarma yetkiniz yok.';
    end if;
  end if;

  -- YouTube/çizim senkronu normal üyeler için mevcut uygulama davranışında açıktır;
  -- bu alanlar burada ayrıca engellenmez. Queue değişiminde ise üyenin yalnızca
  -- ekleme yapabilmesi için mevcut kayıtların korunmasını zorunlu tut.
  if (new.data->'youtubeQueue') is distinct from (old.data->'youtubeQueue') then
    old_non_self_reactions := coalesce(old.data->'youtubeQueue', '[]'::jsonb);
    new_non_self_reactions := coalesce(new.data->'youtubeQueue', '[]'::jsonb);
    for old_msg in select value from jsonb_array_elements(old_non_self_reactions) loop
      select value into new_msg
      from jsonb_array_elements(new_non_self_reactions)
      where value->>'id' = old_msg->>'id'
      limit 1;
      if new_msg is null then
        raise exception 'YouTube kuyruğundaki mevcut videoları silemezsiniz.';
      end if;
      if new_msg is distinct from old_msg then
        raise exception 'YouTube kuyruğundaki mevcut videoları değiştiremezsiniz.';
      end if;
    end loop;
  end if;

  -- Mesaj güvenliği:
  -- * Yeni mesaj yalnızca mevcut kullanıcı adına yazılabilir.
  -- * Başkasının mesajı metin/yazar/tarih vb. açıdan değiştirilemez; yalnızca kendi
  --   reaksiyonunu ekleyip kaldırabilir.
  -- * Kendi mesajını düzenleme/silme mevcut arayüz davranışına göre serbesttir.
  if new_messages is distinct from old_messages then
    -- Eski mesajların her biri için aynı id ile gelen yeni kaydı denetle.
    for old_msg in select value from jsonb_array_elements(old_messages) loop
      old_id := old_msg->>'id';
      select value into new_msg
      from jsonb_array_elements(new_messages)
      where value->>'id' = old_id
      limit 1;

      if new_msg is null then
        if old_msg->>'author' <> v_user then
          raise exception 'Başka bir kullanıcının mesajını silemezsiniz.';
        end if;
        continue;
      end if;

      old_author := old_msg->>'author';
      if old_author <> v_user then
        -- Başkasının mesajında reactions dışında hiçbir alan değişemez.
        for k in
          select key from jsonb_each(old_msg)
          union
          select key from jsonb_each(new_msg)
        loop
          if k <> 'reactions' and (old_msg->k) is distinct from (new_msg->k) then
            raise exception 'Başka bir kullanıcının mesajını değiştiremezsiniz.';
          end if;
        end loop;

        -- Reaksiyon değişikliği varsa yalnızca mevcut kullanıcının üyeliği değişebilir.
        old_non_self_reactions := '{}'::jsonb;
        new_non_self_reactions := '{}'::jsonb;
        for k in
          select key from jsonb_each(coalesce(old_msg->'reactions', '{}'::jsonb))
          union
          select key from jsonb_each(coalesce(new_msg->'reactions', '{}'::jsonb))
        loop
          old_non_self_reactions := jsonb_set(
            old_non_self_reactions,
            array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(old_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )),
            true
          );
          new_non_self_reactions := jsonb_set(
            new_non_self_reactions,
            array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(new_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )),
            true
          );
        end loop;
        if old_non_self_reactions is distinct from new_non_self_reactions then
          raise exception 'Başka kullanıcıların reaksiyonlarını değiştiremezsiniz.';
        end if;
      else
        -- Kendi mevcut mesajında yalnızca mesaj içeriği/medyası/düzenlendi bilgisi/
        -- yanıt ve reaksiyonlar değişsin; author/id korunur.
        for k in
          select key from jsonb_each(old_msg)
          union
          select key from jsonb_each(new_msg)
        loop
          if k not in ('id','author','text','img','edited','replyTo','timestamp','reactions','recipients')
             and (old_msg->k) is distinct from (new_msg->k) then
            raise exception 'Mesajın bu alanını değiştiremezsiniz.';
          end if;
        end loop;

        old_non_self_reactions := '{}'::jsonb;
        new_non_self_reactions := '{}'::jsonb;
        for k in
          select key from jsonb_each(coalesce(old_msg->'reactions', '{}'::jsonb))
          union
          select key from jsonb_each(coalesce(new_msg->'reactions', '{}'::jsonb))
        loop
          old_non_self_reactions := jsonb_set(
            old_non_self_reactions, array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(old_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )), true
          );
          new_non_self_reactions := jsonb_set(
            new_non_self_reactions, array[k],
            to_jsonb(array(
              select u from jsonb_array_elements_text(coalesce(new_msg->'reactions'->k, '[]'::jsonb)) u
              where u <> v_user
            )), true
          );
        end loop;
        if old_non_self_reactions is distinct from new_non_self_reactions then
          raise exception 'Başka kullanıcıların reaksiyonlarını değiştiremezsiniz.';
        end if;
      end if;
    end loop;

    -- Yeni eklenen mesajların yazarı mutlaka mevcut kullanıcı olmalı.
    for new_msg in select value from jsonb_array_elements(new_messages) loop
      new_id := new_msg->>'id';
      if not exists (
        select 1 from jsonb_array_elements(old_messages) o where o->>'id' = new_id
      ) then
        if coalesce(new_msg->>'author','') <> v_user then
          raise exception 'Başka bir kullanıcı adına mesaj gönderemezsiniz.';
        end if;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists rooms_guard on public.rooms;
create trigger rooms_guard
before update on public.rooms
for each row execute function public.aurax_rooms_guard();

-- Oda yöneticilerini RLS tarafında da gerçek yönetici olarak tanı.
drop policy if exists rooms_update_owner_or_admin on public.rooms;
create policy rooms_update_owner_or_admin on public.rooms
for update to authenticated
using (
  public.aurax_is_admin()
  or (data->>'admin') = public.aurax_current_username()
  or exists (
    select 1
    from jsonb_array_elements_text(coalesce(data->'admins','[]'::jsonb)) m
    where m = public.aurax_current_username()
  )
  or exists (
    select 1
    from jsonb_array_elements_text(coalesce(data->'members','[]'::jsonb)) m
    where m = public.aurax_current_username()
  )
)
with check (true);

-- Şifreyle ilk giriş RPC'si, oda satırına üye olmayan kullanıcı adına kontrollü yazabilir.
create or replace function public.aurax_join_room(p_room text, p_password text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user text := public.aurax_current_username();
  v_data jsonb;
begin
  if v_user is null then
    raise exception 'Oturum doğrulanamadı.';
  end if;

  select data into v_data from public.rooms where id = p_room for update;
  if not found then
    return false;
  end if;

  if coalesce(v_data->>'password', '') <> coalesce(p_password, '') then
    return false;
  end if;

  if not public.aurax_is_admin() then
    if coalesce((v_data->'roomAccess'->>'locked')::boolean, false) or coalesce((v_data->>'locked')::boolean, false) then
      raise exception 'Bu oda şu anda girişe kapalıdır.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(coalesce(v_data->'restrictedMembers', '[]'::jsonb)) m
      where m = v_user
    ) then
      raise exception 'Bu odaya girişiniz yönetici tarafından kısıtlandı.';
    end if;
  end if;

  if not exists (
    select 1 from jsonb_array_elements_text(coalesce(v_data->'members', '[]'::jsonb)) m where m = v_user
  ) then
    perform set_config('aurax.bypass_room_guard', '1', true);
    update public.rooms
       set data = jsonb_set(data, '{members}', coalesce(data->'members', '[]'::jsonb) || to_jsonb(v_user))
     where id = p_room;
    perform set_config('aurax.bypass_room_guard', '', true);
  end if;
  return true;
end;
$$;
grant execute on function public.aurax_join_room(text, text) to authenticated;




-- ===== supabase_critical_security_patch.sql =====
-- Aura X / Supabase CRITICAL SECURITY HARDENING
-- Uygulama sırası:
--   1) supabase_schema.sql
--   2) supabase_security_patch.sql
--   3) supabase_fix_patch.sql
--   4) BU DOSYA
--
-- Amaç: istemci tarafı kontrollerine güvenmek yerine veritabanında gerçek yetki sınırları,
-- hassas kullanıcı alanlarının gizliliği, sistem yöneticisinin oda kilidi, sahte admin
-- bildirimlerinin önlenmesi ve değişiklik/audit kayıtlarının tutulması.
--
-- NOT: Bu dosya geçmişte oluşmuş Supabase Auth / Dashboard / SQL log kayıtlarını geriye dönük
-- üretemez. Aşağıdaki audit_logs yalnızca BU YAMADAN SONRA oluşan uygulama-verisi değişikliklerini
-- kaydeder. Supabase Auth Audit Logs, Platform Audit Logs ve pgAudit ayrı log kaynaklarıdır.

create extension if not exists pgcrypto;

-- ============================================================
-- 1) GÜVENLİ KİMLİK ÇÖZÜMLEME FONKSİYONLARI
-- ============================================================
create or replace function public.aurax_current_username()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.id
  from public.users u
  where u.data->>'authUid' = auth.uid()::text
  order by u.updated_at desc
  limit 1;
$$;

create or replace function public.aurax_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users u
    where u.id = 'A_UR_A_XX'
      and u.data->>'authUid' = auth.uid()::text
      and coalesce(u.data->>'role', 'user') = 'admin'
  );
$$;

revoke execute on function public.aurax_current_username() from public, anon;
revoke execute on function public.aurax_is_admin() from public, anon;
grant execute on function public.aurax_current_username() to authenticated;
grant execute on function public.aurax_is_admin() to authenticated;

-- ============================================================
-- 2) USERS: HASSAS ALANLAR SADECE SAHİBİ/ADMIN VE ÖZEL RPC ÜZERİNDEN
-- ============================================================
create or replace function public.aurax_users_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  protected_keys text[] := array[
    'role','verified','special','banned','bannedBy','bannedAt','isLider',
    'authUid','authEmail','googleUid','googleEmail','appleUid','appleEmail','authProvider',
    'ipHash','deviceHash','lastIpHash','lastDeviceHash','createdAt',
    'restricted','restrictionCodeHash'
  ];
  k text;
  v_uid text := auth.uid()::text;
  v_username text := public.aurax_current_username();
  v_vote_count integer;
begin
  -- SQL Editor / service-role gibi güvenilir yönetim işlemleri.
  if auth.uid() is null or public.aurax_is_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.id = 'A_UR_A_XX' then
      raise exception 'Bu kullanıcı adı ayrılmıştır.';
    end if;
    if coalesce(new.data->>'authUid','') <> coalesce(v_uid,'') then
      raise exception 'Kullanıcı kaydı mevcut Auth hesabıyla eşleşmiyor.';
    end if;
    if auth.email() is not null and coalesce(new.data->>'authEmail','') <> auth.email() then
      raise exception 'Kullanıcı e-postası Auth hesabıyla eşleşmiyor.';
    end if;
    new.data := new.data
      || pg_catalog.jsonb_build_object('authUid', auth.uid()::text, 'role','user', 'verified',false, 'special',false, 'banned',false, 'isLider',false, 'votes',0);
    return new;
  end if;

  if v_username is null then
    raise exception 'Oturum doğrulanamadı.';
  end if;
  if new.id is distinct from old.id then
    raise exception 'Kullanıcı kimliği değiştirilemez.';
  end if;

  foreach k in array protected_keys loop
    if (new.data -> k) is distinct from (old.data -> k) then
      -- Bu üç alan yalnızca aurax_record_login_seen() içindeki transaction-local
      -- izin bayrağıyla güncellenebilir. İstemci SET komutu çalıştırsa dahi
      -- RPC olmadan tablo UPDATE yetkisi RLS tarafından verilmediğinden yeterli olmaz.
      if k in ('lastIpHash','lastDeviceHash','lastSeenAt')
         and pg_catalog.current_setting('aurax.login_seen', true) = '1' then
        continue;
      end if;
      -- votes yalnızca gerçekten var olan oyların sayısına eşit olabilir.
      if k = 'votes' then
        select count(*)::integer into v_vote_count
        from public.votes v
        where v.data->>'target' = old.id
          and v.data->>'voter' <> old.id;
        if coalesce((new.data->>'votes')::integer, -1) = coalesce(v_vote_count,0) then
          continue;
        end if;
      end if;
      raise exception 'Bu alan değiştirilemez: %', k;
    end if;
  end loop;

  -- Kullanıcı kendi satırında kimlik sahibini değiştiremesin.
  if (new.data->>'authUid') is distinct from (old.data->>'authUid') then
    raise exception 'Auth kimliği değiştirilemez.';
  end if;

  return new;
end;
$$;

drop trigger if exists users_guard on public.users;
create trigger users_guard
before insert or update on public.users
for each row execute function public.aurax_users_guard();

-- Kullanıcılar arası tam JSONB veri sızıntısını kapat.
drop policy if exists users_select_authenticated on public.users;
create policy users_select_self_or_admin on public.users
for select to authenticated
using ((data->>'authUid') = auth.uid()::text or public.aurax_is_admin());

-- Doğrudan users satırına insert/update/delete yetkileri RLS ile ayrıca korunur.
drop policy if exists users_insert_self on public.users;
create policy users_insert_self on public.users
for insert to authenticated
with check ((data->>'authUid') = auth.uid()::text and id <> 'A_UR_A_XX');

drop policy if exists users_update_self_or_admin on public.users;
create policy users_update_self_or_admin on public.users
for update to authenticated
using ((data->>'authUid') = auth.uid()::text or public.aurax_is_admin())
with check ((data->>'authUid') = auth.uid()::text or public.aurax_is_admin());

-- ============================================================
-- 3) PUBLIC PROFILES: UYGULAMANIN KULLANICI ARAMA/AKIŞ İHTİYACINA GÜVENLİ GÖRÜNÜM
-- ============================================================
create table if not exists public.public_profiles (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create or replace function public.aurax_publicize_user(p_data jsonb, p_id text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'username', p_id,
    'firstName', p_data->'firstName',
    'lastName', p_data->'lastName',
    'displayName', p_data->'displayName',
    'bio', p_data->'bio',
    'mood', p_data->'mood',
    'region', p_data->'region',
    'followers', coalesce(p_data->'followers','[]'::jsonb),
    'following', coalesce(p_data->'following','[]'::jsonb),
    'verified', coalesce(p_data->'verified','false'::jsonb),
    'special', coalesce(p_data->'special','false'::jsonb),
    'votes', coalesce(p_data->'votes','0'::jsonb),
    'isLider', coalesce(p_data->'isLider','false'::jsonb),
    'avatarUrl', p_data->'avatarUrl',
    'avatarPath', p_data->'avatarPath',
    'createdAt', p_data->'createdAt'
  );
$$;

create or replace function public.aurax_sync_public_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.public_profiles where id = old.id;
    return old;
  end if;

  insert into public.public_profiles(id,data,updated_at)
  values (new.id, public.aurax_publicize_user(new.data,new.id), now())
  on conflict (id) do update
    set data = excluded.data,
        updated_at = excluded.updated_at;
  return new;
end;
$$;

drop trigger if exists users_public_profile_sync on public.users;
create trigger users_public_profile_sync
after insert or update or delete on public.users
for each row execute function public.aurax_sync_public_profile();

insert into public.public_profiles(id,data)
select u.id, public.aurax_publicize_user(u.data,u.id)
from public.users u
on conflict (id) do update set data = excluded.data, updated_at = now();

alter table public.public_profiles enable row level security;
drop policy if exists public_profiles_select_authenticated on public.public_profiles;
create policy public_profiles_select_authenticated on public.public_profiles
for select to authenticated using (true);
revoke all on public.public_profiles from anon, authenticated;
grant select on public.public_profiles to authenticated;

-- Realtime güvenli public profile kanalı.
do $$
begin
  if not exists (
    select 1
    from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    join pg_class c on c.oid = pr.prrelid
    join pg_namespace n on n.oid = c.relnamespace
    where p.pubname = 'supabase_realtime'
      and n.nspname = 'public'
      and c.relname = 'public_profiles'
  ) then
    execute 'alter publication supabase_realtime add table public.public_profiles';
  end if;
exception when undefined_object then
  null;
end $$;

-- ============================================================
-- 4) AUTH OTURUMU SON GÖRÜLME / AĞ-CİHAZ HASHLERİ İÇİN KONTROLLÜ RPC
-- ============================================================
create or replace function public.aurax_record_login_seen(p_ip_hash text, p_device_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := auth.uid()::text;
  v_ip text := nullif(left(coalesce(p_ip_hash,''),256),'');
  v_device text := nullif(left(coalesce(p_device_hash,''),256),'');
begin
  if v_uid is null then raise exception 'Oturum doğrulanamadı.'; end if;
  perform pg_catalog.set_config('aurax.login_seen','1',true);
  update public.users
     set data = jsonb_set(
       jsonb_set(
         jsonb_set(data,'{lastIpHash}',to_jsonb(v_ip),true),
         '{lastDeviceHash}',to_jsonb(v_device),true
       ),
       '{lastSeenAt}',to_jsonb(extract(epoch from clock_timestamp())*1000),true
     )
   where data->>'authUid' = v_uid;
  return found;
end;
$$;
revoke execute on function public.aurax_record_login_seen(text,text) from public, anon;
grant execute on function public.aurax_record_login_seen(text,text) to authenticated;

create or replace function public.aurax_resolve_oauth_username(p_provider text default 'email')
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.id
  from public.users u
  where u.data->>'authUid' = auth.uid()::text
    and (p_provider is null or p_provider = '' or p_provider = 'email' or lower(coalesce(u.data->>'authProvider','')) = lower(p_provider))
    and (auth.email() is null or u.data->>'authEmail' = auth.email() or u.data->>'googleEmail' = auth.email() or u.data->>'appleEmail' = auth.email())
  limit 1;
$$;
revoke execute on function public.aurax_resolve_oauth_username(text) from public, anon;
grant execute on function public.aurax_resolve_oauth_username(text) to authenticated;

-- ============================================================
-- 5) ROOMS: SADECE ÜYELER / ODA YÖNETİCİLERİ / SİSTEM ADMIN GÖRSÜN
-- ============================================================
drop policy if exists rooms_select_authenticated on public.rooms;
create policy rooms_select_scoped on public.rooms
for select to authenticated
using (
  public.aurax_is_admin()
  or (data->>'admin') = public.aurax_current_username()
  or exists (select 1 from pg_catalog.jsonb_array_elements_text(coalesce(data->'admins','[]'::jsonb)) m where m = public.aurax_current_username())
  or exists (select 1 from pg_catalog.jsonb_array_elements_text(coalesce(data->'members','[]'::jsonb)) m where m = public.aurax_current_username())
);

-- Sistem kilidi alanlarını ODA ADMINİ dahi açamaz.
create or replace function public.aurax_rooms_guard()
returns trigger
language plpgsql
as $$
declare
  v_user text := public.aurax_current_username();
  v_system_admin boolean := public.aurax_is_admin();
  v_is_room_admin boolean;
  old_members jsonb := coalesce(old.data->'members','[]'::jsonb);
  new_members jsonb := coalesce(new.data->'members','[]'::jsonb);
  old_messages jsonb := coalesce(old.data->'messages','[]'::jsonb);
  new_messages jsonb := coalesce(new.data->'messages','[]'::jsonb);
  old_strokes jsonb := coalesce(old.data #> '{drawing,strokes}','[]'::jsonb);
  new_strokes jsonb := coalesce(new.data #> '{drawing,strokes}','[]'::jsonb);
  old_msg jsonb;
  new_msg jsonb;
  old_id text;
  new_id text;
  k text;
  old_non_self_reactions jsonb;
  new_non_self_reactions jsonb;
begin
  if auth.uid() is null or v_system_admin then return new; end if;
  if v_user is null then raise exception 'Oturum doğrulanamadı.'; end if;

  if tg_op = 'INSERT' then
    if coalesce(new.data->>'admin','') <> v_user then
      raise exception 'Oda yöneticisi mevcut kullanıcıyla eşleşmiyor.';
    end if;
    new.data := pg_catalog.jsonb_set(new.data,'{ownerUid}',to_jsonb(auth.uid()::text),true);
    new.data := pg_catalog.jsonb_set(new.data,'{members}',to_jsonb(array[v_user]),true);
    new.data := pg_catalog.jsonb_set(new.data,'{admins}','[]'::jsonb,true);
    new.data := pg_catalog.jsonb_set(new.data,'{systemLocked}','false'::jsonb,true);
    new.data := pg_catalog.jsonb_set(new.data,'{roomAccess,systemLocked}','false'::jsonb,true);
    return new;
  end if;

  -- Sistem yöneticisi alanları yalnızca A_UR_A_XX tarafından değiştirilebilir.
  foreach k in array array['systemLocked','systemLock','auracellLocked','auraCellLocked','auracell','auraCell'] loop
    if (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'Sistem kilidi yalnızca A_UR_A_XX tarafından değiştirilebilir.';
    end if;
  end loop;
  if (new.data #> '{roomAccess,systemLocked}') is distinct from (old.data #> '{roomAccess,systemLocked}') then
    raise exception 'Sistem kilidi yalnızca A_UR_A_XX tarafından değiştirilebilir.';
  end if;

  v_is_room_admin := old.data->>'admin' = v_user
    or exists (select 1 from pg_catalog.jsonb_array_elements_text(coalesce(old.data->'admins','[]'::jsonb)) a where a = v_user);
  if v_is_room_admin then return new; end if;

  -- Normal üyenin değiştirebileceği alanlar açıkça allow-list ile sınırlandırılır.
  for k in
    select key from pg_catalog.jsonb_each(old.data)
    union
    select key from pg_catalog.jsonb_each(new.data)
  loop
    if k not in ('members','messages','youtubeQueue','youtubeCurrentIndex','youtubeSync','drawing')
       and (new.data -> k) is distinct from (old.data -> k) then
      raise exception 'Bu oda alanını değiştirme yetkiniz yok: %', k;
    end if;
  end loop;

  -- Üye kendi hesabını odaya ekleyebilir (yalnızca güvenli join RPC'si RLS'i bypass ederek kullanır),
  -- fakat başka üyeleri ekleyip çıkaramaz.
  if new_members is distinct from old_members then
    if jsonb_array_length(new_members) < jsonb_array_length(old_members) then
      if exists (
        select 1 from pg_catalog.jsonb_array_elements_text(old_members) m
        where m <> v_user and not exists (select 1 from pg_catalog.jsonb_array_elements_text(new_members) n where n = m)
      ) then raise exception 'Başka bir kullanıcıyı odadan çıkarma yetkiniz yok.'; end if;
    else
      if not (
        jsonb_array_length(new_members) = jsonb_array_length(old_members) + 1
        and exists (select 1 from pg_catalog.jsonb_array_elements_text(new_members) n where n = v_user and not exists (select 1 from pg_catalog.jsonb_array_elements_text(old_members) m where m=n))
      ) then
        raise exception 'Odaya kullanıcı ekleme yetkiniz yok.';
      end if;
    end if;
    if jsonb_array_length(new_members) <> (select count(distinct m) from pg_catalog.jsonb_array_elements_text(new_members) m) then
      raise exception 'Oda üyelik listesi geçersiz.';
    end if;
  end if;

  -- YouTube kuyruğundaki mevcut kayıtlar korunmalı; yeni kayıtların sahibi mevcut kullanıcı olmalı.
  if new.data->'youtubeQueue' is distinct from old.data->'youtubeQueue' then
    old_non_self_reactions := coalesce(old.data->'youtubeQueue','[]'::jsonb);
    new_non_self_reactions := coalesce(new.data->'youtubeQueue','[]'::jsonb);
    for old_msg in select value from pg_catalog.jsonb_array_elements(old_non_self_reactions) loop
      select value into new_msg from pg_catalog.jsonb_array_elements(new_non_self_reactions) where value->>'id'=old_msg->>'id' limit 1;
      if new_msg is null or new_msg is distinct from old_msg then
        raise exception 'YouTube kuyruğundaki mevcut videoları silemez veya değiştiremezsiniz.';
      end if;
    end loop;
    for new_msg in select value from pg_catalog.jsonb_array_elements(new_non_self_reactions) loop
      if not exists (select 1 from pg_catalog.jsonb_array_elements(old_non_self_reactions) o where o->>'id'=new_msg->>'id') then
        if coalesce(new_msg->>'addedBy','') <> v_user then raise exception 'Yeni YouTube kaydı sizin hesabınızla eşleşmiyor.'; end if;
      end if;
    end loop;
  end if;

  -- Çizim tahtasında normal üye yalnızca yeni kendi çizgisini ekleyebilir; mevcut çizgileri silemez/değiştiremez.
  if new_strokes is distinct from old_strokes then
    for old_msg in select value from pg_catalog.jsonb_array_elements(old_strokes) loop
      if not exists (select 1 from pg_catalog.jsonb_array_elements(new_strokes) s where s = old_msg) then
        raise exception 'Başka bir çizimi silemezsiniz.';
      end if;
    end loop;
    for new_msg in select value from pg_catalog.jsonb_array_elements(new_strokes) loop
      if not exists (select 1 from pg_catalog.jsonb_array_elements(old_strokes) s where s = new_msg) then
        if coalesce(new_msg->>'author','') <> v_user then raise exception 'Çizim sahibi doğrulanamadı.'; end if;
      end if;
    end loop;
  end if;

  -- Mesaj koruması: yeni mesaj yalnızca kendi adına; başkasının mesajı yalnızca kendi reaksiyonları üzerinden.
  if new_messages is distinct from old_messages then
    for old_msg in select value from pg_catalog.jsonb_array_elements(old_messages) loop
      old_id := old_msg->>'id';
      select value into new_msg from pg_catalog.jsonb_array_elements(new_messages) where value->>'id'=old_id limit 1;
      if new_msg is null then
        if old_msg->>'author' <> v_user then raise exception 'Başka bir kullanıcının mesajını silemezsiniz.'; end if;
        continue;
      end if;
      if new_msg->>'author' is distinct from old_msg->>'author' then raise exception 'Mesaj sahibi değiştirilemez.'; end if;
      if old_msg->>'author' <> v_user then
        for k in select key from pg_catalog.jsonb_each(old_msg) union select key from pg_catalog.jsonb_each(new_msg) loop
          if k not in ('reactions') and (old_msg->k) is distinct from (new_msg->k) then raise exception 'Başkasının mesajını değiştiremezsiniz.'; end if;
        end loop;
        old_non_self_reactions := '{}'::jsonb;
        new_non_self_reactions := '{}'::jsonb;
        for k in select key from pg_catalog.jsonb_each(coalesce(old_msg->'reactions','{}'::jsonb)) union select key from pg_catalog.jsonb_each(coalesce(new_msg->'reactions','{}'::jsonb)) loop
          old_non_self_reactions := pg_catalog.jsonb_set(old_non_self_reactions, array[k], to_jsonb(array(select u from pg_catalog.jsonb_array_elements_text(coalesce(old_msg->'reactions'->k,'[]'::jsonb)) u where u <> v_user)), true);
          new_non_self_reactions := pg_catalog.jsonb_set(new_non_self_reactions, array[k], to_jsonb(array(select u from pg_catalog.jsonb_array_elements_text(coalesce(new_msg->'reactions'->k,'[]'::jsonb)) u where u <> v_user)), true);
        end loop;
        if old_non_self_reactions is distinct from new_non_self_reactions then raise exception 'Başka kullanıcıların reaksiyonlarını değiştiremezsiniz.'; end if;
      else
        for k in select key from pg_catalog.jsonb_each(old_msg) union select key from pg_catalog.jsonb_each(new_msg) loop
          if k not in ('id','author','text','img','edited','replyTo','timestamp','reactions','recipients') and (old_msg->k) is distinct from (new_msg->k) then raise exception 'Mesajın bu alanını değiştiremezsiniz.'; end if;
        end loop;
      end if;
    end loop;
    for new_msg in select value from pg_catalog.jsonb_array_elements(new_messages) loop
      new_id := new_msg->>'id';
      if not exists (select 1 from pg_catalog.jsonb_array_elements(old_messages) o where o->>'id'=new_id) and coalesce(new_msg->>'author','') <> v_user then
        raise exception 'Başka bir kullanıcı adına mesaj gönderemezsiniz.';
      end if;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists rooms_guard on public.rooms;
create trigger rooms_guard before insert or update on public.rooms for each row execute function public.aurax_rooms_guard();

-- Odaya ilk giriş: ŞİFRE veritabanına istemciye açılmadan RPC içinde kontrol edilir.
create or replace function public.aurax_join_room(p_room text, p_password text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user text := public.aurax_current_username();
  v_data jsonb;
  v_system_locked boolean;
begin
  if v_user is null then raise exception 'Oturum doğrulanamadı.'; end if;
  if length(coalesce(p_room,'')) < 1 or length(coalesce(p_room,'')) > 120 then return false; end if;
  if length(coalesce(p_password,'')) > 256 then return false; end if;

  select data into v_data from public.rooms where id = p_room for update;
  if not found then
    select data into v_data from public.rooms where data->>'displayName'=p_room limit 1 for update;
  end if;
  if not found then return false; end if;

  v_system_locked := coalesce((v_data->>'systemLocked')::boolean,false)
    or coalesce((v_data->'systemLock'->>'locked')::boolean,false)
    or coalesce((v_data->>'auracellLocked')::boolean,false)
    or coalesce((v_data->>'auraCellLocked')::boolean,false)
    or coalesce((v_data->'auracell'->>'locked')::boolean,false)
    or coalesce((v_data->'auraCell'->>'locked')::boolean,false)
    or coalesce((v_data->'roomAccess'->>'systemLocked')::boolean,false);

  if v_data ? 'passwordHash' then
    if extensions.crypt(coalesce(p_password,''), v_data->>'passwordHash') <> v_data->>'passwordHash' then
      return false;
    end if;
  elsif coalesce(v_data->>'password','') <> coalesce(p_password,'') then
    return false;
  else
    -- Eski plaintext oda kaydı başarıyla doğrulanırsa aynı transaction'da
    -- hash'lenip plaintext alan kaldırılır.
    update public.rooms
       set data = pg_catalog.jsonb_set(
                    pg_catalog.jsonb_set(data,'{passwordHash}',to_jsonb(extensions.crypt(p_password, extensions.gen_salt('bf',12))),true),
                    '{password}', 'null'::jsonb, true
                  ) - 'password'
     where id = coalesce((select id from public.rooms where id=p_room limit 1),(select id from public.rooms where data->>'displayName'=p_room limit 1));
  end if;

  if not public.aurax_is_admin() then
    if v_system_locked then raise exception 'Bu sistem yönetici tarafından kilitlenmiştir.'; end if;
    if coalesce((v_data->'roomAccess'->>'locked')::boolean,false) or coalesce((v_data->>'locked')::boolean,false) then
      raise exception 'Bu oda şu anda girişe kapalıdır.';
    end if;
    if exists (select 1 from pg_catalog.jsonb_array_elements_text(coalesce(v_data->'restrictedMembers','[]'::jsonb)) m where m=v_user) then
      raise exception 'Bu odaya girişiniz yönetici tarafından kısıtlandı.';
    end if;
  end if;

  if not exists (select 1 from pg_catalog.jsonb_array_elements_text(coalesce(v_data->'members','[]'::jsonb)) m where m=v_user) then
    update public.rooms
       set data = pg_catalog.jsonb_set(data,'{members}',coalesce(data->'members','[]'::jsonb) || to_jsonb(v_user),true)
     where id = coalesce((select id from public.rooms where id=p_room limit 1),(select id from public.rooms where data->>'displayName'=p_room limit 1));
  end if;
  return true;
end;
$$;
revoke execute on function public.aurax_join_room(text,text) from public, anon;
grant execute on function public.aurax_join_room(text,text) to authenticated;

-- Oda daveti / yönetici paneli gibi akışlar için plaintext şifreyi hiç geri döndürmeden doğrulama.
create or replace function public.aurax_verify_room_password(p_room text, p_password text)
returns table(room_id text, display_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user text := public.aurax_current_username();
  v_data jsonb;
  v_id text;
  v_match boolean := false;
begin
  if v_user is null then raise exception 'Oturum doğrulanamadı.'; end if;
  if length(coalesce(p_room,'')) < 1 or length(coalesce(p_room,'')) > 120 or length(coalesce(p_password,'')) > 256 then
    return;
  end if;

  select r.id, r.data into v_id, v_data
  from public.rooms r
  where r.id = p_room or r.data->>'displayName' = p_room
  order by case when r.id = p_room then 0 else 1 end
  limit 1;
  if v_id is null then return; end if;

  if v_data ? 'passwordHash' then
    v_match := extensions.crypt(coalesce(p_password,''), v_data->>'passwordHash') = v_data->>'passwordHash';
  else
    v_match := coalesce(v_data->>'password','') = coalesce(p_password,'');
  end if;
  if not v_match then return; end if;

  if not public.aurax_is_admin() then
    if not (v_data->>'admin' = v_user
      or exists (select 1 from pg_catalog.jsonb_array_elements_text(coalesce(v_data->'admins','[]'::jsonb)) a where a=v_user)
      or exists (select 1 from pg_catalog.jsonb_array_elements_text(coalesce(v_data->'members','[]'::jsonb)) m where m=v_user)) then
      raise exception 'Bu oda için davet yetkiniz yok.';
    end if;
  end if;

  return query select v_id, coalesce(v_data->>'displayName',v_id);
end;
$$;
revoke execute on function public.aurax_verify_room_password(text,text) from public, anon;
grant execute on function public.aurax_verify_room_password(text,text) to authenticated;

-- Mevcut eski odalarda plaintext parolaları bir defaya mahsus bcrypt tabanlı
-- pgcrypto hash'e taşı; bundan sonra trigger plaintext alanı veritabanında tutmaz.
update public.rooms
set data = pg_catalog.jsonb_set(
             pg_catalog.jsonb_set(data,'{passwordHash}',to_jsonb(extensions.crypt(data->>'password', extensions.gen_salt('bf',12))),true),
             '{password}', 'null'::jsonb, true
           ) - 'password'
where coalesce(data->>'password','') <> ''
  and coalesce(data->>'passwordHash','') = '';

-- INSERT/UPDATE ile plaintext password yazılmasını da at-rest seviyesinde engelle.
create or replace function public.aurax_rooms_password_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_password text;
begin
  if not (new.data ? 'password') then return new; end if;
  v_password := new.data->>'password';
  if v_password is null or length(v_password) = 0 or length(v_password) > 256 then
    raise exception 'Oda şifresi geçersiz veya çok uzun.';
  end if;
  new.data := pg_catalog.jsonb_set(
               new.data,
               '{passwordHash}',
               to_jsonb(extensions.crypt(v_password, extensions.gen_salt('bf',12))),
               true
             ) - 'password';
  return new;
end;
$$;

drop trigger if exists rooms_password_guard on public.rooms;
create trigger rooms_password_guard
before insert or update on public.rooms
for each row execute function public.aurax_rooms_password_guard();

-- İsmi ID'ye çözmek için şifreyi geri döndürmeyen güvenli yardımcı.
create or replace function public.aurax_resolve_room_id(p_room text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select r.id from public.rooms r
  where r.id = p_room or r.data->>'displayName'=p_room
  order by case when r.id=p_room then 0 else 1 end
  limit 1;
$$;
revoke execute on function public.aurax_resolve_room_id(text) from public, anon;
grant execute on function public.aurax_resolve_room_id(text) to authenticated;

-- ============================================================
-- 6) A_UR_A_XX: TÜM ODALARI LİSTELE + ODA ADMINİNİ AŞAN SİSTEM KİLİDİ
-- ============================================================
create or replace function public.aurax_admin_list_rooms()
returns table(
  room_id text,
  display_name text,
  owner_username text,
  admins jsonb,
  member_count integer,
  room_locked boolean,
  system_locked boolean,
  deleted boolean,
  created_at text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.aurax_is_admin() then raise exception 'Yetkisiz yönetici işlemi.'; end if;
  return query
    select r.id,
           coalesce(r.data->>'displayName',r.id),
           coalesce(r.data->>'admin',''),
           coalesce(r.data->'admins','[]'::jsonb),
           coalesce(pg_catalog.jsonb_array_length(r.data->'members'),0),
           coalesce((r.data->'roomAccess'->>'locked')::boolean,false) or coalesce((r.data->>'locked')::boolean,false),
           coalesce((r.data->>'systemLocked')::boolean,false)
             or coalesce((r.data->'systemLock'->>'locked')::boolean,false)
             or coalesce((r.data->'roomAccess'->>'systemLocked')::boolean,false)
             or coalesce((r.data->>'auracellLocked')::boolean,false)
             or coalesce((r.data->>'auraCellLocked')::boolean,false),
           coalesce((r.data->>'deleted')::boolean,false),
           r.data->>'createdAt'
    from public.rooms r
    order by r.updated_at desc;
end;
$$;
revoke execute on function public.aurax_admin_list_rooms() from public, anon;
grant execute on function public.aurax_admin_list_rooms() to authenticated;

create or replace function public.aurax_system_lock_room(p_room text, p_locked boolean, p_reason text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user text := public.aurax_current_username();
  v_now text := to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_reason text := left(coalesce(p_reason,''),500);
begin
  if not public.aurax_is_admin() then raise exception 'Yetkisiz sistem yönetimi.'; end if;
  if p_room is null or p_room = '' then raise exception 'Oda belirtilmedi.'; end if;

  update public.rooms
  set data = pg_catalog.jsonb_set(
              pg_catalog.jsonb_set(
                pg_catalog.jsonb_set(data,'{systemLocked}',to_jsonb(coalesce(p_locked,false)),true),
                '{systemLock}',jsonb_build_object('locked',coalesce(p_locked,false),'by',coalesce(v_user,'A_UR_A_XX'),'at',v_now,'reason',v_reason),true
              ),
              '{roomAccess,systemLocked}',to_jsonb(coalesce(p_locked,false)),true
            )
  where id = p_room;
  if not found then raise exception 'Oda bulunamadı.'; end if;
  return true;
end;
$$;
revoke execute on function public.aurax_system_lock_room(text,boolean,text) from public, anon;
grant execute on function public.aurax_system_lock_room(text,boolean,text) to authenticated;

-- ============================================================
-- 7) NOTIFICATIONS: ADMIN TAKLİDİNİ VE KİMLİK DEĞİŞTİRMEYİ KAPAT
-- ============================================================
create or replace function public.aurax_notifications_guard()
returns trigger
language plpgsql
as $$
declare
  v_user text := public.aurax_current_username();
  v_admin boolean := public.aurax_is_admin();
  k text;
begin
  if auth.uid() is null then return new; end if;
  if v_user is null then raise exception 'Oturum doğrulanamadı.'; end if;

  if tg_op = 'INSERT' then
    if not (coalesce(new.data->>'from','')=v_user or v_admin) then raise exception 'Bildirim gönderen kimliği geçersiz.'; end if;
    if coalesce(new.data->>'type','') in ('admin_message','restriction') then
      if not v_admin or coalesce(new.data->>'from','') <> 'A_UR_A_XX' then raise exception 'Yönetici bildirimi yalnızca A_UR_A_XX oluşturabilir.'; end if;
    end if;
    return new;
  end if;

  -- read/mesaj düzenleme dışındaki kimlik/routing alanları normal kullanıcıya kapalı.
  if not v_admin then
    foreach k in array array['to','from','type','roomId','recipientUsername','senderUsername','direction'] loop
      if (new.data->k) is distinct from (old.data->k) then raise exception 'Bildirim kimliği veya yönlendirmesi değiştirilemez: %', k; end if;
    end loop;
  end if;
  if coalesce(new.data->>'type','') in ('admin_message','restriction') and not v_admin then
    raise exception 'Yönetici bildirimi değiştirilemez.';
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_guard on public.notifications;
create trigger notifications_guard before insert or update on public.notifications
for each row execute function public.aurax_notifications_guard();

-- ============================================================
-- 8) VOTES: HAM OYLARI SADECE OY VEREN / SYSTEM ADMIN GÖRSÜN
-- ============================================================
drop policy if exists votes_select_authenticated on public.votes;
create policy votes_select_owner_or_admin on public.votes
for select to authenticated
using ((data->>'voter') = public.aurax_current_username() or public.aurax_is_admin());

create or replace function public.aurax_votes_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user text := public.aurax_current_username();
begin
  if auth.uid() is null or public.aurax_is_admin() then return new; end if;
  if tg_op='INSERT' then
    if coalesce(new.data->>'voter','') <> v_user then raise exception 'Oy veren kimliği geçersiz.'; end if;
    if coalesce(new.data->>'target','') = v_user or coalesce(new.data->>'target','') = 'A_UR_A_XX' then raise exception 'Bu kullanıcıya oy verilemez.'; end if;
    if not exists (select 1 from public.users u where u.id = new.data->>'target') then raise exception 'Oy verilecek kullanıcı bulunamadı.'; end if;
  else
    raise exception 'Oy kaydı değiştirilemez.';
  end if;
  return new;
end;
$$;
drop trigger if exists votes_guard on public.votes;
create trigger votes_guard before insert or update on public.votes
for each row execute function public.aurax_votes_guard();

create or replace function public.aurax_apply_vote()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target text := new.data->>'target';
  v_count integer;
begin
  select count(*)::integer into v_count
  from public.votes v
  where v.data->>'target'=v_target
    and v.data->>'voter' <> v_target;
  update public.users
     set data = pg_catalog.jsonb_set(data,'{votes}',to_jsonb(coalesce(v_count,0)),true)
   where id = v_target;
  return new;
end;
$$;
drop trigger if exists votes_apply on public.votes;
create trigger votes_apply after insert on public.votes for each row execute function public.aurax_apply_vote();

-- ============================================================
-- 9) STORAGE: YÜKLEME YOLUNU KULLANICIYA BAĞLA
-- ============================================================
drop policy if exists aurax_media_insert on storage.objects;
create policy aurax_media_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='media'
  and (
    public.aurax_is_admin()
    or name like ('avatars/' || public.aurax_current_username() || '_%')
    or name like ('postImages/' || public.aurax_current_username() || '_%')
    or name like ('postVideos/' || public.aurax_current_username() || '_%')
    or name like ('statusImages/' || public.aurax_current_username() || '_%')
  )
);

-- ============================================================
-- 10) AUDIT LOG: UYGULAMA VERİSİ MUTASYONLARININ DEĞİŞMEZ KAYDI
-- ============================================================
create table if not exists public.audit_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  action text not null,
  table_name text not null,
  row_id text,
  actor_uid text,
  actor_username text,
  client_ip inet,
  user_agent text,
  request_path text,
  changed_keys text[] not null default '{}',
  old_hash text,
  new_hash text,
  transaction_id bigint,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists audit_logs_created_at_idx on public.audit_logs(created_at desc);
create index if not exists audit_logs_actor_idx on public.audit_logs(actor_uid, created_at desc);
create index if not exists audit_logs_table_row_idx on public.audit_logs(table_name, row_id, created_at desc);

alter table public.audit_logs enable row level security;
drop policy if exists audit_logs_select_admin on public.audit_logs;
create policy audit_logs_select_admin on public.audit_logs
for select to authenticated using (public.aurax_is_admin());
revoke all on public.audit_logs from anon, authenticated;
grant select on public.audit_logs to authenticated;

create or replace function public.aurax_safe_changed_keys(p_old jsonb, p_new jsonb)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(pg_catalog.array_agg(key order by key),'{}'::text[])
  from (
    select key from pg_catalog.jsonb_each(coalesce(p_old,'{}'::jsonb))
    union
    select key from pg_catalog.jsonb_each(coalesce(p_new,'{}'::jsonb))
  ) s
  where (p_old->s.key) is distinct from (p_new->s.key);
$$;

create or replace function public.aurax_request_headers()
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_raw text;
begin
  v_raw := pg_catalog.current_setting('request.headers',true);
  if v_raw is null or v_raw='' then return '{}'::jsonb; end if;
  return v_raw::jsonb;
exception when others then return '{}'::jsonb;
end;
$$;

create or replace function public.aurax_audit_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  h jsonb := public.aurax_request_headers();
  actor text := auth.uid()::text;
  actor_name text := public.aurax_current_username();
  old_data jsonb := case when tg_op in ('UPDATE','DELETE') then old.data else null end;
  new_data jsonb := case when tg_op in ('INSERT','UPDATE') then new.data else null end;
  ip_text text := nullif(split_part(coalesce(h->>'x-forwarded-for',h->>'cf-connecting-ip',''),',',1),'');
  ip_addr inet;
  action_name text;
begin
  begin ip_addr := ip_text::inet; exception when others then ip_addr := null; end;
  action_name := tg_table_name || ':' || lower(tg_op);
  insert into public.audit_logs(
    action, table_name, row_id, actor_uid, actor_username, client_ip, user_agent, request_path,
    changed_keys, old_hash, new_hash, transaction_id, metadata
  ) values (
    action_name,
    tg_table_name,
    coalesce(case when tg_op='DELETE' then old.id else new.id end, old.id),
    actor,
    actor_name,
    ip_addr,
    nullif(left(h->>'user-agent',1000),''),
    nullif(left(h->>'x-path',1000),''),
    public.aurax_safe_changed_keys(old_data,new_data),
    case when old_data is null then null else encode(extensions.digest(old_data::text,'sha256'),'hex') end,
    case when new_data is null then null else encode(extensions.digest(new_data::text,'sha256'),'hex') end,
    txid_current(),
    pg_catalog.jsonb_build_object('source','aurax_db_trigger','operation',tg_op)
  );
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;

-- PII/mesaj/parola içerikleri audit_log'a ham olarak yazılmaz; bunun yerine değişen alan isimleri + SHA-256 fingerprint tutulur.
do $$
declare
  t text;
begin
  foreach t in array array['users','account_links','posts','rooms','room_messages','statuses','notifications','announcements','reports','votes','restrictions','banned_users','banned_ips','banned_devices','banned_emails','push_tokens'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_'||t, t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.aurax_audit_mutation()', 'audit_'||t, t);
  end loop;
end $$;

comment on table public.audit_logs is 'Aura X uygulama veri mutasyonlarının audit kaydı. Ham parola/mesaj/PII saklamaz; değişen alanlar ve SHA-256 fingerprint saklar.';

-- ============================================================
-- 12) HESAP SİLME: PUBLIC VERİLER TEK TRANSACTION'DA TEMİZLENSİN
-- ============================================================
create or replace function public.aurax_delete_current_user_data()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text := auth.uid()::text;
  v_username text := public.aurax_current_username();
  v_ip inet;
  v_user_agent text;
begin
  if v_uid is null or v_username is null then
    raise exception 'Oturum doğrulanamadı.';
  end if;

  begin
    v_ip := nullif(pg_catalog.btrim(coalesce(public.aurax_request_headers()->>'cf-connecting-ip', pg_catalog.split_part(coalesce(public.aurax_request_headers()->>'x-forwarded-for',''), ',', 1), '')), '')::inet;
  exception when others then
    v_ip := null;
  end;
  v_user_agent := public.aurax_request_headers()->>'user-agent';

  -- Bu kayıt, silme işleminden önce bırakılır; ardından tetikleyici tabanlı
  -- ayrıntılı DELETE kayıtları aynı transaction içinde oluşur.
  insert into public.audit_logs(
    action, table_name, row_id, actor_uid, actor_username,
    client_ip, user_agent, request_path, changed_keys, metadata
  ) values (
    'ACCOUNT_DELETE', 'users', v_username, v_uid, v_username,
    v_ip, v_user_agent, '/functions/v1/delete-account', '{}',
    pg_catalog.jsonb_build_object('reason','user_requested_account_deletion')
  );

  delete from public.push_tokens
   where data->>'username' = v_username
      or data->>'authUid' = v_uid;

  delete from public.account_links
   where data->>'username' = v_username
      or data->>'authUid' = v_uid;

  delete from public.notifications
   where data->>'from' = v_username
      or data->>'to' = v_username
      or data->>'username' = v_username;

  -- Kullanıcının kendi şikayetleri silinir; başkalarının bu kullanıcı hakkındaki
  -- şikayetleri korunur (moderasyon/audit bütünlüğü).
  delete from public.reports
   where data->>'reporter' = v_username
      or data->>'reportedBy' = v_username
      or data->>'username' = v_username;

  delete from public.posts
   where data->>'author' = v_username;

  delete from public.statuses
   where id = v_username
      or data->>'author' = v_username
      or data->>'username' = v_username;

  delete from public.votes
   where data->>'voter' = v_username
      or data->>'target' = v_username;

  delete from public.restrictions
   where id = v_username
      or data->>'username' = v_username;

  -- Oda sahipliği/yöneticiliği gibi kayıtlar mevcut ürün akışını bozmamak için
  -- otomatik olarak silinmez. Kullanıcı üyelikleri temizlenir; oda yöneticisi
  -- alanı sistem yöneticisi tarafından ayrıca devralınabilir/kapatılabilir.
  update public.rooms
     set data = pg_catalog.jsonb_set(
                pg_catalog.jsonb_set(
                  data,
                  '{members}',
                  to_jsonb(array(
                    select m from pg_catalog.jsonb_array_elements_text(coalesce(data->'members','[]'::jsonb)) m
                    where m <> v_username
                  )),
                  true
                ),
                '{admins}',
                to_jsonb(array(
                  select a from pg_catalog.jsonb_array_elements_text(coalesce(data->'admins','[]'::jsonb)) a
                  where a <> v_username
                )),
                true
              )
   where exists (select 1 from pg_catalog.jsonb_array_elements_text(coalesce(data->'members','[]'::jsonb)) m where m=v_username)
      or exists (select 1 from pg_catalog.jsonb_array_elements_text(coalesce(data->'admins','[]'::jsonb)) a where a=v_username);

  delete from public.users where id = v_username;
  return true;
end;
$$;
revoke execute on function public.aurax_delete_current_user_data() from public, anon;
grant execute on function public.aurax_delete_current_user_data() to authenticated;

-- ============================================================
-- 13) LOGIN / AUDIT GÜVENLİK NOTU
-- ============================================================
-- LOGIN_ATTEMPT / LOGIN_FAILED / LOGIN_SUCCESS olayları username-login Edge Function
-- tarafından audit_logs'a yazılır. Parola ASLA loglanmaz. audit_logs normal istemcilerden
-- okunamaz/yazılamaz; yalnızca A_UR_A_XX görür.
--
-- Tam SQL ifade denetimi gerekiyorsa Supabase Dashboard'da pgAudit etkinleştirilmeli;
-- bu uygulama tablosu audit_logs ise uygulama-mantıksal değişiklik geçmişini tutar.


-- ============================================================
-- 14) POSTS: BEĞENİ / YORUM / YANIT SAHTECİLİĞİNİ KAPAT
-- ============================================================
create or replace function public.aurax_posts_guard()
returns trigger
language plpgsql
as $$
declare
  v_user text := public.aurax_current_username();
  v_admin boolean := public.aurax_is_admin();
  old_likes jsonb := coalesce(old.data->'likedBy','[]'::jsonb);
  new_likes jsonb := coalesce(new.data->'likedBy','[]'::jsonb);
  old_comments jsonb := coalesce(old.data->'comments','[]'::jsonb);
  new_comments jsonb := coalesce(new.data->'comments','[]'::jsonb);
  old_nonself jsonb;
  new_nonself jsonb;
  old_c jsonb;
  new_c jsonb;
  old_r jsonb;
  new_r jsonb;
  i integer;
  k text;
begin
  if auth.uid() is null or v_admin then return new; end if;
  if v_user is null then raise exception 'Oturum doğrulanamadı.'; end if;
  if pg_catalog.pg_column_size(new.data) > 1000000 then
    raise exception 'Gönderi verisi çok büyük.';
  end if;

  if tg_op = 'INSERT' then
    if coalesce(new.data->>'author','') <> v_user then
      raise exception 'Gönderi sahibi geçersiz.';
    end if;
    if coalesce(new.data->'likedBy','[]'::jsonb) <> '[]'::jsonb then
      raise exception 'Yeni gönderide sahte beğeni oluşturulamaz.';
    end if;
    if coalesce(new.data->'comments','[]'::jsonb) <> '[]'::jsonb then
      raise exception 'Yeni gönderiye başkası adına yorum eklenemez.';
    end if;
    if coalesce((new.data->>'pinned')::boolean,false) then
      raise exception 'Gönderi başlangıçta sabitlenemez.';
    end if;
    return new;
  end if;

  if (new.data->>'author') is distinct from (old.data->>'author') then
    raise exception 'Gönderi sahibi değiştirilemez.';
  end if;

  -- Gönderi sahibi temel içerik alanlarını değiştirebilir; pinned yine yalnızca admin'dir.
  -- Sahibi de olsa likes/comments alt verisini başkaları adına sahteleştiremez.
  if old.data->>'author' = v_user then
    if (new.data->'pinned') is distinct from (old.data->'pinned') then
      raise exception 'Bu alan değiştirilemez: pinned';
    end if;
  else
    -- Başkasının gönderisinde yalnızca kendi beğeni üyeliği ve kendi eklediği yorum/yanıtlar değişebilir.
    for k in select key from pg_catalog.jsonb_each(old.data) union select key from pg_catalog.jsonb_each(new.data) loop
      if k not in ('likedBy','comments') and (new.data->k) is distinct from (old.data->k) then
        raise exception 'Bu alanı değiştirme yetkiniz yok: %', k;
      end if;
    end loop;
  end if;

  if pg_catalog.jsonb_array_length(new_likes) > 10000 then
    raise exception 'Beğeni listesi çok büyük.';
  end if;
  old_nonself := to_jsonb(array(select value from pg_catalog.jsonb_array_elements_text(old_likes) where value <> v_user));
  new_nonself := to_jsonb(array(select value from pg_catalog.jsonb_array_elements_text(new_likes) where value <> v_user));
  if old_nonself is distinct from new_nonself then
    raise exception 'Başka kullanıcıların beğenileri değiştirilemez.';
  end if;
  if (select count(*) from pg_catalog.jsonb_array_elements_text(new_likes) where value=v_user) > 1 then
    raise exception 'Aynı kullanıcı birden fazla beğeni gönderemez.';
  end if;

  if pg_catalog.jsonb_array_length(new_comments) > 5000 then
    raise exception 'Yorum listesi çok büyük.';
  end if;
  if pg_catalog.jsonb_array_length(new_comments) < pg_catalog.jsonb_array_length(old_comments) then
    raise exception 'Mevcut yorumlar silinemez.';
  end if;

  -- Eski yorumların tamamı korunur; yalnızca replies altına yeni kullanıcı cevabı eklenebilir.
  for i in 0..pg_catalog.jsonb_array_length(old_comments)-1 loop
    old_c := old_comments->i;
    new_c := new_comments->i;
    if new_c is null then raise exception 'Mevcut yorum değiştirilemez.'; end if;
    if (new_c - 'replies') is distinct from (old_c - 'replies') then
      raise exception 'Mevcut yorum değiştirilemez.';
    end if;
    old_r := coalesce(old_c->'replies','[]'::jsonb);
    new_r := coalesce(new_c->'replies','[]'::jsonb);
    if pg_catalog.jsonb_array_length(new_r) < pg_catalog.jsonb_array_length(old_r) then
      raise exception 'Mevcut yanıtlar silinemez.';
    end if;
    for k in 0..pg_catalog.jsonb_array_length(old_r)-1 loop
      if new_r->k is distinct from old_r->k then
        raise exception 'Mevcut yanıt değiştirilemez.';
      end if;
    end loop;
    if pg_catalog.jsonb_array_length(new_r) > pg_catalog.jsonb_array_length(old_r) then
      for k in pg_catalog.jsonb_array_length(old_r)..pg_catalog.jsonb_array_length(new_r)-1 loop
        if coalesce(new_r->k->>'author','') <> v_user then
          raise exception 'Yanıt sahibi doğrulanamadı.';
        end if;
        if (new_r->k - array['author','text']) <> '{}'::jsonb then
          raise exception 'Yanıt alanları geçersiz.';
        end if;
        if length(coalesce(new_r->k->>'text','')) > 4000 then
          raise exception 'Yanıt çok uzun.';
        end if;
      end loop;
    end if;
  end loop;

  -- Yeni yorumlar yalnızca mevcut kullanıcı adına ve boş replies listesiyle eklenebilir.
  if pg_catalog.jsonb_array_length(new_comments) > pg_catalog.jsonb_array_length(old_comments) then
    for i in pg_catalog.jsonb_array_length(old_comments)..pg_catalog.jsonb_array_length(new_comments)-1 loop
      new_c := new_comments->i;
      if coalesce(new_c->>'author','') <> v_user then
        raise exception 'Yorum sahibi doğrulanamadı.';
      end if;
      if (new_c - array['author','text','replies']) <> '{}'::jsonb then
        raise exception 'Yorum alanları geçersiz.';
      end if;
      if length(coalesce(new_c->>'text','')) > 4000 then
        raise exception 'Yorum çok uzun.';
      end if;
      if coalesce(new_c->'replies','[]'::jsonb) <> '[]'::jsonb then
        raise exception 'Yeni yorumda başkası adına yanıt oluşturulamaz.';
      end if;
    end loop;
  end if;

  return new;
end;
$$;

drop trigger if exists posts_guard on public.posts;
create trigger posts_guard before insert or update on public.posts for each row execute function public.aurax_posts_guard();



-- ============================================================
-- 15) REKLAM KAMPANYASI: GÜNLÜK GÖSTERİM + SÜRE
-- ============================================================
-- Reklam aralığı (2-5 kullanıcı sonrası) kaldırılmıştır. Her reklam,
-- günlük benzersiz kullanıcı gösterim kotası ve 24 saatlik gün cinsinden
-- aktiflik süresi ile yönetilir. Aynı kullanıcı aynı reklamı aynı gün
-- birden fazla kez kotaya saydıramaz.
create table if not exists public.ad_impressions (
  id uuid primary key default gen_random_uuid(),
  post_id text not null references public.posts(id) on delete cascade,
  viewer_username text not null,
  impression_day date not null,
  created_at timestamptz not null default now()
);

create unique index if not exists ad_impressions_post_viewer_day_uq
  on public.ad_impressions(post_id, viewer_username, impression_day);
create index if not exists ad_impressions_post_day_idx
  on public.ad_impressions(post_id, impression_day);

alter table public.ad_impressions enable row level security;
drop policy if exists ad_impressions_no_client_select on public.ad_impressions;
create policy ad_impressions_no_client_select on public.ad_impressions for select to authenticated using (false);
drop policy if exists ad_impressions_no_client_insert on public.ad_impressions;
create policy ad_impressions_no_client_insert on public.ad_impressions for insert to authenticated with check (false);
drop policy if exists ad_impressions_no_client_update on public.ad_impressions;
create policy ad_impressions_no_client_update on public.ad_impressions for update to authenticated using (false) with check (false);
drop policy if exists ad_impressions_no_client_delete on public.ad_impressions;
create policy ad_impressions_no_client_delete on public.ad_impressions for delete to authenticated using (false);

create or replace function public.aurax_set_post_ad(
  p_post text,
  p_enabled boolean,
  p_daily_impressions integer default 5,
  p_duration_days integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user text := public.aurax_current_username();
  v_data jsonb;
  v_now timestamptz := now();
  v_days integer := greatest(1, least(3, coalesce(p_duration_days, 3)));
  v_daily integer := greatest(1, least(50, coalesce(p_daily_impressions, 5)));
begin
  if not public.aurax_is_admin() or v_user is distinct from 'A_UR_A_XX' then
    raise exception 'Bu reklam kampanyası yalnızca A_UR_A_XX sistem yöneticisi tarafından yönetilebilir.';
  end if;

  select data into v_data from public.posts where id = p_post for update;
  if v_data is null then raise exception 'Gönderi bulunamadı.'; end if;
  if v_data->>'author' is distinct from 'A_UR_A_XX' then
    raise exception 'Sadece A_UR_A_XX gönderileri reklam olabilir.';
  end if;

  if not p_enabled then
    v_data := v_data - array['isAd','adDailyImpressions','adDurationDays','adStartAt','adEndAt'];
    v_data := jsonb_set(v_data, '{isAd}', 'false'::jsonb, true);
  else
    v_data := jsonb_set(v_data, '{isAd}', 'true'::jsonb, true);
    v_data := jsonb_set(v_data, '{adDailyImpressions}', to_jsonb(v_daily), true);
    v_data := jsonb_set(v_data, '{adDurationDays}', to_jsonb(v_days), true);
    v_data := jsonb_set(v_data, '{adStartAt}', to_jsonb(extract(epoch from v_now)*1000), true);
    v_data := jsonb_set(v_data, '{adEndAt}', to_jsonb(extract(epoch from (v_now + make_interval(days => v_days)))*1000), true);
    v_data := jsonb_set(v_data, '{adUpdatedAt}', to_jsonb(extract(epoch from v_now)*1000), true);
    v_data := v_data - 'adInterval';
  end if;

  update public.posts set data = v_data where id = p_post;
  return v_data;
end;
$$;
revoke execute on function public.aurax_set_post_ad(text, boolean, integer, integer) from public, anon;
grant execute on function public.aurax_set_post_ad(text, boolean, integer, integer) to authenticated;

create or replace function public.aurax_record_ad_impression(p_post text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user text := public.aurax_current_username();
  v_data jsonb;
  v_start timestamptz;
  v_end timestamptz;
  v_daily integer;
  v_day date := timezone('Europe/Istanbul', now())::date;
  v_count integer;
begin
  if auth.uid() is null or v_user is null then return false; end if;

  select data into v_data
    from public.posts
   where id = p_post
     and data->>'author' = 'A_UR_A_XX'
     and coalesce((data->>'isAd')::boolean,false) = true
   for update;
  if v_data is null then return false; end if;

  begin v_start := to_timestamp((v_data->>'adStartAt')::double precision / 1000.0); exception when others then v_start := null; end;
  begin v_end := to_timestamp((v_data->>'adEndAt')::double precision / 1000.0); exception when others then v_end := null; end;
  v_daily := greatest(1, least(50, coalesce((v_data->>'adDailyImpressions')::integer, 1)));
  if v_start is null or v_end is null or now() < v_start or now() >= v_end then return false; end if;

  if exists(
    select 1 from public.ad_impressions
     where post_id = p_post and viewer_username = v_user and impression_day = v_day
  ) then
    return false;
  end if;

  select count(*)::integer into v_count
    from public.ad_impressions
   where post_id = p_post and impression_day = v_day;
  if v_count >= v_daily then return false; end if;

  insert into public.ad_impressions(post_id, viewer_username, impression_day)
  values (p_post, v_user, v_day)
  on conflict (post_id, viewer_username, impression_day) do nothing;
  return found;
end;
$$;
revoke execute on function public.aurax_record_ad_impression(text) from public, anon;
grant execute on function public.aurax_record_ad_impression(text) to authenticated;

-- POSTS guard: normal kullanıcılar hiçbir şekilde reklam kampanyası alanlarını
-- ekleyemez/değiştiremez. Kampanya yalnızca yukarıdaki RPC ile yönetilir.
create or replace function public.aurax_posts_guard()
returns trigger
language plpgsql
as $$
declare
  v_user text := public.aurax_current_username();
  v_admin boolean := public.aurax_is_admin();
  old_likes jsonb := coalesce(old.data->'likedBy','[]'::jsonb);
  new_likes jsonb := coalesce(new.data->'likedBy','[]'::jsonb);
  old_comments jsonb := coalesce(old.data->'comments','[]'::jsonb);
  new_comments jsonb := coalesce(new.data->'comments','[]'::jsonb);
  old_nonself jsonb;
  new_nonself jsonb;
  old_c jsonb;
  new_c jsonb;
  old_r jsonb;
  new_r jsonb;
  i integer;
  k text;
begin
  if auth.uid() is null or v_admin then return new; end if;
  if v_user is null then raise exception 'Oturum doğrulanamadı.'; end if;

  if tg_op = 'INSERT' then
    if coalesce(new.data->>'author','') <> v_user then raise exception 'Gönderi sahibi geçersiz.'; end if;
    if coalesce(new.data->'likedBy','[]'::jsonb) <> '[]'::jsonb then raise exception 'Yeni gönderide sahte beğeni oluşturulamaz.'; end if;
    if coalesce(new.data->'comments','[]'::jsonb) <> '[]'::jsonb then raise exception 'Yeni gönderiye başkası adına yorum eklenemez.'; end if;
    if coalesce((new.data->>'pinned')::boolean,false) then raise exception 'Gönderi başlangıçta sabitlenemez.'; end if;
    if coalesce((new.data->>'isAd')::boolean,false) or new.data ? 'adDailyImpressions' or new.data ? 'adDurationDays' or new.data ? 'adStartAt' or new.data ? 'adEndAt' then
      raise exception 'Reklam kampanyası alanlarını yalnızca sistem yöneticisi yönetebilir.';
    end if;
    return new;
  end if;

  if (new.data->>'author') is distinct from (old.data->>'author') then raise exception 'Gönderi sahibi değiştirilemez.'; end if;

  foreach k in array array['isAd','adDailyImpressions','adDurationDays','adStartAt','adEndAt','adUpdatedAt'] loop
    if (new.data->k) is distinct from (old.data->k) then raise exception 'Reklam alanını değiştirme yetkiniz yok: %', k; end if;
  end loop;

  if old.data->>'author' = v_user then
    if (new.data->'pinned') is distinct from (old.data->'pinned') then raise exception 'Bu alan değiştirilemez: pinned'; end if;
  else
    for k in select key from jsonb_each(old.data) union select key from jsonb_each(new.data) loop
      if k not in ('likedBy','comments','isAd','adDailyImpressions','adDurationDays','adStartAt','adEndAt','adUpdatedAt') and (new.data->k) is distinct from (old.data->k) then
        raise exception 'Bu alanı değiştirme yetkiniz yok: %', k;
      end if;
    end loop;
  end if;

  if jsonb_array_length(new_likes) > 10000 then raise exception 'Beğeni listesi çok büyük.'; end if;
  old_nonself := to_jsonb(array(select value from jsonb_array_elements_text(old_likes) where value <> v_user));
  new_nonself := to_jsonb(array(select value from jsonb_array_elements_text(new_likes) where value <> v_user));
  if old_nonself is distinct from new_nonself then raise exception 'Başka kullanıcıların beğenileri değiştirilemez.'; end if;
  if (select count(*) from jsonb_array_elements_text(new_likes) where value=v_user) > 1 then raise exception 'Aynı kullanıcı birden fazla beğeni gönderemez.'; end if;

  if jsonb_array_length(new_comments) > 5000 then raise exception 'Yorum listesi çok büyük.'; end if;
  if jsonb_array_length(new_comments) < jsonb_array_length(old_comments) then raise exception 'Mevcut yorumlar silinemez.'; end if;
  for i in 0..jsonb_array_length(old_comments)-1 loop
    old_c := old_comments->i; new_c := new_comments->i;
    if new_c is null then raise exception 'Mevcut yorum değiştirilemez.'; end if;
    if (new_c - 'replies') is distinct from (old_c - 'replies') then raise exception 'Mevcut yorum değiştirilemez.'; end if;
    old_r := coalesce(old_c->'replies','[]'::jsonb); new_r := coalesce(new_c->'replies','[]'::jsonb);
    if jsonb_array_length(new_r) < jsonb_array_length(old_r) then raise exception 'Mevcut yanıtlar silinemez.'; end if;
    for k in 0..jsonb_array_length(old_r)-1 loop
      if new_r->k is distinct from old_r->k then raise exception 'Mevcut yanıt değiştirilemez.'; end if;
    end loop;
    if jsonb_array_length(new_r) > jsonb_array_length(old_r) then
      for k in jsonb_array_length(old_r)..jsonb_array_length(new_r)-1 loop
        if coalesce(new_r->k->>'author','') <> v_user then raise exception 'Yanıt sahibi doğrulanamadı.'; end if;
        if (new_r->k - array['author','text']) <> '{}'::jsonb then raise exception 'Yanıt alanları geçersiz.'; end if;
        if length(coalesce(new_r->k->>'text','')) > 4000 then raise exception 'Yanıt çok uzun.'; end if;
      end loop;
    end if;
  end loop;

  if jsonb_array_length(new_comments) > jsonb_array_length(old_comments) then
    for i in jsonb_array_length(old_comments)..jsonb_array_length(new_comments)-1 loop
      new_c := new_comments->i;
      if coalesce(new_c->>'author','') <> v_user then raise exception 'Yorum sahibi doğrulanamadı.'; end if;
      if (new_c - array['author','text','replies']) <> '{}'::jsonb then raise exception 'Yorum alanları geçersiz.'; end if;
      if length(coalesce(new_c->>'text','')) > 4000 then raise exception 'Yorum çok uzun.'; end if;
      if coalesce(new_c->'replies','[]'::jsonb) <> '[]'::jsonb then raise exception 'Yeni yorumda başkası adına yanıt oluşturulamaz.'; end if;
    end loop;
  end if;

  return new;
end;
$$;

commit;
