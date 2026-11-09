-- Modulo de clientes (EP-4): tabla, validacion del EORI, politicas RLS y escritura atomica por funciones.
-- PLAT-526 (registrar un cliente), PLAT-527 (tabla de clientes) y PLAT-528 (validar el formato EORI en la base).
--
-- Diseno (docs/modelo-datos.md, "Clientes y operacion comercial"; mismo patron que products y suppliers):
--  * Se LEE la tabla con RLS (customers.read); se ESCRIBE solo por funciones SECURITY DEFINER
--    (create_customer, update_customer, set_customer_active) que comprueban permiso y validan.
--  * Los clientes no se borran nunca (baja logica con is_active): privilegio revocado y trigger.
--  * EORI (Economic Operators Registration and Identification): se guarda NORMALIZADO (mayusculas, sin
--    espacios ni guiones) y es unico. Formato: 2 letras de pais + 1 a 15 caracteres alfanumericos.
--    La validacion esta en la tabla (CHECK) y en la funcion (mensajes claros).
--  * Supuestos a confirmar con el cliente (el backlog deja abierta la obligatoriedad del EORI por pais):
--      - el prefijo del EORI debe corresponder al pais del cliente (Grecia usa EL; el Reino Unido admite
--        GB y XI para Irlanda del Norte);
--      - el EORI es OBLIGATORIO si el cliente esta en un pais de la Union Europea (27) y opcional fuera;
--      - pais y moneda se guardan como codigos ISO (2 y 3 letras) sin catalogos country/currency, que aun
--        no existen; la moneda preferida es obligatoria (el modelo la exige).

-- 1. Tabla ---------------------------------------------------------------------------------------
create table if not exists public.customer (
  id                      bigint generated always as identity primary key,
  name                    text not null check (char_length(name) between 1 and 180),
  contact_name            text check (char_length(contact_name) between 1 and 160),
  email                   text check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 254),
  country_code            text not null check (country_code ~ '^[A-Z]{2}$'),
  eori_number             text,
  preferred_currency_code text not null check (preferred_currency_code ~ '^[A-Z]{3}$'),
  is_active               boolean not null default true,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  -- PLAT-528: formato del EORI (normalizado).
  constraint customer_eori_format check (eori_number is null or eori_number ~ '^[A-Z]{2}[A-Z0-9]{1,15}$'),
  -- El prefijo del EORI es el pais que lo emitio.
  constraint customer_eori_prefix check (
    eori_number is null
    or left(eori_number, 2) = case country_code when 'GR' then 'EL' else country_code end
    or (country_code = 'GB' and left(eori_number, 2) = 'XI')
  ),
  -- Obligatorio en los 27 paises de la Union Europea.
  constraint customer_eori_required_eu check (
    eori_number is not null
    or country_code not in ('AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU','IE','IT',
                            'LV','LT','LU','MT','NL','PL','PT','RO','SK','SI','ES','SE')
  )
);

create unique index if not exists customer_eori_uq on public.customer (eori_number);
create index if not exists customer_active_idx on public.customer (is_active);
create index if not exists customer_country_idx on public.customer (country_code);
create index if not exists customer_name_trgm_idx
  on public.customer using gin (name extensions.gin_trgm_ops);

-- 2. Reglas de integridad -------------------------------------------------------------------------
create or replace function public.guard_customer_update()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists customer_guard on public.customer;
create trigger customer_guard
  before update on public.customer
  for each row execute function public.guard_customer_update();

-- Los clientes no se borran (se inactivan), tengan pedidos o no.
create or replace function public.block_customer_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Los clientes no se borran: se inactivan.';
end;
$$;

drop trigger if exists customer_no_delete on public.customer;
create trigger customer_no_delete
  before delete on public.customer
  for each row execute function public.block_customer_delete();

-- 3. Permisos y RLS -------------------------------------------------------------------------------
insert into public.permission (code, description) values
  ('customers.read', 'Consultar clientes.'),
  ('customers.create', 'Registrar clientes.'),
  ('customers.update', 'Editar e inactivar clientes.')
on conflict (code) do nothing;

alter table public.customer enable row level security;

drop policy if exists customer_select on public.customer;
create policy customer_select on public.customer
  for select to authenticated using (public.has_permission('customers.read'));

revoke all on public.customer from anon, authenticated;
grant select on public.customer to authenticated;

-- 4. Validacion del EORI (PLAT-528) y funciones de escritura -------------------------------------------
-- Convencion de errores: 42501 sin permiso; P0002 no encontrado; 22023 dato no valido; P0001 conflicto.

-- Normaliza un EORI: mayusculas y sin espacios, guiones ni puntos. Null si queda vacio.
create or replace function public.normalize_eori(p text)
returns text
language sql immutable
set search_path = public
as $$
  select nullif(upper(regexp_replace(coalesce(p, ''), '[\s.\-]', '', 'g')), '');
$$;

-- Valida un EORI normalizado contra el pais del cliente. Lanza 22023 con un mensaje claro.
create or replace function public._check_eori(p_eori text, p_country text)
returns void
language plpgsql immutable
as $$
declare
  v_prefix text := case p_country when 'GR' then 'EL' else p_country end;
begin
  if p_eori is null then
    if p_country in ('AT','BE','BG','HR','CY','CZ','DK','EE','FI','FR','DE','GR','HU','IE','IT',
                     'LV','LT','LU','MT','NL','PL','PT','RO','SK','SI','ES','SE') then
      raise exception 'El EORI es obligatorio para clientes de la Unión Europea.' using errcode = '22023';
    end if;
    return;
  end if;
  if p_eori !~ '^[A-Z]{2}[A-Z0-9]{1,15}$' then
    raise exception 'El EORI no tiene un formato válido: 2 letras de país y hasta 15 caracteres alfanuméricos (por ejemplo ES12345678Z).'
      using errcode = '22023';
  end if;
  if left(p_eori, 2) <> v_prefix and not (p_country = 'GB' and left(p_eori, 2) = 'XI') then
    raise exception 'El EORI debe empezar por % (el país del cliente).', v_prefix using errcode = '22023';
  end if;
end;
$$;

create or replace function public._customer_audit(p_action text, p_id bigint, p_meta jsonb)
returns void
language sql security definer set search_path = public
as $$
  insert into public.audit_log (actor_user_id, action, entity_type, entity_id, metadata)
  values ((select id from public.profile where auth_user_id = auth.uid()), p_action, 'customer', p_id, p_meta);
$$;
revoke all on function public._customer_audit(text, bigint, jsonb) from public, anon, authenticated;

create or replace function public._customer_text(p jsonb, p_key text, p_label text, p_max int, p_pattern text default null)
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
revoke all on function public._customer_text(jsonb, text, text, int, text) from public, anon, authenticated;

create or replace function public.create_customer(p jsonb)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_key text;
  v_name text;
  v_contact text;
  v_email text;
  v_country text;
  v_eori text;
  v_currency text;
  v_id bigint;
begin
  if not public.has_permission('customers.create') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'La solicitud no es válida.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if not (v_key = any (array['name', 'contact_name', 'email', 'country_code', 'eori_number', 'preferred_currency_code'])) then
      raise exception 'Campo no permitido para un cliente: %.', v_key using errcode = '22023';
    end if;
  end loop;

  v_name := public._customer_text(p, 'name', 'El nombre', 180);
  v_contact := public._customer_text(p, 'contact_name', 'El nombre de contacto', 160);
  v_email := lower(public._customer_text(p, 'email', 'El correo', 254, '^[^@\s]+@[^@\s]+\.[^@\s]+$'));
  v_country := upper(public._customer_text(p, 'country_code', 'El país', 2));
  v_currency := upper(public._customer_text(p, 'preferred_currency_code', 'La moneda', 3));
  v_eori := public.normalize_eori(public._customer_text(p, 'eori_number', 'El EORI', 40));

  if v_name is null then raise exception 'El nombre del cliente es obligatorio.' using errcode = '22023'; end if;
  if v_country is null then raise exception 'El país es obligatorio.' using errcode = '22023'; end if;
  if v_country !~ '^[A-Z]{2}$' then
    raise exception 'El país debe ser un código de 2 letras (por ejemplo CO).' using errcode = '22023';
  end if;
  if v_currency is null then raise exception 'La moneda preferida es obligatoria.' using errcode = '22023'; end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'La moneda debe ser un código de 3 letras (por ejemplo USD).' using errcode = '22023';
  end if;
  perform public._check_eori(v_eori, v_country);

  begin
    insert into public.customer (name, contact_name, email, country_code, eori_number, preferred_currency_code)
    values (v_name, v_contact, v_email, v_country, v_eori, v_currency)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ya existe un cliente con ese EORI.';
  end;

  perform public._customer_audit('customer.created', v_id, jsonb_build_object('country_code', v_country));
  return v_id;
end;
$$;

create or replace function public.update_customer(p_id bigint, p jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.customer;
  v_key text;
  v_changed text[] := '{}';
  v_name text;
  v_contact text;
  v_email text;
  v_country text;
  v_eori text;
  v_currency text;
begin
  if not public.has_permission('customers.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  select * into v_row from public.customer where id = p_id for update;
  if not found then
    raise exception 'No se encontró el cliente solicitado.' using errcode = 'P0002';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' or p = '{}'::jsonb then
    raise exception 'Indica al menos un campo para actualizar.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p) loop
    if not (v_key = any (array['name', 'contact_name', 'email', 'country_code', 'eori_number', 'preferred_currency_code'])) then
      raise exception 'Campo no permitido: %.', v_key using errcode = '22023';
    end if;
  end loop;

  v_name := v_row.name; v_contact := v_row.contact_name; v_email := v_row.email;
  v_country := v_row.country_code; v_eori := v_row.eori_number; v_currency := v_row.preferred_currency_code;

  if p ? 'name' then
    v_name := public._customer_text(p, 'name', 'El nombre', 180);
    if v_name is null then raise exception 'El nombre del cliente es obligatorio.' using errcode = '22023'; end if;
  end if;
  if p ? 'contact_name' then v_contact := public._customer_text(p, 'contact_name', 'El nombre de contacto', 160); end if;
  if p ? 'email' then v_email := lower(public._customer_text(p, 'email', 'El correo', 254, '^[^@\s]+@[^@\s]+\.[^@\s]+$')); end if;
  if p ? 'country_code' then
    v_country := upper(public._customer_text(p, 'country_code', 'El país', 2));
    if v_country is null then raise exception 'El país es obligatorio.' using errcode = '22023'; end if;
    if v_country !~ '^[A-Z]{2}$' then
      raise exception 'El país debe ser un código de 2 letras (por ejemplo CO).' using errcode = '22023';
    end if;
  end if;
  if p ? 'preferred_currency_code' then
    v_currency := upper(public._customer_text(p, 'preferred_currency_code', 'La moneda', 3));
    if v_currency is null then raise exception 'La moneda preferida es obligatoria.' using errcode = '22023'; end if;
    if v_currency !~ '^[A-Z]{3}$' then
      raise exception 'La moneda debe ser un código de 3 letras (por ejemplo USD).' using errcode = '22023';
    end if;
  end if;
  if p ? 'eori_number' then
    v_eori := public.normalize_eori(public._customer_text(p, 'eori_number', 'El EORI', 40));
  end if;
  -- Cambiar el pais o el EORI obliga a que sigan siendo coherentes entre si.
  perform public._check_eori(v_eori, v_country);

  if v_name is distinct from v_row.name then v_changed := array_append(v_changed, 'name'); end if;
  if v_contact is distinct from v_row.contact_name then v_changed := array_append(v_changed, 'contact_name'); end if;
  if v_email is distinct from v_row.email then v_changed := array_append(v_changed, 'email'); end if;
  if v_country is distinct from v_row.country_code then v_changed := array_append(v_changed, 'country_code'); end if;
  if v_eori is distinct from v_row.eori_number then v_changed := array_append(v_changed, 'eori_number'); end if;
  if v_currency is distinct from v_row.preferred_currency_code then v_changed := array_append(v_changed, 'preferred_currency_code'); end if;
  if cardinality(v_changed) = 0 then
    return;
  end if;

  begin
    update public.customer
       set name = v_name, contact_name = v_contact, email = v_email, country_code = v_country,
           eori_number = v_eori, preferred_currency_code = v_currency
     where id = p_id;
  exception when unique_violation then
    raise exception 'Ya existe un cliente con ese EORI.';
  end;
  perform public._customer_audit('customer.updated', p_id, jsonb_build_object('fields', to_jsonb(v_changed)));
end;
$$;

create or replace function public.set_customer_active(p_id bigint, p_active boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_current boolean;
begin
  if not public.has_permission('customers.update') then
    raise exception 'No tienes permiso para esta operación.' using errcode = '42501';
  end if;
  if p_active is null then
    raise exception 'Indica si el cliente debe quedar activo.' using errcode = '22023';
  end if;
  select is_active into v_current from public.customer where id = p_id for update;
  if not found then
    raise exception 'No se encontró el cliente solicitado.' using errcode = 'P0002';
  end if;
  if v_current is distinct from p_active then
    update public.customer set is_active = p_active where id = p_id;
    perform public._customer_audit(case when p_active then 'customer.reactivated' else 'customer.inactivated' end,
      p_id, '{}'::jsonb);
  end if;
end;
$$;

revoke all on function public.create_customer(jsonb), public.update_customer(bigint, jsonb),
                       public.set_customer_active(bigint, boolean) from public, anon;
grant execute on function public.create_customer(jsonb), public.update_customer(bigint, jsonb),
                          public.set_customer_active(bigint, boolean) to authenticated;
-- normalize_eori es una funcion pura: la app y las pruebas pueden usarla.
revoke all on function public.normalize_eori(text) from public, anon;
grant execute on function public.normalize_eori(text) to authenticated;
