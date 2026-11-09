-- Funcion auxiliar: nombre del rol del usuario actual.
-- Devuelve el rol solo si la cuenta esta activa y su rol tambien; en cualquier otro caso
-- (sin sesion, cuenta desactivada, rol inactivo) devuelve null. Sirve para politicas y
-- consultas que dependan del rol sin repetir el join profile/role.

create or replace function public.current_user_role()
returns text
language sql stable security definer set search_path = public
as $$
  select r.name
  from public.profile pr
  join public.role r on r.id = pr.role_id
  where pr.auth_user_id = auth.uid() and pr.is_active and r.is_active;
$$;

revoke all on function public.current_user_role() from public, anon;
grant execute on function public.current_user_role() to authenticated;
