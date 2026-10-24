-- Keep is_admin() out of the public API; policies keep working (they reference the function itself)
create schema if not exists private;
grant usage on schema private to anon, authenticated;
alter function public.is_admin() set schema private;
revoke all on function private.is_admin() from public;
grant execute on function private.is_admin() to anon, authenticated;
