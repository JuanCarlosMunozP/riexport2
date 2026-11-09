-- RiExport: esquema de autenticación, usuarios y roles sobre Supabase.
-- Ejecútalo una vez en Supabase > SQL Editor. Es idempotente en lo posible.
--
-- Modelo: Supabase Auth guarda correo y contraseña (auth.users). Cada cuenta
-- tiene una fila en public.profile con id numérico (lo que usa la app), el rol
-- y el estado. Las reglas de negocio viven aquí, no en el cliente.

-- ---------------------------------------------------------------- tablas ----

create table if not exists public.role (
  id          bigint generated always as identity primary key,
  name        text not null unique check (name ~ '^[a-z][a-z0-9_]{1,59}$'),
  description text check (char_length(description) <= 250),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.permission (
  code        text primary key,
  description text not null
);

create table if not exists public.role_permission (
  role_id         bigint not null references public.role (id) on delete cascade,
  permission_code text   not null references public.permission (code) on delete cascade,
  primary key (role_id, permission_code)
);

create table if not exists public.profile (
  id           bigint generated always as identity primary key,
  auth_user_id uuid not null unique references auth.users (id) on delete cascade,
  email        text not null unique,
  first_name   text not null check (char_length(first_name) between 1 and 100),
  last_name    text not null check (char_length(last_name) between 1 and 100),
  phone        text check (char_length(phone) <= 32),
  role_id      bigint not null references public.role (id),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists profile_role_id_idx on public.profile (role_id);

-- ------------------------------------------------------------ datos base ----

insert into public.permission (code, description) values
  ('roles.read', 'Consultar roles y permisos.'),
  ('roles.create', 'Crear roles.'),
  ('roles.update', 'Editar roles.'),
  ('roles.permissions.update', 'Asignar permisos a roles.'),
  ('roles.deactivate', 'Desactivar roles.'),
  ('users.read', 'Consultar usuarios.'),
  ('users.create', 'Registrar usuarios.'),
  ('users.update', 'Editar usuarios.'),
  ('users.deactivate', 'Desactivar usuarios.')
on conflict (code) do nothing;

insert into public.role (name, description) values
  ('administrador', 'Gestiona usuarios, roles y permisos; accede al tablero de KPI.'),
  ('usuario_comercial', 'Perfil comercial para productos, clientes, pedidos y exportaciones.'),
  ('encargado_logistico', 'Perfil logístico para transportista, guía y eventos de envío.'),
  ('cliente', 'Cliente externo con acceso limitado a sus propios envíos.')
on conflict (name) do nothing;

insert into public.role_permission (role_id, permission_code)
select r.id, p.code from public.role r cross join public.permission p
where r.name = 'administrador'
on conflict do nothing;

-- ------------------------------------------------------------- funciones ----

create or replace function public.has_permission(p_code text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.profile pr
    join public.role r on r.id = pr.role_id
    join public.role_permission rp on rp.role_id = r.id
    where pr.auth_user_id = auth.uid()
      and pr.is_active and r.is_active
      and rp.permission_code = p_code
  );
$$;

-- Registro público: toda cuenta nueva nace con el rol "cliente".
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profile (auth_user_id, email, first_name, last_name, phone, role_id)
  values (
    new.id,
    lower(new.email),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''), 'Usuario'),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'last_name'), ''), '-'),
    nullif(trim(new.raw_user_meta_data ->> 'phone'), ''),
    (select id from public.role where name = 'cliente')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Cuando el titular confirma su nuevo correo en Supabase Auth, se copia al perfil.
create or replace function public.handle_user_email_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  update public.profile set email = lower(new.email) where auth_user_id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row
  when (old.email is distinct from new.email)
  execute function public.handle_user_email_change();

-- Reglas de usuarios: no autodesactivarse, siempre un administrador activo,
-- rol destino activo.
create or replace function public.guard_profile_update()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_admin_role bigint := (select id from public.role where name = 'administrador');
begin
  new.updated_at := now();

  if new.role_id <> old.role_id
     and not (select is_active from public.role where id = new.role_id) then
    raise exception 'El rol indicado no existe o está inactivo.';
  end if;

  if old.is_active and not new.is_active and old.auth_user_id = auth.uid() then
    raise exception 'No puedes desactivar tu propio usuario.';
  end if;

  if old.is_active and old.role_id = v_admin_role
     and (not new.is_active or new.role_id <> old.role_id)
     and (select count(*) from public.profile
          where role_id = v_admin_role and is_active) <= 1 then
    raise exception 'No se puede dejar el sistema sin un administrador activo.';
  end if;

  return new;
end;
$$;

drop trigger if exists profile_guard on public.profile;
create trigger profile_guard
  before update on public.profile
  for each row execute function public.guard_profile_update();

-- Reglas de roles: el administrador es intocable y un rol con usuarios activos
-- no se puede desactivar.
create or replace function public.guard_role_update()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if old.name = 'administrador'
     and (new.name <> old.name or not new.is_active) then
    raise exception 'No se puede modificar ni desactivar el rol administrador del sistema.';
  end if;
  if old.is_active and not new.is_active
     and exists (select 1 from public.profile
                 where role_id = old.id and is_active) then
    raise exception 'El rol tiene usuarios activos asignados.';
  end if;
  return new;
end;
$$;

drop trigger if exists role_guard on public.role;
create trigger role_guard
  before update on public.role
  for each row execute function public.guard_role_update();

-- Reemplaza de forma atómica los permisos de un rol.
create or replace function public.set_role_permissions(p_role_id bigint, p_codes text[])
returns void
language plpgsql security definer set search_path = public
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
  if exists (select 1 from unnest(v_codes) c
             where c not in (select code from public.permission)) then
    raise exception 'Uno o más permisos no existen.' using errcode = '22023';
  end if;
  if v_name = 'administrador'
     and not (v_codes @> array['roles.read', 'roles.create', 'roles.update',
                               'roles.permissions.update']) then
    raise exception 'El rol administrador debe conservar sus permisos de gestión.';
  end if;

  delete from public.role_permission where role_id = p_role_id;
  insert into public.role_permission (role_id, permission_code)
  select p_role_id, c from unnest(v_codes) c;
end;
$$;

revoke all on function public.set_role_permissions(bigint, text[]) from public, anon;
grant execute on function public.set_role_permissions(bigint, text[]) to authenticated;

-- ------------------------------------------------------------------- RLS ----

alter table public.role            enable row level security;
alter table public.permission      enable row level security;
alter table public.role_permission enable row level security;
alter table public.profile         enable row level security;

drop policy if exists role_select on public.role;
create policy role_select on public.role
  for select to authenticated using (true);
drop policy if exists role_insert on public.role;
create policy role_insert on public.role
  for insert to authenticated with check (public.has_permission('roles.create'));
drop policy if exists role_update on public.role;
create policy role_update on public.role
  for update to authenticated
  using (public.has_permission('roles.update') or public.has_permission('roles.deactivate'))
  with check (public.has_permission('roles.update') or public.has_permission('roles.deactivate'));

drop policy if exists permission_select on public.permission;
create policy permission_select on public.permission
  for select to authenticated using (true);

drop policy if exists role_permission_select on public.role_permission;
create policy role_permission_select on public.role_permission
  for select to authenticated using (true);

drop policy if exists profile_select on public.profile;
create policy profile_select on public.profile
  for select to authenticated
  using (auth_user_id = auth.uid() or public.has_permission('users.read'));
drop policy if exists profile_update on public.profile;
create policy profile_update on public.profile
  for update to authenticated
  using (public.has_permission('users.update') or public.has_permission('users.deactivate'))
  with check (public.has_permission('users.update') or public.has_permission('users.deactivate'));

-- Sin acceso anónimo y con columnas editables acotadas.
revoke all on public.role, public.permission, public.role_permission, public.profile
  from anon;
revoke insert, delete on public.profile from authenticated;
revoke update on public.profile from authenticated;
grant update (email, first_name, last_name, phone, role_id, is_active)
  on public.profile to authenticated;
revoke delete on public.role from authenticated;

-- ----------------------------------------- primer administrador (manual) ----
-- 1) Crea tu cuenta (Authentication > Users > Add user, con "Auto Confirm User",
--    o regístrate desde la app).
-- 2) Ejecuta esto con tu correo para promover tu cuenta:
--
--   update public.profile
--   set role_id = (select id from public.role where name = 'administrador')
--   where email = 'tu_correo@dominio.com';
