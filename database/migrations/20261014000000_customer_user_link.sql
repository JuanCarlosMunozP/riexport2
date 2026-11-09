-- Vinculo entre un cliente y su cuenta de usuario (EP-4). PLAT-529 (enlazar el cliente con su cuenta).
--
-- Un cliente externo entra a la app con su propia cuenta (rol con `portal.read`); este vinculo dice
-- A QUE CLIENTE pertenece esa cuenta. Sin vinculo, `portal.read` no da acceso a nada. Las politicas que
-- usan el vinculo para limitar pedidos, exportaciones y envios al propio cliente estan en
-- database/drafts/client_isolation.sql y se aplicaran cuando existan esas tablas.
--
-- Diseno (mismo patron que los demas modulos):
--  * El vinculo se LEE con RLS: cada usuario ve los suyos y el personal con customers.read ve todos.
--  * Se ESCRIBE solo por funciones SECURITY DEFINER (link_customer_user, unlink_customer_user) que exigen
--    customers.update; el personal indica el CORREO de la cuenta (no necesita ver la lista de usuarios).
--  * Desvincular borra la fila (es revocar un acceso, no historial): queda auditado.
--  * Supuestos a confirmar con el cliente (los mismos del borrador de aislamiento): un usuario puede
--    estar vinculado a varios clientes y un cliente puede tener varios usuarios (N:M); solo el personal
--    vincula, no el propio cliente; solo se vincula a cuentas activas y a clientes activos.

-- 1. Permiso y tabla -----------------------------------------------------------------------------
insert into public.permission (code, description) values
  ('portal.read', 'Consultar los pedidos, exportaciones, documentos y envios propios (cliente externo).')
on conflict (code) do nothing;

create table if not exists public.customer_user (
  customer_id bigint not null references public.customer (id),
  profile_id  bigint not null references public.profile (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (customer_id, profile_id)
);
create index if not exists customer_user_profile_idx on public.customer_user (profile_id);

alter table public.customer_user enable row level security;

drop policy if exists customer_user_select on public.customer_user;
create policy customer_user_select on public.customer_user
  for select to authenticated
  using (
    public.is_active_user()
    and (
      profile_id = (select id from public.profile where auth_user_id = auth.uid())
      or public.has_permission('customers.read')
    )
  );

revoke all on public.customer_user from anon, authenticated;
grant select on public.customer_user to authenticated;

-- 2. Vista legible para el personal -----------------------------------------------------------------
-- Une con la cuenta (correo y nombre). Se ejecuta con los derechos del propietario y filtra por permiso:
-- solo customers.read la ve (los datos de la cuenta son personales).
create or replace view public.customer_account_link
with (security_invoker = false) as
select
  cu.customer_id,
  cu.profile_id,
  cu.created_at,
  p.email,
  p.first_name,
  p.last_name,
  p.is_active as account_is_active,
  (select count(*) > 0
     from public.role_permission rp
    where rp.role_id = p.role_id and rp.permission_code = 'portal.read') as has_portal_access
from public.customer_user cu
join public.profile p on p.id = cu.profile_id
where public.has_permission('customers.read');

revoke all on public.customer_account_link from public, anon, authenticated;
grant select on public.customer_account_link to authenticated;

-- 3. Funciones de escritura ----------------------------------------------------------------------------
create or replace function public.link_customer_user(p_customer_id bigint, p_email text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_profile public.profile;
begin
  if not public.has_permission('customers.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if v_email = '' then
    raise exception 'El correo de la cuenta es obligatorio.' using errcode = '22023';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'El correo de la cuenta no tiene un formato válido.' using errcode = '22023';
  end if;
  perform 1 from public.customer where id = p_customer_id for share;
  if not found then
    raise exception 'No se encontró el cliente solicitado.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.customer where id = p_customer_id and is_active) then
    raise exception 'El cliente está inactivo.' using errcode = '22023';
  end if;
  select * into v_profile from public.profile where lower(email) = v_email;
  if not found then
    raise exception 'No existe una cuenta con ese correo.' using errcode = '22023';
  end if;
  if not v_profile.is_active then
    raise exception 'La cuenta está desactivada.' using errcode = '22023';
  end if;
  begin
    insert into public.customer_user (customer_id, profile_id) values (p_customer_id, v_profile.id);
  exception when unique_violation then
    raise exception 'Esa cuenta ya está vinculada a este cliente.';
  end;
  perform public._customer_audit('customer.user_linked', p_customer_id,
    jsonb_build_object('profile_id', v_profile.id));
end;
$$;

create or replace function public.unlink_customer_user(p_customer_id bigint, p_profile_id bigint)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.has_permission('customers.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  delete from public.customer_user where customer_id = p_customer_id and profile_id = p_profile_id;
  if not found then
    raise exception 'No se encontró el vínculo solicitado.' using errcode = 'P0002';
  end if;
  perform public._customer_audit('customer.user_unlinked', p_customer_id,
    jsonb_build_object('profile_id', p_profile_id));
end;
$$;

revoke all on function public.link_customer_user(bigint, text), public.unlink_customer_user(bigint, bigint) from public, anon;
grant execute on function public.link_customer_user(bigint, text), public.unlink_customer_user(bigint, bigint) to authenticated;
