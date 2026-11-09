-- Mantiene vinculados los números reservados con la serie/año que controla su consecutivo.
do $$
begin
  if exists (
    select 1
    from public.document_number dn
    left join public.document_sequence ds
      on ds.document_type = dn.document_type
     and ds.series_year = dn.series_year
    where ds.document_type is null
  ) then
    raise exception
      'Hay números de documento sin serie/año en document_sequence; corrige esos datos antes de aplicar esta migración.';
  end if;
end $$;

alter table public.document_sequence
  drop constraint if exists document_sequence_type_check;
alter table public.document_sequence
  add constraint document_sequence_type_check
  check (document_type in ('commercial_invoice', 'packing_list', 'eur1_certificate'));

alter table public.document_number
  drop constraint if exists document_number_sequence_fk;
alter table public.document_number
  add constraint document_number_sequence_fk
  foreign key (document_type, series_year)
  references public.document_sequence (document_type, series_year)
  on update restrict
  on delete restrict;
