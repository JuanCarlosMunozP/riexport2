-- Mantiene los permisos por rol alineados con el principio de minimo privilegio.

create or replace function public.grant_new_permission_to_administrator()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.role_permission (role_id, permission_code)
  select r.id, new.code
  from public.role r
  where r.name = 'administrador'
  on conflict do nothing;
  return new;
end;
$$;

revoke all on function public.grant_new_permission_to_administrator() from public, anon, authenticated;

drop trigger if exists permission_grant_administrator on public.permission;
create trigger permission_grant_administrator
  after insert on public.permission
  for each row execute function public.grant_new_permission_to_administrator();

insert into public.role_permission (role_id, permission_code)
select r.id, p.code
from public.role r
cross join public.permission p
where r.name = 'administrador'
on conflict do nothing;

delete from public.role_permission rp
using public.role r
where r.id = rp.role_id
  and r.name = 'administrador'
  and not exists (
    select 1 from public.permission p where p.code = rp.permission_code
  );

-- El personal comercial gestiona el ciclo de venta; no administra usuarios,
-- roles, inventario ni operaciones logísticas.
delete from public.role_permission rp
using public.role r
where r.id = rp.role_id and r.name = 'usuario_comercial';

insert into public.role_permission (role_id, permission_code)
select r.id, p.code
from public.role r
join (values
  ('customers.read'),
  ('customers.create'),
  ('customers.update'),
  ('orders.read'),
  ('orders.create'),
  ('orders.update'),
  ('orders.transition'),
  ('exports.read'),
  ('exports.create'),
  ('exports.update'),
  ('documents.read'),
  ('documents.upload'),
  ('documents.generate'),
  ('inventory.read'),
  ('payments.read'),
  ('payments.create'),
  ('logistics.read')
) as allowed(code) on true
join public.permission p on p.code = allowed.code
where r.name = 'usuario_comercial'
on conflict do nothing;

-- Logística puede consultar los datos necesarios para preparar y rastrear
-- envíos y ajustar inventario; no puede crear ventas, gestionar pagos ni usuarios.
delete from public.role_permission rp
using public.role r
where r.id = rp.role_id and r.name = 'encargado_logistico';

insert into public.role_permission (role_id, permission_code)
select r.id, p.code
from public.role r
join (values
  ('customers.read'),
  ('orders.read'),
  ('exports.read'),
  ('documents.read'),
  ('inventory.read'),
  ('inventory.adjust'),
  ('logistics.read'),
  ('logistics.create'),
  ('logistics.update')
) as allowed(code) on true
join public.permission p on p.code = allowed.code
where r.name = 'encargado_logistico'
on conflict do nothing;

-- El cliente solo accede a sus datos de portal; las políticas de aislamiento
-- exigen además el vínculo customer_user correspondiente.
delete from public.role_permission rp
using public.role r
where r.id = rp.role_id and r.name = 'cliente';

insert into public.role_permission (role_id, permission_code)
select r.id, p.code
from public.role r
join public.permission p on p.code = 'portal.read'
where r.name = 'cliente'
on conflict do nothing;

create or replace function public.set_role_permissions(p_role_id bigint, p_codes text[])
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_codes text[] := coalesce(p_codes, '{}');
begin
  if not public.has_permission('roles.permissions.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;

  select name into v_name from public.role where id = p_role_id;
  if v_name is null then
    raise exception 'No se encontró el rol solicitado.' using errcode = 'P0002';
  end if;

  if cardinality(v_codes) <> (select count(distinct c) from unnest(v_codes) c) then
    raise exception 'No se permiten permisos duplicados.' using errcode = '22023';
  end if;

  if exists (
    select 1 from unnest(v_codes) c
    where c not in (select code from public.permission)
  ) then
    raise exception 'Uno o más permisos no existen.' using errcode = '22023';
  end if;

  if v_name = 'administrador'
     and (
       cardinality(v_codes) <> (select count(*) from public.permission)
       or exists (
         select 1 from public.permission p
         where not (p.code = any(v_codes))
       )
     ) then
    raise exception 'El rol administrador debe conservar sus permisos de gestión y todos los permisos del sistema.';
  end if;

  delete from public.role_permission where role_id = p_role_id;
  insert into public.role_permission (role_id, permission_code)
  select p_role_id, c from unnest(v_codes) c;
end;
$$;

revoke all on function public.set_role_permissions(bigint, text[]) from public, anon;
grant execute on function public.set_role_permissions(bigint, text[]) to authenticated;
