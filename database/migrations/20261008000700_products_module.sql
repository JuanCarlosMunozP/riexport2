-- Modulo de productos (EP-2): catalogo de cafe y cacao, certificaciones, validaciones, politicas RLS,
-- escritura atomica por funciones y vista de catalogo. PLAT-491 a PLAT-506.
--
-- Diseno (docs/modelo-datos.md, "Productos y origen"; docs/modelo-autorizacion-rls.md, seccion 14):
--  * Los usuarios LEEN las tablas (RLS) y ESCRIBEN solo mediante funciones SECURITY DEFINER
--    (create_product, update_product, set_product_active, set_product_certifications): cada una
--    comprueba el permiso, valida y es atomica (producto + detalle + certificaciones juntos).
--  * Los productos no se borran nunca (baja logica con is_active): privilegio revocado y trigger.
--  * Supuestos a confirmar con el cliente: producto unico por (tipo, variedad, calidad); la unidad
--    base y el tipo no cambian despues de creado; formato del codigo HS (fuente y version pendientes).

-- 1. Catalogos de referencia ---------------------------------------------------------------------
create table if not exists public.unit_of_measure (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{0,11}$'),
  name text not null unique check (char_length(name) between 1 and 60)
);

insert into public.unit_of_measure (code, name) values
  ('kg', 'Kilogramo'),
  ('t', 'Tonelada métrica')
on conflict (code) do nothing;

create table if not exists public.certification (
  id        bigint generated always as identity primary key,
  code      text not null unique check (code ~ '^[A-Z][A-Z0-9_]{1,49}$'),
  name      text not null check (char_length(name) between 1 and 120),
  is_active boolean not null default true
);

insert into public.certification (code, name) values
  ('ORGANIC', 'Orgánico'),
  ('FAIR_TRADE', 'Fair Trade'),
  ('RAINFOREST_ALLIANCE', 'Rainforest Alliance')
on conflict (code) do nothing;

-- 2. Producto y detalles por tipo -------------------------------------------------------------------
create table if not exists public.product (
  id                  bigint generated always as identity primary key,
  type                text not null check (type in ('coffee', 'cacao')),
  variety             text not null check (char_length(variety) between 1 and 120),
  quality_grade       text not null check (char_length(quality_grade) between 1 and 80),
  hs_code             text check (hs_code ~ '^[0-9]{4}(\.[0-9]{2}){0,3}$'),
  base_unit_code      text not null references public.unit_of_measure (code),
  low_stock_threshold numeric(18, 3) check (low_stock_threshold >= 0),
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Evita duplicados: mismo tipo, variedad y calidad (sin distinguir mayusculas).
create unique index if not exists product_identity_uq
  on public.product (type, lower(variety), lower(quality_grade));
create index if not exists product_type_idx      on public.product (type);
create index if not exists product_active_idx    on public.product (is_active);
create index if not exists product_variety_trgm_idx on public.product using gin (variety extensions.gin_trgm_ops);
create index if not exists product_quality_trgm_idx on public.product using gin (quality_grade extensions.gin_trgm_ops);

create table if not exists public.coffee_detail (
  product_id       bigint primary key references public.product (id),
  humidity_percent numeric(5, 2) not null check (humidity_percent between 0 and 100)
);

create table if not exists public.cacao_detail (
  product_id           bigint primary key references public.product (id),
  bean_type            text not null check (char_length(bean_type) between 1 and 100),
  fermentation_percent numeric(5, 2) not null check (fermentation_percent between 0 and 100)
);

create table if not exists public.product_certification (
  product_id       bigint not null references public.product (id),
  certification_id bigint not null references public.certification (id),
  primary key (product_id, certification_id)
);
create index if not exists product_certification_cert_idx on public.product_certification (certification_id);

-- 3. Reglas de integridad en la base ----------------------------------------------------------------
-- El tipo y la unidad base no cambian; se actualiza updated_at.
create or replace function public.guard_product_update()
returns trigger
language plpgsql
as $$
begin
  if new.type <> old.type then
    raise exception 'El tipo de producto no se puede cambiar.';
  end if;
  if new.base_unit_code <> old.base_unit_code then
    raise exception 'La unidad base no se puede cambiar.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists product_guard on public.product;
create trigger product_guard
  before update on public.product
  for each row execute function public.guard_product_update();

-- El detalle debe corresponder al tipo del producto (coffee_detail solo para cafe, etc.).
create or replace function public.guard_product_detail_type()
returns trigger
language plpgsql
as $$
declare
  v_expected text := case tg_table_name when 'coffee_detail' then 'coffee' else 'cacao' end;
begin
  if (select type from public.product where id = new.product_id) is distinct from v_expected then
    raise exception 'El detalle no corresponde al tipo del producto.';
  end if;
  return new;
end;
$$;

drop trigger if exists coffee_detail_type_guard on public.coffee_detail;
create trigger coffee_detail_type_guard
  before insert or update on public.coffee_detail
  for each row execute function public.guard_product_detail_type();
drop trigger if exists cacao_detail_type_guard on public.cacao_detail;
create trigger cacao_detail_type_guard
  before insert or update on public.cacao_detail
  for each row execute function public.guard_product_detail_type();

-- Todo producto debe tener su detalle al terminar la transaccion (restriccion diferida).
create or replace function public.require_product_detail()
returns trigger
language plpgsql
as $$
begin
  if new.type = 'coffee' and not exists (select 1 from public.coffee_detail where product_id = new.id) then
    raise exception 'El producto de café necesita su detalle (humedad).';
  end if;
  if new.type = 'cacao' and not exists (select 1 from public.cacao_detail where product_id = new.id) then
    raise exception 'El producto de cacao necesita su detalle (tipo de grano y fermentación).';
  end if;
  return null;
end;
$$;

drop trigger if exists product_detail_required on public.product;
create constraint trigger product_detail_required
  after insert on public.product
  deferrable initially deferred
  for each row execute function public.require_product_detail();

-- PLAT-506: los productos no se borran (se inactivan), tengan historial o no.
create or replace function public.block_product_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Los productos no se borran: se inactivan.';
end;
$$;

drop trigger if exists product_no_delete on public.product;
create trigger product_no_delete
  before delete on public.product
  for each row execute function public.block_product_delete();
drop trigger if exists coffee_detail_no_delete on public.coffee_detail;
create trigger coffee_detail_no_delete
  before delete on public.coffee_detail
  for each row execute function public.block_product_delete();
drop trigger if exists cacao_detail_no_delete on public.cacao_detail;
create trigger cacao_detail_no_delete
  before delete on public.cacao_detail
  for each row execute function public.block_product_delete();

-- 4. Permisos y RLS (solo lectura directa; escritura por funciones) ---------------------------------
insert into public.permission (code, description) values
  ('products.read', 'Consultar el catalogo de productos.'),
  ('products.create', 'Registrar productos.'),
  ('products.update', 'Editar, inactivar y asociar certificaciones a productos.')
on conflict (code) do nothing;

alter table public.unit_of_measure     enable row level security;
alter table public.certification       enable row level security;
alter table public.product             enable row level security;
alter table public.coffee_detail       enable row level security;
alter table public.cacao_detail        enable row level security;
alter table public.product_certification enable row level security;

drop policy if exists unit_of_measure_select on public.unit_of_measure;
create policy unit_of_measure_select on public.unit_of_measure
  for select to authenticated using (public.is_active_user());
drop policy if exists certification_select on public.certification;
create policy certification_select on public.certification
  for select to authenticated using (public.is_active_user());
drop policy if exists product_select on public.product;
create policy product_select on public.product
  for select to authenticated using (public.has_permission('products.read'));
drop policy if exists coffee_detail_select on public.coffee_detail;
create policy coffee_detail_select on public.coffee_detail
  for select to authenticated using (public.has_permission('products.read'));
drop policy if exists cacao_detail_select on public.cacao_detail;
create policy cacao_detail_select on public.cacao_detail
  for select to authenticated using (public.has_permission('products.read'));
drop policy if exists product_certification_select on public.product_certification;
create policy product_certification_select on public.product_certification
  for select to authenticated using (public.has_permission('products.read'));

revoke all on public.unit_of_measure, public.certification, public.product, public.coffee_detail,
              public.cacao_detail, public.product_certification from anon, authenticated;
grant select on public.unit_of_measure, public.certification, public.product, public.coffee_detail,
                public.cacao_detail, public.product_certification to authenticated;

-- 5. Funciones de escritura (atomicas, con permiso y validacion) --------------------------------------
-- Convencion de errores: 42501 sin permiso; P0002 no encontrado; 22023 dato no valido; P0001 conflicto.

create or replace function public._product_audit(p_action text, p_id bigint, p_meta jsonb)
returns void
language sql security definer set search_path = public
as $$
  insert into public.audit_log (actor_user_id, action, entity_type, entity_id, metadata)
  values ((select id from public.profile where auth_user_id = auth.uid()), p_action, 'product', p_id, p_meta);
$$;
revoke all on function public._product_audit(text, bigint, jsonb) from public, anon, authenticated;

-- Convierte un campo JSON a numerico con un mensaje claro si no lo es.
create or replace function public._product_num(p jsonb, p_key text, p_label text)
returns numeric
language plpgsql immutable
as $$
begin
  if p -> p_key is null or jsonb_typeof(p -> p_key) = 'null' then
    return null;
  end if;
  if jsonb_typeof(p -> p_key) not in ('number', 'string') then
    raise exception '% debe ser un número.', p_label using errcode = '22023';
  end if;
  return (p ->> p_key)::numeric;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception '% debe ser un número válido.', p_label using errcode = '22023';
end;
$$;
revoke all on function public._product_num(jsonb, text, text) from public, anon, authenticated;

create or replace function public.create_product(p jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_type text;
  v_variety text;
  v_quality text;
  v_hs text;
  v_unit text;
  v_threshold numeric;
  v_humidity numeric;
  v_bean text;
  v_ferment numeric;
  v_cert_ids bigint[] := '{}';
  v_id bigint;
  v_allowed text[];
  v_key text;
begin
  if not public.has_permission('products.create') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'La solicitud no es válida.' using errcode = '22023';
  end if;

  v_type := p ->> 'type';
  if v_type is null or v_type not in ('coffee', 'cacao') then
    raise exception 'El tipo de producto debe ser café o cacao.' using errcode = '22023';
  end if;

  v_allowed := array['type', 'variety', 'quality_grade', 'hs_code', 'base_unit_code',
                     'low_stock_threshold', 'certification_ids']
    || case v_type when 'coffee' then array['humidity_percent']
                   else array['bean_type', 'fermentation_percent'] end;
  for v_key in select jsonb_object_keys(p) loop
    if not (v_key = any (v_allowed)) then
      raise exception 'Campo no permitido para un producto de %: %.',
        case v_type when 'coffee' then 'café' else 'cacao' end, v_key using errcode = '22023';
    end if;
  end loop;

  v_variety := nullif(btrim(p ->> 'variety'), '');
  v_quality := nullif(btrim(p ->> 'quality_grade'), '');
  v_hs := nullif(btrim(coalesce(p ->> 'hs_code', '')), '');
  v_unit := nullif(btrim(p ->> 'base_unit_code'), '');
  v_threshold := public._product_num(p, 'low_stock_threshold', 'El umbral de stock bajo');

  if v_variety is null then raise exception 'La variedad es obligatoria.' using errcode = '22023'; end if;
  if char_length(v_variety) > 120 then raise exception 'La variedad admite máximo 120 caracteres.' using errcode = '22023'; end if;
  if v_quality is null then raise exception 'La calidad es obligatoria.' using errcode = '22023'; end if;
  if char_length(v_quality) > 80 then raise exception 'La calidad admite máximo 80 caracteres.' using errcode = '22023'; end if;
  if v_hs is not null and v_hs !~ '^[0-9]{4}(\.[0-9]{2}){0,3}$' then
    raise exception 'El código HS no tiene un formato válido (por ejemplo 0901.11).' using errcode = '22023';
  end if;
  if v_unit is null or not exists (select 1 from public.unit_of_measure where code = v_unit) then
    raise exception 'La unidad base no existe.' using errcode = '22023';
  end if;
  if v_threshold is not null and v_threshold < 0 then
    raise exception 'El umbral de stock bajo no puede ser negativo.' using errcode = '22023';
  end if;

  if v_type = 'coffee' then
    v_humidity := public._product_num(p, 'humidity_percent', 'La humedad');
    if v_humidity is null then raise exception 'La humedad es obligatoria para el café.' using errcode = '22023'; end if;
    if v_humidity < 0 or v_humidity > 100 then raise exception 'La humedad debe estar entre 0 y 100.' using errcode = '22023'; end if;
  else
    v_bean := nullif(btrim(p ->> 'bean_type'), '');
    v_ferment := public._product_num(p, 'fermentation_percent', 'El porcentaje de fermentación');
    if v_bean is null then raise exception 'El tipo de grano es obligatorio para el cacao.' using errcode = '22023'; end if;
    if char_length(v_bean) > 100 then raise exception 'El tipo de grano admite máximo 100 caracteres.' using errcode = '22023'; end if;
    if v_ferment is null then raise exception 'El porcentaje de fermentación es obligatorio para el cacao.' using errcode = '22023'; end if;
    if v_ferment < 0 or v_ferment > 100 then raise exception 'El porcentaje de fermentación debe estar entre 0 y 100.' using errcode = '22023'; end if;
  end if;

  if p ? 'certification_ids' and jsonb_typeof(p -> 'certification_ids') <> 'null' then
    if jsonb_typeof(p -> 'certification_ids') <> 'array'
       or exists (select 1 from jsonb_array_elements(p -> 'certification_ids') e
                  where jsonb_typeof(e) <> 'number' or e::text !~ '^[0-9]+$') then
      raise exception 'Las certificaciones deben ser una lista de identificadores.' using errcode = '22023';
    end if;
    select coalesce(array_agg(e::bigint), '{}') into v_cert_ids
      from jsonb_array_elements_text(p -> 'certification_ids') e;
    if cardinality(v_cert_ids) <> (select count(distinct c) from unnest(v_cert_ids) c) then
      raise exception 'No se permiten certificaciones duplicadas.' using errcode = '22023';
    end if;
    if exists (select 1 from unnest(v_cert_ids) c
               where c not in (select id from public.certification where is_active)) then
      raise exception 'Una o más certificaciones no existen o están inactivas.' using errcode = '22023';
    end if;
  end if;

  begin
    insert into public.product (type, variety, quality_grade, hs_code, base_unit_code, low_stock_threshold)
    values (v_type, v_variety, v_quality, v_hs, v_unit, v_threshold)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ya existe un producto con ese tipo, variedad y calidad.';
  end;

  if v_type = 'coffee' then
    insert into public.coffee_detail (product_id, humidity_percent) values (v_id, v_humidity);
  else
    insert into public.cacao_detail (product_id, bean_type, fermentation_percent) values (v_id, v_bean, v_ferment);
  end if;

  insert into public.product_certification (product_id, certification_id)
  select v_id, c from unnest(v_cert_ids) c;

  perform public._product_audit('product.created', v_id,
    jsonb_build_object('type', v_type, 'certification_ids', to_jsonb(v_cert_ids)));
  return v_id;
end;
$$;

create or replace function public.update_product(p_id bigint, p jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_prod public.product;
  v_allowed text[];
  v_key text;
  v_changed text[] := '{}';
  v_variety text;
  v_quality text;
  v_hs text;
  v_threshold numeric;
  v_humidity numeric;
  v_bean text;
  v_ferment numeric;
begin
  if not public.has_permission('products.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  select * into v_prod from public.product where id = p_id for update;
  if not found then
    raise exception 'No se encontró el producto solicitado.' using errcode = 'P0002';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' or p = '{}'::jsonb then
    raise exception 'Indica al menos un campo para actualizar.' using errcode = '22023';
  end if;

  v_allowed := array['type', 'base_unit_code', 'variety', 'quality_grade', 'hs_code', 'low_stock_threshold']
    || case v_prod.type when 'coffee' then array['humidity_percent']
                        else array['bean_type', 'fermentation_percent'] end;
  for v_key in select jsonb_object_keys(p) loop
    if not (v_key = any (v_allowed)) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;
  if p ? 'type' and p ->> 'type' is distinct from v_prod.type then
    raise exception 'El tipo de producto no se puede cambiar.' using errcode = '22023';
  end if;
  if p ? 'base_unit_code' and p ->> 'base_unit_code' is distinct from v_prod.base_unit_code then
    raise exception 'La unidad base no se puede cambiar.' using errcode = '22023';
  end if;

  v_variety := v_prod.variety; v_quality := v_prod.quality_grade;
  v_hs := v_prod.hs_code; v_threshold := v_prod.low_stock_threshold;

  if p ? 'variety' then
    v_variety := nullif(btrim(p ->> 'variety'), '');
    if v_variety is null then raise exception 'La variedad es obligatoria.' using errcode = '22023'; end if;
    if char_length(v_variety) > 120 then raise exception 'La variedad admite máximo 120 caracteres.' using errcode = '22023'; end if;
  end if;
  if p ? 'quality_grade' then
    v_quality := nullif(btrim(p ->> 'quality_grade'), '');
    if v_quality is null then raise exception 'La calidad es obligatoria.' using errcode = '22023'; end if;
    if char_length(v_quality) > 80 then raise exception 'La calidad admite máximo 80 caracteres.' using errcode = '22023'; end if;
  end if;
  if p ? 'hs_code' then
    v_hs := nullif(btrim(coalesce(p ->> 'hs_code', '')), '');
    if v_hs is not null and v_hs !~ '^[0-9]{4}(\.[0-9]{2}){0,3}$' then
      raise exception 'El código HS no tiene un formato válido (por ejemplo 0901.11).' using errcode = '22023';
    end if;
  end if;
  if p ? 'low_stock_threshold' then
    v_threshold := public._product_num(p, 'low_stock_threshold', 'El umbral de stock bajo');
    if v_threshold is not null and v_threshold < 0 then
      raise exception 'El umbral de stock bajo no puede ser negativo.' using errcode = '22023';
    end if;
  end if;

  if v_variety is distinct from v_prod.variety then v_changed := array_append(v_changed, 'variety'); end if;
  if v_quality is distinct from v_prod.quality_grade then v_changed := array_append(v_changed, 'quality_grade'); end if;
  if v_hs is distinct from v_prod.hs_code then v_changed := array_append(v_changed, 'hs_code'); end if;
  if v_threshold is distinct from v_prod.low_stock_threshold then v_changed := array_append(v_changed, 'low_stock_threshold'); end if;

  begin
    update public.product
       set variety = v_variety, quality_grade = v_quality, hs_code = v_hs, low_stock_threshold = v_threshold
     where id = p_id;
  exception when unique_violation then
    raise exception 'Ya existe un producto con ese tipo, variedad y calidad.';
  end;

  if v_prod.type = 'coffee' and p ? 'humidity_percent' then
    v_humidity := public._product_num(p, 'humidity_percent', 'La humedad');
    if v_humidity is null then raise exception 'La humedad es obligatoria para el café.' using errcode = '22023'; end if;
    if v_humidity < 0 or v_humidity > 100 then raise exception 'La humedad debe estar entre 0 y 100.' using errcode = '22023'; end if;
    if v_humidity is distinct from (select humidity_percent from public.coffee_detail where product_id = p_id) then
      v_changed := array_append(v_changed, 'humidity_percent');
    end if;
    update public.coffee_detail set humidity_percent = v_humidity where product_id = p_id;
  end if;

  if v_prod.type = 'cacao' then
    if p ? 'bean_type' then
      v_bean := nullif(btrim(p ->> 'bean_type'), '');
      if v_bean is null then raise exception 'El tipo de grano es obligatorio para el cacao.' using errcode = '22023'; end if;
      if char_length(v_bean) > 100 then raise exception 'El tipo de grano admite máximo 100 caracteres.' using errcode = '22023'; end if;
      if v_bean is distinct from (select bean_type from public.cacao_detail where product_id = p_id) then
        v_changed := array_append(v_changed, 'bean_type');
      end if;
      update public.cacao_detail set bean_type = v_bean where product_id = p_id;
    end if;
    if p ? 'fermentation_percent' then
      v_ferment := public._product_num(p, 'fermentation_percent', 'El porcentaje de fermentación');
      if v_ferment is null then raise exception 'El porcentaje de fermentación es obligatorio para el cacao.' using errcode = '22023'; end if;
      if v_ferment < 0 or v_ferment > 100 then raise exception 'El porcentaje de fermentación debe estar entre 0 y 100.' using errcode = '22023'; end if;
      if v_ferment is distinct from (select fermentation_percent from public.cacao_detail where product_id = p_id) then
        v_changed := array_append(v_changed, 'fermentation_percent');
      end if;
      update public.cacao_detail set fermentation_percent = v_ferment where product_id = p_id;
    end if;
  end if;

  if cardinality(v_changed) > 0 then
    update public.product set updated_at = now() where id = p_id;
    perform public._product_audit('product.updated', p_id, jsonb_build_object('fields', to_jsonb(v_changed)));
  end if;
end;
$$;

create or replace function public.set_product_active(p_id bigint, p_active boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_current boolean;
begin
  if not public.has_permission('products.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if p_active is null then
    raise exception 'Indica si el producto debe quedar activo.' using errcode = '22023';
  end if;
  select is_active into v_current from public.product where id = p_id for update;
  if not found then
    raise exception 'No se encontró el producto solicitado.' using errcode = 'P0002';
  end if;
  if v_current is distinct from p_active then
    update public.product set is_active = p_active where id = p_id;
    perform public._product_audit(case when p_active then 'product.reactivated' else 'product.inactivated' end,
      p_id, '{}'::jsonb);
  end if;
end;
$$;

create or replace function public.set_product_certifications(p_id bigint, p_ids bigint[])
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_ids bigint[] := coalesce(p_ids, '{}');
  v_added bigint[];
  v_removed bigint[];
begin
  if not public.has_permission('products.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  perform 1 from public.product where id = p_id for update;
  if not found then
    raise exception 'No se encontró el producto solicitado.' using errcode = 'P0002';
  end if;
  if cardinality(v_ids) <> (select count(distinct c) from unnest(v_ids) c) then
    raise exception 'No se permiten certificaciones duplicadas.' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(v_ids) c where c not in (select id from public.certification)) then
    raise exception 'Una o más certificaciones no existen.' using errcode = '22023';
  end if;

  select coalesce(array_agg(c), '{}') into v_added from unnest(v_ids) c
   where c not in (select certification_id from public.product_certification where product_id = p_id);
  select coalesce(array_agg(certification_id), '{}') into v_removed from public.product_certification
   where product_id = p_id and certification_id <> all (v_ids);

  -- Una certificacion inactiva puede conservarse, pero no asignarse de nuevo.
  if exists (select 1 from unnest(v_added) c where c in (select id from public.certification where not is_active)) then
    raise exception 'Una o más certificaciones están inactivas.' using errcode = '22023';
  end if;

  if cardinality(v_added) = 0 and cardinality(v_removed) = 0 then
    return;
  end if;
  delete from public.product_certification where product_id = p_id;
  insert into public.product_certification (product_id, certification_id)
  select p_id, c from unnest(v_ids) c;
  update public.product set updated_at = now() where id = p_id;
  perform public._product_audit('product.certifications_changed', p_id,
    jsonb_build_object('added', to_jsonb(v_added), 'removed', to_jsonb(v_removed)));
end;
$$;

revoke all on function public.create_product(jsonb), public.update_product(bigint, jsonb),
                       public.set_product_active(bigint, boolean),
                       public.set_product_certifications(bigint, bigint[]) from public, anon;
grant execute on function public.create_product(jsonb), public.update_product(bigint, jsonb),
                          public.set_product_active(bigint, boolean),
                          public.set_product_certifications(bigint, bigint[]) to authenticated;

-- 6. Vista de catalogo (PLAT-503) -----------------------------------------------------------------------
-- security_invoker: respeta las politicas RLS de quien consulta (products.read para ver productos).
create or replace view public.product_catalog
with (security_invoker = true) as
select
  p.id,
  p.type,
  p.variety,
  p.quality_grade,
  p.hs_code,
  p.base_unit_code,
  u.name as base_unit_name,
  p.low_stock_threshold,
  p.is_active,
  p.created_at,
  p.updated_at,
  cd.humidity_percent,
  cc.bean_type,
  cc.fermentation_percent,
  coalesce(cert.items, '[]'::jsonb) as certifications,
  coalesce(cert.ids, '{}'::bigint[]) as certification_ids
from public.product p
join public.unit_of_measure u on u.code = p.base_unit_code
left join public.coffee_detail cd on cd.product_id = p.id
left join public.cacao_detail cc on cc.product_id = p.id
left join lateral (
  select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name) order by c.name) as items,
         array_agg(c.id order by c.id) as ids
  from public.product_certification pc
  join public.certification c on c.id = pc.certification_id
  where pc.product_id = p.id
) cert on true;

revoke all on public.product_catalog from public, anon, authenticated;
grant select on public.product_catalog to authenticated;
