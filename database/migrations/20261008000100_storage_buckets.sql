-- Almacenamiento de archivos: buckets privados y sus políticas de acceso.
-- Idempotente. Convención de rutas: <auth.uid()>/<archivo> en profile-photos.

-- ---------------------------------------------------------------- buckets ---

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('profile-photos', 'profile-photos', false, 2097152,
   array['image/png', 'image/jpeg', 'image/webp']),
  ('export-documents', 'export-documents', false, 20971520,
   array['application/pdf', 'image/png', 'image/jpeg'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- ------------------------------------------------- políticas: profile-photos ---
-- Cada usuario gestiona solo los archivos de su carpeta (<su auth.uid()>/...);
-- quien tenga users.read puede ver las fotos de los demás.

drop policy if exists profile_photos_select on storage.objects;
create policy profile_photos_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'profile-photos'
    and ((storage.foldername(name))[1] = auth.uid()::text
         or public.has_permission('users.read'))
  );

drop policy if exists profile_photos_insert on storage.objects;
create policy profile_photos_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists profile_photos_update on storage.objects;
create policy profile_photos_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists profile_photos_delete on storage.objects;
create policy profile_photos_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ----------------------------------------------- export-documents (sin acceso) ---
-- El bucket existe pero no tiene políticas: nadie con sesión puede leer ni escribir
-- hasta que el módulo de documentos defina sus permisos (documents.read,
-- documents.upload, ...) y las políticas correspondientes en una migración nueva.
