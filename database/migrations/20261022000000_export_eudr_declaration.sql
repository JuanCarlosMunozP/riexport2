-- PLAT-570..573 HU.28: declaracion de diligencia debida EUDR de una exportacion.
-- La funcion es SECURITY INVOKER: se apoya en los permisos de las vistas de trazabilidad
-- (exports.read + farms.read) y no escribe nada; la declaracion se genera bajo demanda.
-- Una declaracion es valida solo si TODA linea de la exportacion llega a un lote, una finca
-- con coordenadas, un proveedor y un codigo HS.

create or replace function public.export_eudr_declaration(p_export_id bigint)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_export record;
  v_line_count integer;
  v_trace_count integer;
  v_without_point integer;
  v_without_hs integer;
  v_issues text[] := '{}';
begin
  if not public.has_permission('exports.read') or not public.has_permission('farms.read') then
    raise exception 'No tienes permiso para consultar la trazabilidad de exportaciones.' using errcode = '42501';
  end if;

  select e.id, e.export_date, e.destination_country_code, e.status, e.order_id, e.incoterm_code
    into v_export
    from public.export e where e.id = p_export_id;
  if not found then
    raise exception 'La exportación no existe.' using errcode = 'P0002';
  end if;
  if v_export.status = 'cancelled' then
    raise exception 'La exportación está cancelada.' using errcode = '22023';
  end if;

  select count(*) into v_line_count from public.export_line where export_id = p_export_id;
  select count(*),
         count(*) filter (where latitude is null or longitude is null),
         count(*) filter (where hs_code_snapshot is null)
    into v_trace_count, v_without_point, v_without_hs
    from public.export_traceability where export_id = p_export_id;

  if v_line_count = 0 then v_issues := array_append(v_issues, 'La exportación no tiene líneas.'); end if;
  if v_trace_count < v_line_count then
    v_issues := array_append(v_issues, 'Hay líneas sin lote, finca o proveedor de origen.');
  end if;
  if v_without_point > 0 then
    v_issues := array_append(v_issues, v_without_point || ' línea(s) con finca sin coordenadas de geolocalización.');
  end if;
  if v_without_hs > 0 then
    v_issues := array_append(v_issues, v_without_hs || ' línea(s) sin código arancelario HS.');
  end if;

  return jsonb_build_object(
    'export_id', v_export.id,
    'export_date', v_export.export_date,
    'destination_country_code', v_export.destination_country_code,
    'incoterm_code', v_export.incoterm_code,
    'status', v_export.status,
    'declaration_date', current_date,
    'line_count', v_line_count,
    'total_quantity', coalesce((select sum(quantity) from public.export_line where export_id = p_export_id), 0),
    'farm_count', (select count(distinct farm_id) from public.export_traceability where export_id = p_export_id),
    'supplier_count', (select count(distinct supplier_id) from public.export_traceability where export_id = p_export_id),
    'traceability_valid', cardinality(v_issues) = 0,
    'issues', to_jsonb(v_issues),
    'hs_codes', coalesce((select jsonb_agg(distinct hs_code_snapshot) from public.export_traceability
                          where export_id = p_export_id and hs_code_snapshot is not null), '[]'::jsonb),
    'origin_farms', coalesce((select jsonb_agg(to_jsonb(o) - 'export_id' order by o.farm_name)
                              from public.export_origin_farms o where o.export_id = p_export_id), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.export_eudr_declaration(bigint) from public, anon;
grant execute on function public.export_eudr_declaration(bigint) to authenticated;
