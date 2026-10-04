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


