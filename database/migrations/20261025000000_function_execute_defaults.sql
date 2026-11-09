-- Las funciones nuevas de public no deben quedar ejecutables por PUBLIC por defecto.
-- Las migraciones que exponen RPC deben otorgar EXECUTE explícitamente al rol necesario.
alter default privileges in schema public
  revoke execute on functions from public;

