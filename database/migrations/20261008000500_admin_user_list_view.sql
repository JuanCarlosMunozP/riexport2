-- Vista de usuarios para administracion: perfil + nombre del rol, y busqueda rapida.
-- security_invoker = true: la vista se ejecuta con los permisos y la RLS de quien consulta
-- (profile_select y role_select), de modo que NO abre nada que las politicas no abran:
--   * con users.read se ven todos los perfiles; sin el, solo el propio (si la cuenta esta activa);
--   * una cuenta desactivada no ve nada; el anonimo no tiene acceso.

create or replace view public.admin_user_list
with (security_invoker = true) as
select
  p.id,
  p.email,
  p.first_name,
  p.last_name,
  p.phone,
  p.role_id,
  r.name as role_name,
  p.is_active,
  p.created_at,
  p.updated_at
from public.profile p
join public.role r on r.id = p.role_id;

revoke all on public.admin_user_list from public, anon;
grant select on public.admin_user_list to authenticated;

-- Busqueda por nombre, apellido o correo (ilike '%texto%') sin recorrer toda la tabla.
create extension if not exists pg_trgm with schema extensions;

create index if not exists profile_first_name_trgm_idx
  on public.profile using gin (first_name extensions.gin_trgm_ops);
create index if not exists profile_last_name_trgm_idx
  on public.profile using gin (last_name extensions.gin_trgm_ops);
create index if not exists profile_email_trgm_idx
  on public.profile using gin (email extensions.gin_trgm_ops);
