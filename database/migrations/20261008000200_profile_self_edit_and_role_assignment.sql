-- Autoedicion del perfil, asignacion de roles con permiso propio y endurecimiento de privilegios.
-- Resuelve los hallazgos H1, H2 y H5 de docs/modelo-autorizacion-rls.md.

-- 1. Permiso nuevo: asignar roles a usuarios ------------------------------------------
insert into public.permission (code, description)
values ('users.assign_role', 'Asignar o cambiar el rol de un usuario.')
on conflict (code) do nothing;

insert into public.role_permission (role_id, permission_code)
select r.id, 'users.assign_role' from public.role r where r.name = 'administrador'
on conflict do nothing;

-- 2. Reglas de edicion por campo (la RLS decide la FILA; este trigger decide los CAMPOS) --
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

  return new;
end;
$$;

-- 3. Politicas de UPDATE en profile -----------------------------------------------------
drop policy if exists profile_update on public.profile;

drop policy if exists profile_update_managers on public.profile;
create policy profile_update_managers on public.profile
  for update to authenticated
  using (public.has_permission('users.update')
         or public.has_permission('users.deactivate')
         or public.has_permission('users.assign_role'))
  with check (public.has_permission('users.update')
              or public.has_permission('users.deactivate')
              or public.has_permission('users.assign_role'));

drop policy if exists profile_update_self on public.profile;
create policy profile_update_self on public.profile
  for update to authenticated
  using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- 4. El correo solo cambia por Supabase Auth (trigger), nunca por UPDATE directo ----------
revoke update (email) on public.profile from authenticated;

-- 5. Privilegios sobrantes que Supabase concede por defecto (H1) ------------------------
revoke truncate, references, trigger
  on public.role, public.permission, public.role_permission, public.profile
  from authenticated, anon;
revoke insert, update, delete
  on public.permission, public.role_permission
  from authenticated;
alter default privileges in schema public
  revoke truncate, references, trigger on tables from authenticated, anon;
