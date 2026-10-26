-- township_domains is public, so this lookup needs no elevated rights
alter function public.township_for_email(text) security invoker;
-- only used inside other functions
revoke execute on function public.is_township() from authenticated;
