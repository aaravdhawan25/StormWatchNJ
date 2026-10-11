-- Lets the server functions read a named secret from Supabase Vault, where it is
-- stored encrypted. Callable only with the service-role key, which exists only
-- on the server: app users, signed in or not, cannot call it.
--
-- The OpenAI key itself is NOT in this repository. It is stored once, by hand:
--   select vault.create_secret('<key>', 'openai_api_key');
create or replace function public.server_secret(p_name text)
returns text
language sql stable security definer set search_path = ''
as $$
    select s.decrypted_secret from vault.decrypted_secrets s where s.name = p_name limit 1;
$$;

revoke execute on function public.server_secret(text) from public, anon, authenticated;
grant execute on function public.server_secret(text) to service_role;
