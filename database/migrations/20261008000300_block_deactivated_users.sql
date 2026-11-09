-- Bloqueo real de los usuarios desactivados.
-- Antes solo has_permission() miraba profile.is_active: una cuenta desactivada con un token
-- valido seguia leyendo catalogos, editando su perfil y usando Storage, y podia iniciar sesion
-- llamando a Supabase Auth directamente (el control estaba solo en el codigo de la app).

-- 1. Cuenta activa con rol activo ---------------------------------------------------------
create or replace function public.is_active_user()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.profile pr
    join public.role r on r.id = pr.role_id
    where pr.auth_user_id = auth.uid() and pr.is_active and r.is_active
  );
$$;

revoke all on function public.is_active_user() from public, anon;
grant execute on function public.is_active_user() to authenticated;

-- 2. Politicas de public: toda lectura o edicion exige cuenta activa ----------------------
drop policy if exists role_select on public.role;
create policy role_select on public.role
  for select to authenticated using (public.is_active_user());

drop policy if exists permission_select on public.permission;
create policy permission_select on public.permission
  for select to authenticated using (public.is_active_user());

drop policy if exists role_permission_select on public.role_permission;
create policy role_permission_select on public.role_permission
  for select to authenticated using (public.is_active_user());

drop policy if exists profile_select on public.profile;
create policy profile_select on public.profile
  for select to authenticated
  using ((auth_user_id = auth.uid() and public.is_active_user())
         or public.has_permission('users.read'));

drop policy if exists profile_update_self on public.profile;
create policy profile_update_self on public.profile
  for update to authenticated
  using (auth_user_id = auth.uid() and public.is_active_user())
  with check (auth_user_id = auth.uid() and public.is_active_user());

-- 3. Storage: igual ------------------------------------------------------------------------
drop policy if exists profile_photos_select on storage.objects;
create policy profile_photos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'profile-photos'
    and (((storage.foldername(name))[1] = auth.uid()::text and public.is_active_user())
         or public.has_permission('users.read'))
  );

drop policy if exists profile_photos_insert on storage.objects;
create policy profile_photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_active_user()
  );

drop policy if exists profile_photos_update on storage.objects;
create policy profile_photos_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_active_user()
  )
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_active_user()
  );

drop policy if exists profile_photos_delete on storage.objects;
create policy profile_photos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.is_active_user()
  );

-- 4. Supabase Auth: desactivar = vetar la cuenta y revocar sus sesiones -----------------------
-- banned_until impide iniciar sesion y renovar tokens aunque se llame a Auth directamente.
-- Un token de acceso ya emitido sigue siendo valido hasta vencer, pero las politicas de arriba
-- ya no le conceden nada.
create or replace function public.sync_auth_access()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.is_active = old.is_active then
    return new;
  end if;
  if new.is_active then
    update auth.users set banned_until = null where id = new.auth_user_id;
  else
    update auth.users set banned_until = now() + interval '876000 hours'
     where id = new.auth_user_id;
    delete from auth.sessions where user_id = new.auth_user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists profile_sync_auth_access on public.profile;
create trigger profile_sync_auth_access
  after update of is_active on public.profile
  for each row execute function public.sync_auth_access();
