-- PLAT-647: activa pg_cron (si el proyecto lo permite) y programa las alertas cada hora.
-- PLAT-601: el bucket export-documents rechaza en Storage lo que la función register_export_document
-- también rechaza (10 MB, PDF/PNG/JPEG), para que no haya una ruta de subida más permisiva.

do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'No se pudo activar pg_cron: %', sqlerrm;
  end;
  if exists(select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'riexport-alerts';
    perform cron.schedule('riexport-alerts', '0 * * * *', 'select public.run_scheduled_alerts(true)');
  end if;
exception when others then
  raise notice 'pg_cron no está configurado: %', sqlerrm;
end $$;

update storage.buckets
   set file_size_limit = 10485760,
       allowed_mime_types = array['application/pdf', 'image/png', 'image/jpeg']
 where id = 'export-documents';
