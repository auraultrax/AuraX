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
