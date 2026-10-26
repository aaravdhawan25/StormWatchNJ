-- read a secret from Supabase Vault (server only)
create or replace function public.server_secret(p_name text)
returns text
language sql stable security definer set search_path = ''
as $$
    select s.decrypted_secret from vault.decrypted_secrets s where s.name = p_name limit 1;
$$;

revoke execute on function public.server_secret(text) from public, anon, authenticated;
grant execute on function public.server_secret(text) to service_role;
