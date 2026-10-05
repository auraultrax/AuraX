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
