-- Fincas y lotes con geolocalizacion (EP-2): tablas, validacion de coordenadas, RLS y escritura atomica.
-- PLAT-513 (registrar una finca o lote con geolocalizacion), PLAT-514 (tabla de fincas y lotes) y
-- PLAT-515 (validar las coordenadas en la base de datos).
--
-- Diseno (docs/modelo-datos.md, "Origen"; mismo patron que products y suppliers):
--  * supplier 1-N farm 1-N product_lot N-1 product. La geolocalizacion es de la FINCA (punto
--    latitud/longitud); el lote hereda la de su finca y no guarda coordenadas propias.
--  * Se LEE con RLS (o por vistas con filtro de permiso) y se ESCRIBE solo por funciones SECURITY
--    DEFINER (create_farm, update_farm, set_farm_active, create_lot) que comprueban permiso y validan.
--  * Las coordenadas se validan DOS veces: en las funciones (mensajes claros) y con CHECK en la tabla
--    (nadie las salta escribiendo por otra via): rango, par completo o ausente, y no (0, 0).
--  * Fincas y lotes no se borran nunca: las fincas se inactivan; los lotes quedan para trazabilidad.
--  * Supuestos a confirmar: el pais se guarda como codigo ISO de 2 letras sin catalogo country
--    (todavia no existe); se rechaza el punto (0, 0) por ser casi siempre un valor por defecto;
--    maximo 6 decimales (NUMERIC(9,6), ~0,1 m); sin poligonos EUDR; un lote exige producto y finca
--    activos al crearse y su codigo es unico por finca sin distinguir mayusculas.

-- 1. Tablas ---------------------------------------------------------------------------------------
create table if not exists public.farm (
  id           bigint generated always as identity primary key,
  supplier_id  bigint not null references public.supplier (id),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  name         text not null check (char_length(name) between 1 and 160),
  address      text check (char_length(address) between 1 and 300),
  latitude     numeric(9, 6) check (latitude between -90 and 90),
  longitude    numeric(9, 6) check (longitude between -180 and 180),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- El punto se informa completo o no se informa.
  constraint farm_point_complete check ((latitude is null) = (longitude is null)),
  -- (0, 0) en el golfo de Guinea casi siempre es un valor por defecto, no una finca.
  constraint farm_point_not_origin check (not (latitude = 0 and longitude = 0))
);

-- Una finca no se repite dentro del mismo proveedor (sin distinguir mayusculas).
create unique index if not exists farm_supplier_name_uq on public.farm (supplier_id, lower(name));
create index if not exists farm_supplier_idx on public.farm (supplier_id);
create index if not exists farm_active_idx on public.farm (is_active);

create table if not exists public.product_lot (
  id         bigint generated always as identity primary key,
  product_id bigint not null references public.product (id),
  farm_id    bigint not null references public.farm (id),
  lot_code   text not null check (char_length(lot_code) between 1 and 80),
  created_at timestamptz not null default now()
);

create unique index if not exists product_lot_farm_code_uq on public.product_lot (farm_id, lower(lot_code));
create index if not exists product_lot_farm_product_idx on public.product_lot (farm_id, product_id);
create index if not exists product_lot_product_idx on public.product_lot (product_id);

-- 2. Reglas de integridad -------------------------------------------------------------------------
create or replace function public.guard_farm_update()
returns trigger
language plpgsql
as $$
begin
  if new.supplier_id <> old.supplier_id then
    raise exception 'La finca no se puede pasar a otro proveedor.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists farm_guard on public.farm;
create trigger farm_guard
  before update on public.farm
  for each row execute function public.guard_farm_update();

-- Un lote es inmutable (trazabilidad): ni se edita ni se borra; las fincas tampoco se borran.
create or replace function public.block_origin_change()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Fincas y lotes no se borran: la finca se inactiva y el lote se conserva.';
  end if;
  raise exception 'Un lote no se modifica una vez registrado.';
end;
$$;

drop trigger if exists farm_no_delete on public.farm;
create trigger farm_no_delete
  before delete on public.farm
  for each row execute function public.block_origin_change();
drop trigger if exists product_lot_no_delete on public.product_lot;
create trigger product_lot_no_delete
  before delete on public.product_lot
  for each row execute function public.block_origin_change();
drop trigger if exists product_lot_no_update on public.product_lot;
create trigger product_lot_no_update
  before update on public.product_lot
  for each row execute function public.block_origin_change();

-- 3. Permisos y RLS -------------------------------------------------------------------------------
insert into public.permission (code, description) values
  ('farms.read', 'Consultar fincas y su geolocalizacion.'),
  ('farms.create', 'Registrar fincas.'),
  ('farms.update', 'Editar e inactivar fincas.'),
  ('lots.read', 'Consultar lotes de producto.'),
  ('lots.create', 'Registrar lotes de producto.')
on conflict (code) do nothing;

alter table public.farm enable row level security;
alter table public.product_lot enable row level security;

drop policy if exists farm_select on public.farm;
create policy farm_select on public.farm
  for select to authenticated using (public.has_permission('farms.read'));
drop policy if exists product_lot_select on public.product_lot;
create policy product_lot_select on public.product_lot
  for select to authenticated using (public.has_permission('lots.read'));

revoke all on public.farm, public.product_lot from anon, authenticated;
grant select on public.farm, public.product_lot to authenticated;

-- 4. Funciones de escritura -------------------------------------------------------------------------
-- Convencion de errores: 42501 sin permiso; P0002 no encontrado; 22023 dato no valido; P0001 conflicto.

create or replace function public._origin_audit(p_action text, p_type text, p_id bigint, p_meta jsonb)
returns void
language sql security definer set search_path = public
as $$
  insert into public.audit_log (actor_user_id, action, entity_type, entity_id, metadata)
  values ((select id from public.profile where auth_user_id = auth.uid()), p_action, p_type, p_id, p_meta);
$$;
revoke all on function public._origin_audit(text, text, bigint, jsonb) from public, anon, authenticated;

-- Valida una coordenada (PLAT-515): numero, dentro del rango y con maximo 6 decimales. Devuelve null si falta.
create or replace function public._farm_coordinate(p jsonb, p_key text, p_label text, p_limit numeric)
returns numeric
language plpgsql immutable
as $$
declare
  v numeric;
begin
  if p -> p_key is null or jsonb_typeof(p -> p_key) = 'null' then
    return null;
  end if;
  if jsonb_typeof(p -> p_key) not in ('number', 'string') then
    raise exception '% debe ser un número.', p_label using errcode = '22023';
  end if;
  begin
    v := replace(btrim(p ->> p_key), ',', '.')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception '% debe ser un número válido.', p_label using errcode = '22023';
  end;
  if v < -p_limit or v > p_limit then
    raise exception '% debe estar entre % y %.', p_label, -p_limit, p_limit using errcode = '22023';
  end if;
  if v <> round(v, 6) then
    raise exception '% admite como máximo 6 decimales.', p_label using errcode = '22023';
  end if;
  return v;
end;
$$;
revoke all on function public._farm_coordinate(jsonb, text, text, numeric) from public, anon, authenticated;

-- Texto opcional recortado (mismo comportamiento que _supplier_text, con su propio nombre para no acoplar modulos).
create or replace function public._origin_text(p jsonb, p_key text, p_label text, p_max int)
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
  if v is not null and char_length(v) > p_max then
    raise exception '% admite máximo % caracteres.', p_label, p_max using errcode = '22023';
  end if;
  return v;
end;
$$;
revoke all on function public._origin_text(jsonb, text, text, int) from public, anon, authenticated;

create or replace function public.create_farm(p jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_key text;
  v_supplier bigint;
  v_country text;
  v_name text;
  v_address text;
  v_lat numeric;
  v_lon numeric;
  v_id bigint;
begin
  if not public.has_permission('farms.create') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'La solicitud no es válida.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if not (v_key = any (array['supplier_id', 'country_code', 'name', 'address', 'latitude', 'longitude'])) then
      raise exception 'Campo no permitido para una finca: %.', v_key using errcode = '22023';
    end if;
  end loop;

  if jsonb_typeof(p -> 'supplier_id') is distinct from 'number' or (p ->> 'supplier_id') !~ '^[0-9]+$' then
    raise exception 'El proveedor es obligatorio.' using errcode = '22023';
  end if;
  v_supplier := (p ->> 'supplier_id')::bigint;
  if not exists (select 1 from public.supplier where id = v_supplier) then
    raise exception 'El proveedor no existe.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.supplier where id = v_supplier and is_active) then
    raise exception 'El proveedor está inactivo.' using errcode = '22023';
  end if;

  v_country := upper(public._origin_text(p, 'country_code', 'El país', 2));
  if v_country is null then raise exception 'El país es obligatorio.' using errcode = '22023'; end if;
  if v_country !~ '^[A-Z]{2}$' then
    raise exception 'El país debe ser un código de 2 letras (por ejemplo CO).' using errcode = '22023';
  end if;
  v_name := public._origin_text(p, 'name', 'El nombre de la finca', 160);
  if v_name is null then raise exception 'El nombre de la finca es obligatorio.' using errcode = '22023'; end if;
  v_address := public._origin_text(p, 'address', 'La dirección', 300);

  v_lat := public._farm_coordinate(p, 'latitude', 'La latitud', 90);
  v_lon := public._farm_coordinate(p, 'longitude', 'La longitud', 180);
  if (v_lat is null) <> (v_lon is null) then
    raise exception 'Informa la latitud y la longitud juntas, o ninguna.' using errcode = '22023';
  end if;
  if v_lat = 0 and v_lon = 0 then
    raise exception 'Las coordenadas (0, 0) no son una ubicación válida de finca.' using errcode = '22023';
  end if;

  begin
    insert into public.farm (supplier_id, country_code, name, address, latitude, longitude)
    values (v_supplier, v_country, v_name, v_address, v_lat, v_lon)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'El proveedor ya tiene una finca con ese nombre.';
  end;

  perform public._origin_audit('farm.created', 'farm', v_id,
    jsonb_build_object('supplier_id', v_supplier, 'geolocated', v_lat is not null));
  return v_id;
end;
$$;

create or replace function public.update_farm(p_id bigint, p jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.farm;
  v_key text;
  v_changed text[] := '{}';
  v_country text;
  v_name text;
  v_address text;
  v_lat numeric;
  v_lon numeric;
begin
  if not public.has_permission('farms.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  select * into v_row from public.farm where id = p_id for update;
  if not found then
    raise exception 'No se encontró la finca solicitada.' using errcode = 'P0002';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' or p = '{}'::jsonb then
    raise exception 'Indica al menos un campo para actualizar.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if not (v_key = any (array['supplier_id', 'country_code', 'name', 'address', 'latitude', 'longitude'])) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if p ? 'supplier_id' and (p ->> 'supplier_id') is distinct from v_row.supplier_id::text then
    raise exception 'La finca no se puede pasar a otro proveedor.' using errcode = '22023';
  end if;

  v_country := v_row.country_code; v_name := v_row.name; v_address := v_row.address;
  v_lat := v_row.latitude; v_lon := v_row.longitude;

  if p ? 'country_code' then
    v_country := upper(public._origin_text(p, 'country_code', 'El país', 2));
    if v_country is null then raise exception 'El país es obligatorio.' using errcode = '22023'; end if;
    if v_country !~ '^[A-Z]{2}$' then
      raise exception 'El país debe ser un código de 2 letras (por ejemplo CO).' using errcode = '22023';
    end if;
  end if;
  if p ? 'name' then
    v_name := public._origin_text(p, 'name', 'El nombre de la finca', 160);
    if v_name is null then raise exception 'El nombre de la finca es obligatorio.' using errcode = '22023'; end if;
  end if;
  if p ? 'address' then v_address := public._origin_text(p, 'address', 'La dirección', 300); end if;
  if p ? 'latitude' then v_lat := public._farm_coordinate(p, 'latitude', 'La latitud', 90); end if;
  if p ? 'longitude' then v_lon := public._farm_coordinate(p, 'longitude', 'La longitud', 180); end if;
  if (v_lat is null) <> (v_lon is null) then
    raise exception 'Informa la latitud y la longitud juntas, o ninguna.' using errcode = '22023';
  end if;
  if v_lat = 0 and v_lon = 0 then
    raise exception 'Las coordenadas (0, 0) no son una ubicación válida de finca.' using errcode = '22023';
  end if;

  if v_country is distinct from v_row.country_code then v_changed := array_append(v_changed, 'country_code'); end if;
  if v_name is distinct from v_row.name then v_changed := array_append(v_changed, 'name'); end if;
  if v_address is distinct from v_row.address then v_changed := array_append(v_changed, 'address'); end if;
  if v_lat is distinct from v_row.latitude or v_lon is distinct from v_row.longitude then
    v_changed := array_append(v_changed, 'coordinates');
  end if;
  if cardinality(v_changed) = 0 then
    return;
  end if;

  begin
    update public.farm
       set country_code = v_country, name = v_name, address = v_address, latitude = v_lat, longitude = v_lon
     where id = p_id;
  exception when unique_violation then
    raise exception 'El proveedor ya tiene una finca con ese nombre.';
  end;
  perform public._origin_audit('farm.updated', 'farm', p_id, jsonb_build_object('fields', to_jsonb(v_changed)));
end;
$$;

create or replace function public.set_farm_active(p_id bigint, p_active boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_current boolean;
begin
  if not public.has_permission('farms.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if p_active is null then
    raise exception 'Indica si la finca debe quedar activa.' using errcode = '22023';
  end if;
  select is_active into v_current from public.farm where id = p_id for update;
  if not found then
    raise exception 'No se encontró la finca solicitada.' using errcode = 'P0002';
  end if;
  if v_current is distinct from p_active then
    update public.farm set is_active = p_active where id = p_id;
    perform public._origin_audit(case when p_active then 'farm.reactivated' else 'farm.inactivated' end,
      'farm', p_id, '{}'::jsonb);
  end if;
end;
$$;

create or replace function public.create_lot(p jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_key text;
  v_product bigint;
  v_farm bigint;
  v_code text;
  v_id bigint;
begin
  if not public.has_permission('lots.create') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'La solicitud no es válida.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if not (v_key = any (array['product_id', 'farm_id', 'lot_code'])) then
      raise exception 'Campo no permitido para un lote: %.', v_key using errcode = '22023';
    end if;
  end loop;

  if jsonb_typeof(p -> 'product_id') is distinct from 'number' or (p ->> 'product_id') !~ '^[0-9]+$' then
    raise exception 'El producto es obligatorio.' using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'farm_id') is distinct from 'number' or (p ->> 'farm_id') !~ '^[0-9]+$' then
    raise exception 'La finca es obligatoria.' using errcode = '22023';
  end if;
  v_product := (p ->> 'product_id')::bigint;
  v_farm := (p ->> 'farm_id')::bigint;
  v_code := public._origin_text(p, 'lot_code', 'El código del lote', 80);
  if v_code is null then raise exception 'El código del lote es obligatorio.' using errcode = '22023'; end if;

  if not exists (select 1 from public.product where id = v_product) then
    raise exception 'El producto no existe.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.product where id = v_product and is_active) then
    raise exception 'El producto está inactivo.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.farm where id = v_farm) then
    raise exception 'La finca no existe.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.farm where id = v_farm and is_active) then
    raise exception 'La finca está inactiva.' using errcode = '22023';
  end if;

  begin
    insert into public.product_lot (product_id, farm_id, lot_code) values (v_product, v_farm, v_code)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'La finca ya tiene un lote con ese código.';
  end;
  perform public._origin_audit('lot.created', 'lot', v_id,
    jsonb_build_object('product_id', v_product, 'farm_id', v_farm));
  return v_id;
end;
$$;

revoke all on function public.create_farm(jsonb), public.update_farm(bigint, jsonb),
                       public.set_farm_active(bigint, boolean), public.create_lot(jsonb) from public, anon;
grant execute on function public.create_farm(jsonb), public.update_farm(bigint, jsonb),
                          public.set_farm_active(bigint, boolean), public.create_lot(jsonb) to authenticated;

-- 5. Vistas de consulta -------------------------------------------------------------------------------
-- Se ejecutan con los derechos del propietario (para unir con proveedor y producto sin exigir sus permisos
-- de lectura) pero filtran por el permiso del modulo: sin farms.read / lots.read no devuelven nada.
create or replace view public.farm_catalog
with (security_invoker = false) as
select
  f.id,
  f.supplier_id,
  s.business_name as supplier_name,
  f.country_code,
  f.name,
  f.address,
  f.latitude,
  f.longitude,
  f.is_active,
  f.created_at,
  f.updated_at,
  (select count(*) from public.product_lot l where l.farm_id = f.id) as lot_count
from public.farm f
join public.supplier s on s.id = f.supplier_id
where public.has_permission('farms.read');

create or replace view public.lot_catalog
with (security_invoker = false) as
select
  l.id,
  l.lot_code,
  l.created_at,
  l.product_id,
  p.type as product_type,
  p.variety as product_variety,
  p.quality_grade as product_quality,
  l.farm_id,
  f.name as farm_name,
  f.country_code,
  f.latitude,
  f.longitude,
  f.supplier_id,
  s.business_name as supplier_name
from public.product_lot l
join public.product p on p.id = l.product_id
join public.farm f on f.id = l.farm_id
join public.supplier s on s.id = f.supplier_id
where public.has_permission('lots.read');

revoke all on public.farm_catalog, public.lot_catalog from public, anon, authenticated;
grant select on public.farm_catalog, public.lot_catalog to authenticated;
