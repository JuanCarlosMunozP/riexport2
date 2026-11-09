-- Verifica que las claves foráneas estén validadas y que los números de documento
-- no queden desligados de su serie/año.
do $$
begin
  if exists (
    select 1
    from pg_constraint
    where connamespace = 'public'::regnamespace
      and contype = 'f'
      and not convalidated
  ) then
    raise exception 'Hay claves foráneas de public que aún no están validadas.';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where connamespace = 'public'::regnamespace
      and conrelid = 'public.document_number'::regclass
      and confrelid = 'public.document_sequence'::regclass
      and conname = 'document_number_sequence_fk'
      and contype = 'f'
      and convalidated
  ) then
    raise exception 'Falta la clave foránea validada entre document_number y document_sequence.';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where connamespace = 'public'::regnamespace
      and conrelid = 'public.document_sequence'::regclass
      and conname = 'document_sequence_type_check'
      and contype = 'c'
      and convalidated
  ) then
    raise exception 'Falta la restricción validada de tipos de documento en document_sequence.';
  end if;

  if exists (
    select 1
    from public.document_number dn
    left join public.document_sequence ds
      on ds.document_type = dn.document_type
     and ds.series_year = dn.series_year
    where ds.document_type is null
  ) then
    raise exception 'Hay números de documento huérfanos en public.document_number.';
  end if;
end $$;
