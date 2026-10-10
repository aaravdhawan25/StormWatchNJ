-- township_domains is public, so this lookup needs no elevated rights.
alter function public.township_for_email(text) security invoker;
-- Only used inside other functions; the app reads its role from `profiles`.
revoke execute on function public.is_township() from authenticated;
