-- Modulo de proveedores (EP-2): tabla, validaciones, politicas RLS y escritura atomica por funciones.
-- PLAT-510 (registrar un proveedor) y PLAT-511 (tabla de proveedores en la base de datos).
--
-- Diseno (mismo patron que products, ver 20261008000700_products_module.sql):
--  * Se LEE la tabla con RLS (suppliers.read); se ESCRIBE solo por funciones SECURITY DEFINER
--    (create_supplier, update_supplier, set_supplier_active) que comprueban permiso y validan.
--  * Los proveedores no se borran nunca (baja logica con is_active): privilegio revocado y trigger.
--  * Supuestos a confirmar con el cliente: campos del proveedor (razon social, documento tributario,
--    contacto, telefono, correo, ubicacion); documento unico sin distinguir mayusculas; el pais
--    (modelo-datos: supplier -> country) se registra como texto hasta existir el catalogo country.

-- 1. Tabla ---------------------------------------------------------------------------------------
create table if not exists public.supplier (
  id            bigint generated always as identity primary key,
  business_name text not null check (char_length(business_name) between 1 and 160),
  tax_id        text not null check (tax_id ~ '^[A-Za-z0-9][A-Za-z0-9.\-]{2,29}$'),
  contact_name  text check (char_length(contact_name) between 1 and 120),
  phone         text check (phone ~ '^\+?[0-9][0-9 ()\-]{5,24}$'),
  email         text check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 254),
  location      text check (char_length(location) between 1 and 200),
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create unique index if not exists supplier_tax_id_uq on public.supplier (lower(tax_id));
create index if not exists supplier_active_idx on public.supplier (is_active);
create index if not exists supplier_name_trgm_idx
  on public.supplier using gin (business_name extensions.gin_trgm_ops);

-- 2. Reglas de integridad -----------------------------------------------------------------------
create or replace function public.guard_supplier_update()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists supplier_guard on public.supplier;
create trigger supplier_guard
  before update on public.supplier
  for each row execute function public.guard_supplier_update();

-- Los proveedores no se borran (se inactivan), tengan historial o no.
create or replace function public.block_supplier_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Los proveedores no se borran: se inactivan.';
end;
$$;

drop trigger if exists supplier_no_delete on public.supplier;
create trigger supplier_no_delete
  before delete on public.supplier
  for each row execute function public.block_supplier_delete();

-- 3. Permisos y RLS -----------------------------------------------------------------------------
insert into public.permission (code, description) values
  ('suppliers.read', 'Consultar proveedores.'),
  ('suppliers.create', 'Registrar proveedores.'),
  ('suppliers.update', 'Editar e inactivar proveedores.')
on conflict (code) do nothing;

alter table public.supplier enable row level security;

drop policy if exists supplier_select on public.supplier;
create policy supplier_select on public.supplier
  for select to authenticated using (public.has_permission('suppliers.read'));

revoke all on public.supplier from anon, authenticated;
grant select on public.supplier to authenticated;

-- 4. Funciones de escritura ----------------------------------------------------------------------
-- Convencion de errores: 42501 sin permiso; P0002 no encontrado; 22023 dato no valido; P0001 conflicto.

create or replace function public._supplier_audit(p_action text, p_id bigint, p_meta jsonb)
returns void
language sql security definer set search_path = public
as $$
  insert into public.audit_log (actor_user_id, action, entity_type, entity_id, metadata)
  values ((select id from public.profile where auth_user_id = auth.uid()), p_action, 'supplier', p_id, p_meta);
$$;
revoke all on function public._supplier_audit(text, bigint, jsonb) from public, anon, authenticated;

-- Valida un campo de texto opcional del proveedor y devuelve el valor limpio (null si esta vacio).
create or replace function public._supplier_text(p jsonb, p_key text, p_label text, p_max int, p_pattern text default null)
returns text
language plpgsql immutable
as $$
declare
  v text;
begin
  if p -> p_key is null or jsonb_typeof(p -> p_key) = 'null' then
    return null;
  end if;
  if jsonb_typeof(p -> p_key) <> 'string' then
    raise exception '% debe ser texto.', p_label using errcode = '22023';
  end if;
  v := nullif(btrim(p ->> p_key), '');
  if v is null then
    return null;
  end if;
  if char_length(v) > p_max then
    raise exception '% admite máximo % caracteres.', p_label, p_max using errcode = '22023';
  end if;
  if p_pattern is not null and v !~ p_pattern then
    raise exception '% no tiene un formato válido.', p_label using errcode = '22023';
  end if;
  return v;
end;
$$;
revoke all on function public._supplier_text(jsonb, text, text, int, text) from public, anon, authenticated;

create or replace function public.create_supplier(p jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_key text;
  v_name text;
  v_tax text;
  v_contact text;
  v_phone text;
  v_email text;
  v_location text;
  v_id bigint;
begin
  if not public.has_permission('suppliers.create') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'La solicitud no es válida.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if not (v_key = any (array['business_name', 'tax_id', 'contact_name', 'phone', 'email', 'location'])) then
      raise exception 'Campo no permitido para un proveedor: %.', v_key using errcode = '22023';
    end if;
  end loop;

  v_name := public._supplier_text(p, 'business_name', 'La razón social', 160);
  v_tax := public._supplier_text(p, 'tax_id', 'El documento tributario', 30, '^[A-Za-z0-9][A-Za-z0-9.\-]{2,29}$');
  v_contact := public._supplier_text(p, 'contact_name', 'El nombre de contacto', 120);
  v_phone := public._supplier_text(p, 'phone', 'El teléfono', 25, '^\+?[0-9][0-9 ()\-]{5,24}$');
  v_email := lower(public._supplier_text(p, 'email', 'El correo', 254, '^[^@\s]+@[^@\s]+\.[^@\s]+$'));
  v_location := public._supplier_text(p, 'location', 'La ubicación', 200);

  if v_name is null then raise exception 'La razón social es obligatoria.' using errcode = '22023'; end if;
  if v_tax is null then raise exception 'El documento tributario es obligatorio.' using errcode = '22023'; end if;

  begin
    insert into public.supplier (business_name, tax_id, contact_name, phone, email, location)
    values (v_name, v_tax, v_contact, v_phone, v_email, v_location)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ya existe un proveedor con ese documento tributario.';
  end;

  perform public._supplier_audit('supplier.created', v_id, '{}'::jsonb);
  return v_id;
end;
$$;

create or replace function public.update_supplier(p_id bigint, p jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.supplier;
  v_key text;
  v_changed text[] := '{}';
  v_name text;
  v_tax text;
  v_contact text;
  v_phone text;
  v_email text;
  v_location text;
begin
  if not public.has_permission('suppliers.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  select * into v_row from public.supplier where id = p_id for update;
  if not found then
    raise exception 'No se encontró el proveedor solicitado.' using errcode = 'P0002';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' or p = '{}'::jsonb then
    raise exception 'Indica al menos un campo para actualizar.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if not (v_key = any (array['business_name', 'tax_id', 'contact_name', 'phone', 'email', 'location'])) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;

  v_name := v_row.business_name; v_tax := v_row.tax_id; v_contact := v_row.contact_name;
  v_phone := v_row.phone; v_email := v_row.email; v_location := v_row.location;

  if p ? 'business_name' then
    v_name := public._supplier_text(p, 'business_name', 'La razón social', 160);
    if v_name is null then raise exception 'La razón social es obligatoria.' using errcode = '22023'; end if;
  end if;
  if p ? 'tax_id' then
    v_tax := public._supplier_text(p, 'tax_id', 'El documento tributario', 30, '^[A-Za-z0-9][A-Za-z0-9.\-]{2,29}$');
    if v_tax is null then raise exception 'El documento tributario es obligatorio.' using errcode = '22023'; end if;
  end if;
  if p ? 'contact_name' then v_contact := public._supplier_text(p, 'contact_name', 'El nombre de contacto', 120); end if;
  if p ? 'phone' then v_phone := public._supplier_text(p, 'phone', 'El teléfono', 25, '^\+?[0-9][0-9 ()\-]{5,24}$'); end if;
  if p ? 'email' then v_email := lower(public._supplier_text(p, 'email', 'El correo', 254, '^[^@\s]+@[^@\s]+\.[^@\s]+$')); end if;
  if p ? 'location' then v_location := public._supplier_text(p, 'location', 'La ubicación', 200); end if;

  if v_name is distinct from v_row.business_name then v_changed := array_append(v_changed, 'business_name'); end if;
  if v_tax is distinct from v_row.tax_id then v_changed := array_append(v_changed, 'tax_id'); end if;
  if v_contact is distinct from v_row.contact_name then v_changed := array_append(v_changed, 'contact_name'); end if;
  if v_phone is distinct from v_row.phone then v_changed := array_append(v_changed, 'phone'); end if;
  if v_email is distinct from v_row.email then v_changed := array_append(v_changed, 'email'); end if;
  if v_location is distinct from v_row.location then v_changed := array_append(v_changed, 'location'); end if;

  if cardinality(v_changed) = 0 then
    return;
  end if;
  begin
    update public.supplier
       set business_name = v_name, tax_id = v_tax, contact_name = v_contact,
           phone = v_phone, email = v_email, location = v_location
     where id = p_id;
  exception when unique_violation then
    raise exception 'Ya existe un proveedor con ese documento tributario.';
  end;
  perform public._supplier_audit('supplier.updated', p_id, jsonb_build_object('fields', to_jsonb(v_changed)));
end;
$$;

create or replace function public.set_supplier_active(p_id bigint, p_active boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_current boolean;
begin
  if not public.has_permission('suppliers.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if p_active is null then
    raise exception 'Indica si el proveedor debe quedar activo.' using errcode = '22023';
  end if;
  select is_active into v_current from public.supplier where id = p_id for update;
  if not found then
    raise exception 'No se encontró el proveedor solicitado.' using errcode = 'P0002';
  end if;
  if v_current is distinct from p_active then
    update public.supplier set is_active = p_active where id = p_id;
    perform public._supplier_audit(case when p_active then 'supplier.reactivated' else 'supplier.inactivated' end,
      p_id, '{}'::jsonb);
  end if;
end;
$$;

revoke all on function public.create_supplier(jsonb), public.update_supplier(bigint, jsonb),
                       public.set_supplier_active(bigint, boolean) from public, anon;
grant execute on function public.create_supplier(jsonb), public.update_supplier(bigint, jsonb),
                          public.set_supplier_active(bigint, boolean) to authenticated;
