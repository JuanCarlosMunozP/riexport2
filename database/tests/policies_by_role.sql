-- Matriz de pruebas: cada ROL SEMBRADO x cada tabla de negocio x cada operacion.
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f database/tests/policies_by_role.sql
-- Ejecutar desde la raiz del repositorio. Todo se revierte al final (tablas y usuarios de prueba):
-- la base no cambia.
--
-- Roles: A = administrador, C = usuario_comercial, L = encargado_logistico, K = cliente (externo).
-- Los permisos proceden de los perfiles de la migracion 20261107000000.
-- Cada celda se prueba ejecutando la sentencia y deshaciendola (sin efectos colaterales).

begin;

create temp table resultados(rol text, tabla text, op text, resultado text);
create temp table esperado(tabla text, op text, roles text);   -- roles que SI deben poder
grant all on resultados, esperado to authenticated, anon;

-- Ejecuta la sentencia y siempre la revierte. 'SI' = afecta/devuelve filas; 'no' = RLS o privilegio.
create function pg_temp.probe(p_sql text) returns text
language plpgsql as $$
declare n int;
begin
  begin
    execute p_sql;
    get diagnostics n = row_count;
    raise exception 'PROBE:%', n;
  exception when others then
    if sqlerrm like 'PROBE:%' then
      return case when substr(sqlerrm, 7)::int > 0 then 'SI' else 'no' end;
    elsif sqlerrm ilike '%row-level security%' or sqlerrm ilike '%permission denied%' then
      return 'no';
    else
      return 'ERR ' || sqlerrm;
    end if;
  end;
end $$;

\i database/tests/_domain_stubs.sql
alter table public.exchange_rate add column nota text;
\i database/drafts/domain_policies.sql
\i database/drafts/client_isolation.sql

-- ---------------------------------------------------------------------------- usuarios ---
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated', 'adm@rol.test', '{"first_name":"A","last_name":"Adm"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d2', 'authenticated', 'authenticated', 'com@rol.test', '{"first_name":"C","last_name":"Com"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d3', 'authenticated', 'authenticated', 'log@rol.test', '{"first_name":"L","last_name":"Log"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000d4', 'authenticated', 'authenticated', 'cli@rol.test', '{"first_name":"K","last_name":"Cli"}', now(), now());
update public.profile set role_id = (select id from public.role where name = 'administrador')       where email = 'adm@rol.test';
update public.profile set role_id = (select id from public.role where name = 'usuario_comercial')    where email = 'com@rol.test';
update public.profile set role_id = (select id from public.role where name = 'encargado_logistico')  where email = 'log@rol.test';
-- cli@rol.test conserva el rol 'cliente' que le asigna el registro

-- ------------------------------------------------------------------------------- datos ---
alter table public.customer alter column id restart with 1;   -- real: se revierte al final
insert into public.customer(name, country_code, preferred_currency_code) values ('C1', 'US', 'USD'), ('C2', 'US', 'USD');
insert into public.customer_order(customer_id) values (1), (2);
insert into public.order_line(order_id) values (1), (2);
insert into public.export(order_id) values (1), (2);
insert into public.export_line(export_id) values (1), (2);
insert into public.export_document(export_id) values (1), (2);
insert into public.stored_file default values;
insert into public.stored_file default values;
insert into public.inventory_movement default values;
insert into public.inventory_movement default values;
insert into public.payment_obligation(order_id) values (1), (2);
insert into public.payment_transaction default values;
insert into public.payment_transaction default values;
insert into public.exchange_rate default values;
insert into public.exchange_rate default values;
insert into public.shipment(export_id) values (1), (2);
insert into public.shipment_event(shipment_id) values (1), (2);
insert into public.notification(recipient_user_id, title) select id, 'n' from public.profile where email like '%@rol.test';
insert into public.customer_user(customer_id, profile_id) select 1, id from public.profile where email = 'cli@rol.test';

-- ------------------------------------------------------------------ lo esperado (la especificacion) ---
insert into esperado values
  ('customer','select','ACLK'), ('customer','insert',''), ('customer','update',''), ('customer','delete',''),
  ('customer_order','select','ACLK'), ('customer_order','insert','AC'), ('customer_order','update','AC'), ('customer_order','delete',''),
  ('order_line','select','ACLK'), ('order_line','insert','AC'), ('order_line','update','AC'), ('order_line','delete','AC'),
  ('export','select','ACLK'), ('export','insert','AC'), ('export','update','AC'), ('export','delete',''),
  ('export_line','select','ACLK'), ('export_line','insert','AC'), ('export_line','update','AC'), ('export_line','delete','AC'),
  ('export_document','select','ACLK'), ('export_document','insert','AC'), ('export_document','update',''), ('export_document','delete',''),
  ('stored_file','select','ACL'), ('stored_file','insert','ACLK'), ('stored_file','update',''), ('stored_file','delete',''),
  ('inventory_movement','select','ACL'), ('inventory_movement','insert','AL'), ('inventory_movement','update',''), ('inventory_movement','delete',''),
  ('payment_obligation','select','AC'), ('payment_obligation','insert','AC'), ('payment_obligation','update',''), ('payment_obligation','delete',''),
  ('payment_transaction','select','AC'), ('payment_transaction','insert','AC'), ('payment_transaction','update',''), ('payment_transaction','delete',''),
  ('exchange_rate','select','AC'), ('exchange_rate','insert',''), ('exchange_rate','update',''), ('exchange_rate','delete',''),
  ('shipment','select','ACLK'), ('shipment','insert','AL'), ('shipment','update','AL'), ('shipment','delete',''),
  ('shipment_event','select','ACLK'), ('shipment_event','insert','AL'), ('shipment_event','update',''), ('shipment_event','delete',''),
  ('notification','select','ACLK'), ('notification','insert',''), ('notification','update','ACLK'), ('notification','delete',''),
  ('customer_user','select','ACLK'), ('customer_user','insert',''), ('customer_user','update',''), ('customer_user','delete','');

-- --------------------------------------------------------------------- sentencias por tabla y operacion ---
create temp table sentencias(tabla text, op text, sql text);
insert into sentencias
select t.tabla, o.op,
  case o.op
    when 'select' then format('select * from public.%I', t.tabla)
    when 'delete' then format('delete from public.%I', t.tabla)
    when 'update' then format('update public.%I set %I = %I', t.tabla, t.col_upd, t.col_upd)
    else t.ins end
from (values
  ('customer',            'name',              $s$insert into public.customer(name, country_code, preferred_currency_code) values ('Z', 'US', 'USD')$s$),
  ('customer_order',      'nota',              'insert into public.customer_order(customer_id) values (1)'),
  ('order_line',          'order_id',          'insert into public.order_line(order_id) values (1)'),
  ('export',              'order_id',          'insert into public.export(order_id) values (1)'),
  ('export_line',         'export_id',         'insert into public.export_line(export_id) values (1)'),
  ('export_document',     'export_id',         'insert into public.export_document(export_id, created_by_id) values (1, public.current_profile_id())'),
  ('stored_file',         'uploaded_by_id',    'insert into public.stored_file(uploaded_by_id) values (public.current_profile_id())'),
  ('inventory_movement',  'performed_by_id',   'insert into public.inventory_movement(performed_by_id) values (public.current_profile_id())'),
  ('payment_obligation',  'order_id',          'insert into public.payment_obligation(order_id) values (1)'),
  ('payment_transaction', 'recorded_by_id',    'insert into public.payment_transaction(recorded_by_id) values (public.current_profile_id())'),
  ('exchange_rate',       'nota',              'insert into public.exchange_rate default values'),
  ('shipment',            'nota',              'insert into public.shipment(export_id) values (1)'),
  ('shipment_event',      'nota',              'insert into public.shipment_event(shipment_id) values (1)'),
  ('notification',        'read_at',           'insert into public.notification(recipient_user_id) values (public.current_profile_id())'),
  ('customer_user',       'profile_id',        'insert into public.customer_user(customer_id, profile_id) values (1, public.current_profile_id())')
) t(tabla, col_upd, ins)
cross join (values ('select'), ('insert'), ('update'), ('delete')) o(op);
grant all on sentencias to authenticated;

-- ----------------------------------------------------------------------- ejecucion de la matriz ---
do $$
declare
  actor record; stmt record;
begin
  for actor in
    select * from (values ('A','adm@rol.test'), ('C','com@rol.test'), ('L','log@rol.test'), ('K','cli@rol.test')) a(rol, email)
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', (select auth_user_id from public.profile where email = actor.email), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    for stmt in select * from sentencias order by tabla, op loop
      insert into resultados values (actor.rol, stmt.tabla, stmt.op, pg_temp.probe(stmt.sql));
    end loop;
    execute 'reset role';
  end loop;
end $$;

-- --------------------------------------------------------------------------------- informe ---
select tabla, op,
       max(resultado) filter (where rol = 'A') as "A admin",
       max(resultado) filter (where rol = 'C') as "C comercial",
       max(resultado) filter (where rol = 'L') as "L logistico",
       max(resultado) filter (where rol = 'K') as "K cliente"
from resultados group by tabla, op order by tabla, case op when 'select' then 1 when 'insert' then 2 when 'update' then 3 else 4 end;

select 'DIFERENCIAS CON LO ESPERADO' as seccion, r.rol, r.tabla, r.op, r.resultado as real,
       case when position(r.rol in e.roles) > 0 then 'SI' else 'no' end as esperado
from resultados r join esperado e on e.tabla = r.tabla and e.op = r.op
where r.resultado <> case when position(r.rol in e.roles) > 0 then 'SI' else 'no' end
order by r.tabla, r.op, r.rol;

select count(*) as celdas,
       count(*) filter (where r.resultado = case when position(r.rol in e.roles) > 0 then 'SI' else 'no' end) as coinciden,
       count(*) filter (where r.resultado <> case when position(r.rol in e.roles) > 0 then 'SI' else 'no' end) as diferencias
from resultados r join esperado e on e.tabla = r.tabla and e.op = r.op;

rollback;

select (select count(*) from public.role_permission rp join public.role r on r.id = rp.role_id
        where r.name in ('usuario_comercial','encargado_logistico','cliente')) as permisos_de_negocio_en_roles_reales_tras_rollback;
