-- PLAT-472: politica de cambio de rol (el rol administrador solo lo asigna o quita un administrador).
-- PLAT-473: registro de auditoria append-only y auditoria de los cambios de rol.

-- 1. Auditoria: tabla, permiso y RLS -----------------------------------------------------------
create table if not exists public.audit_log (
  id            bigint generated always as identity primary key,
  actor_user_id bigint references public.profile (id) on delete set null,
  action        text not null check (char_length(action) between 1 and 100),
  entity_type   text not null check (char_length(entity_type) between 1 and 60),
  entity_id     bigint not null,
  request_id    text,
  metadata      jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists audit_log_entity_idx  on public.audit_log (entity_type, entity_id, created_at desc);
create index if not exists audit_log_created_idx on public.audit_log (created_at desc);

insert into public.permission (code, description)
values ('audit.read', 'Consultar el registro de auditoria.')
on conflict (code) do nothing;

insert into public.role_permission (role_id, permission_code)
select r.id, 'audit.read' from public.role r where r.name = 'administrador'
on conflict do nothing;

alter table public.audit_log enable row level security;

drop policy if exists audit_log_select on public.audit_log;
create policy audit_log_select on public.audit_log
  for select to authenticated using (public.has_permission('audit.read'));
-- Sin politicas de INSERT/UPDATE/DELETE: solo escriben los triggers (SECURITY DEFINER).

revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;

-- 2. Inmutabilidad: ni siquiera el propietario edita o borra el registro -------------------------
-- Excepcion: el ON DELETE SET NULL de actor_user_id (borrar una cuenta no debe romperse).
create or replace function public.audit_log_block_changes()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
     and old.actor_user_id is not null and new.actor_user_id is null
     and (to_jsonb(new) - 'actor_user_id') = (to_jsonb(old) - 'actor_user_id') then
    return new;
  end if;
  raise exception 'El registro de auditoria no se puede modificar ni borrar.';
end;
$$;

drop trigger if exists audit_log_immutable on public.audit_log;
create trigger audit_log_immutable
  before update or delete on public.audit_log
  for each row execute function public.audit_log_block_changes();

drop trigger if exists audit_log_no_truncate on public.audit_log;
create trigger audit_log_no_truncate
  before truncate on public.audit_log
  for each statement execute function public.audit_log_block_changes();

-- 3. Auditar los cambios de rol ------------------------------------------------------------------
-- Guarda solo identificadores y nombres de rol (sin datos personales). El actor es null cuando el
-- cambio no viene de una sesion de usuario (por ejemplo, un script SQL).
create or replace function public.audit_profile_role_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.audit_log (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    (select id from public.profile where auth_user_id = auth.uid()),
    'user.role_changed',
    'profile',
    new.id,
    jsonb_build_object(
      'from_role_id', old.role_id,
      'to_role_id', new.role_id,
      'from_role', (select name from public.role where id = old.role_id),
      'to_role', (select name from public.role where id = new.role_id)
    )
  );
  return new;
end;
$$;

drop trigger if exists profile_audit_role_change on public.profile;
create trigger profile_audit_role_change
  after update of role_id on public.profile
  for each row
  when (old.role_id is distinct from new.role_id)
  execute function public.audit_profile_role_change();

-- 4. Politica de cambio de rol: el rol administrador solo lo gestiona un administrador ---------------
-- Sin esta regla, un rol con users.assign_role (p. ej. un supervisor) podria promover a cualquiera
-- a administrador. Va despues de la regla del ultimo administrador activo.
create or replace function public.guard_profile_update()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_admin_role bigint := (select id from public.role where name = 'administrador');
  v_self boolean := coalesce(old.auth_user_id = auth.uid(), false);
begin
  new.updated_at := now();

  -- Con sesion de usuario (auth.uid() no nulo) se exige el permiso de cada campo.
  if auth.uid() is not null then
    if new.role_id <> old.role_id then
      if v_self then
        raise exception 'No puedes cambiar tu propio rol.';
      end if;
      if not public.has_permission('users.assign_role') then
        raise exception 'No tienes permiso para asignar roles.' using errcode = '42501';
      end if;
    end if;

    if new.is_active <> old.is_active
       and not public.has_permission('users.deactivate') then
      raise exception 'No tienes permiso para activar o desactivar usuarios.' using errcode = '42501';
    end if;

    if (new.first_name, new.last_name, new.phone)
         is distinct from (old.first_name, old.last_name, old.phone)
       and not v_self
       and not public.has_permission('users.update') then
      raise exception 'No tienes permiso para editar a otros usuarios.' using errcode = '42501';
    end if;
  end if;

  if new.role_id <> old.role_id
     and not (select is_active from public.role where id = new.role_id) then
    raise exception 'El rol indicado no existe o está inactivo.';
  end if;

  if old.is_active and not new.is_active and v_self then
    raise exception 'No puedes desactivar tu propio usuario.';
  end if;

  if old.is_active and old.role_id = v_admin_role
     and (not new.is_active or new.role_id <> old.role_id)
     and (select count(*) from public.profile
          where role_id = v_admin_role and is_active) <= 1 then
    raise exception 'No se puede dejar el sistema sin un administrador activo.';
  end if;

  if auth.uid() is not null
     and new.role_id <> old.role_id
     and (new.role_id = v_admin_role or old.role_id = v_admin_role)
     and public.current_user_role() is distinct from 'administrador' then
    raise exception 'Solo un administrador puede asignar o quitar el rol administrador.';
  end if;

  return new;
end;
$$;
