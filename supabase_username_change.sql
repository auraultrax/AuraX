-- =====================================================================
-- Aura X: Kullanıcı adı değiştirme (güvenli, tek transaction)
-- Çalıştırmadan önce mutlaka test (staging) projesinde deneyin.
-- Bu dosya supabase_final_security_setup.sql'den SONRA çalıştırılmalıdır.
-- =====================================================================

-- 1) JSON içindeki her tam eşleşen kullanıcı adı referansını yeniden yazar
--    (author, from, to, voter, members, admin, reactions, followers, following vb.).
--    Metin alanlarına (mesaj gövdesi, bio, başlık vb.) dokunmaz.
create or replace function public.aurax_rename_json(j jsonb, old_u text, new_u text)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  result jsonb := '{}'::jsonb;
  arr jsonb;
  k text;
  v jsonb;
  text_keys constant text[] := array[
    'text','body','bio','title','displayName','firstName','lastName','messageBody',
    'caption','description','name','url','img','video','avatarUrl','avatarPath','mediaUrl','bannerUrl'
  ];
begin
  if j is null then
    return null;
  end if;
  case jsonb_typeof(j)
    when 'string' then
      if (j #>> '{}') = old_u then
        return to_jsonb(new_u);
      end if;
      return j;
    when 'array' then
      select coalesce(jsonb_agg(public.aurax_rename_json(e.value, old_u, new_u) order by e.ord), '[]'::jsonb)
        into arr
        from jsonb_array_elements(j) with ordinality as e(value, ord);
      return arr;
    when 'object' then
      for k, v in select key, value from jsonb_each(j) loop
        if k = any(text_keys) then
          result := result || jsonb_build_object(k, v);
        else
          result := result || jsonb_build_object(k, public.aurax_rename_json(v, old_u, new_u));
        end if;
      end loop;
      return result;
    else
      return j;
  end case;
end;
$$;

-- 2) Kullanıcı adını değiştirir. Yalnızca oturumdaki kullanıcı kendi hesabını değiştirebilir.
create or replace function public.aurax_change_username(p_new text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid text := auth.uid()::text;
  v_new text := trim(coalesce(p_new, ''));
  v_old text;
  v_row public.users%rowtype;
  t text;
  tables text[] := array[
    'users','account_links','posts','rooms','room_messages','statuses','notifications',
    'announcements','reports','votes','restrictions','banned_users','banned_ips',
    'banned_devices','banned_emails','push_tokens'
  ];
begin
  if v_uid is null or v_uid = '' then
    raise exception 'Oturum doğrulanamadı.';
  end if;

  if v_new !~ '^[A-Za-z0-9_.]{3,20}$' then
    raise exception 'Kullanıcı adı 3-20 karakter olmalı; yalnızca harf, rakam, _ ve . kullanılabilir.';
  end if;

  select * into v_row
  from public.users
  where data->>'authUid' = v_uid
  limit 1
  for update;

  if not found then
    raise exception 'Aura kullanıcı hesabı bulunamadı.';
  end if;

  v_old := v_row.id;

  if v_old = v_new then
    return v_new;
  end if;

  if lower(v_new) = 'a_ur_a_xx' or lower(v_old) = 'a_ur_a_xx' then
    raise exception 'Bu kullanıcı adı ayrılmıştır.';
  end if;

  -- Büyük/küçük harf duyarsız benzersizlik. Kullanıcının kendi kaydı hariç.
  if exists (select 1 from public.users where lower(id) = lower(v_new) and id <> v_old) then
    raise exception 'Bu kullanıcı adı zaten kullanılıyor.';
  end if;

  -- Tüm tablolardaki kullanıcı tetikleyicileri (koruma kuralları) bu transaction için kapatılır.
  -- Hata olursa transaction geri alınır ve tetikleyiciler eski haline döner.
  foreach t in array tables loop
    execute format('alter table public.%I disable trigger user', t);
  end loop;

  -- Eski Auth e-posta türetmesi girişi bozmasın diye, alan yoksa eski değeri sabitle.
  update public.users
     set data = jsonb_set(data, '{authEmail}', to_jsonb(v_old || '@auth.aurax.local'), true)
   where id = v_old and not (data ? 'authEmail');

  -- JSON içindeki tüm referanslar.
  foreach t in array tables loop
    execute format(
      'update public.%I set data = public.aurax_rename_json(data, $1, $2) where position($1 in data::text) > 0',
      t
    ) using v_old, v_new;
  end loop;

  -- Kimlik (id) alanları: kullanıcı, durumlar, kısıtlamalar, yasaklı kullanıcılar.
  update public.users set id = v_new where id = v_old;
  update public.statuses set id = v_new where id = v_old;
  update public.restrictions set id = v_new where id = v_old;
  update public.banned_users set id = v_new where id = v_old;

  update public.users
     set data = jsonb_set(data, '{username}', to_jsonb(v_new), true),
         updated_at = now()
   where id = v_new;

  -- Herkese açık profil kaydını yeniden eşitle.
  delete from public.public_profiles where id = v_old;
  insert into public.public_profiles (id, data, updated_at)
  select u.id, public.aurax_publicize_user(u.data, u.id), now()
    from public.users u
   where u.id = v_new
  on conflict (id) do update set data = excluded.data, updated_at = excluded.updated_at;

  foreach t in array tables loop
    execute format('alter table public.%I enable trigger user', t);
  end loop;

  begin
    insert into public.audit_logs (action, table_name, row_id, actor_uid, actor_username, metadata)
    values ('USERNAME_CHANGED', 'users', v_old, v_uid, v_new,
            jsonb_build_object('from', v_old, 'to', v_new));
  exception when others then
    null; -- denetim kaydı yazılamazsa değişiklik yine tamamlanır
  end;

  return v_new;
end;
$$;

revoke execute on function public.aurax_change_username(text) from public, anon;
grant execute on function public.aurax_change_username(text) to authenticated;
revoke execute on function public.aurax_rename_json(jsonb, text, text) from public, anon, authenticated;

-- 3) Çıkartmalar kullanıcının kendi users kaydında tutulur; mevcut RLS (users_update_self_or_admin) yeterlidir.
--    Çıkartma dosyaları için storage 'media' bucket'ındaki mevcut insert politikası (authenticated) kullanılır.
