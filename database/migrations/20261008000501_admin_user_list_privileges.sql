-- Corrige 20261008000500: la vista conservaba los privilegios de escritura que Supabase concede por
-- defecto a authenticated. Una vista de consulta solo debe tener SELECT.
revoke all on public.admin_user_list from authenticated;
grant select on public.admin_user_list to authenticated;
