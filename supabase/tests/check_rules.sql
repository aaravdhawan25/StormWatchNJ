-- Rule checks for the StormWatch NJ database.
--
-- Run in the Supabase SQL editor. Everything happens inside one DO block that
-- ends by raising an exception carrying the results, so the whole thing rolls
-- back: no test accounts or hazards are left behind, and because the users are
-- inserted directly, no emails are sent. A passing run reads
-- "RESULTS: N passed, 0 failed".

do $$
declare
    passed int := 0; failed int := 0; failures text := '';
    bo uuid := gen_random_uuid(); cy uuid := gen_random_uuid(); di uuid := gen_random_uuid();
    ed uuid := gen_random_uuid(); town uuid := gen_random_uuid(); pending uuid := gen_random_uuid();
    h uuid; h2 uuid; h3 uuid; r jsonb; ok boolean; n int;
begin
    -- "Acting as" a user below means setting request.jwt.claims, which is what
    -- auth.uid() reads.
    insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_user_meta_data) values
        (bo,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bo@example.com',  now(), '{}'),
        (cy,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cy@example.com',  now(), '{}'),
        (di,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'di@example.com',  now(), '{}'),
        (ed,  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ed@example.com',  now(), '{}'),
        (town,'00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dpw@princetonnj.gov', now(), '{"account_type":"township"}'),
        (pending,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','clerk@plainsboronj.com', null, '{"account_type":"township"}');

    -- ---- township rules -------------------------------------------------
    ok := (select role = 'township' and township = 'Princeton' from public.profiles where id = town);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | confirmed township gets role'; end if;

    ok := (select role = 'resident' from public.profiles where id = pending);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | unconfirmed township stays resident'; end if;

    update auth.users set email_confirmed_at = now() where id = pending;
    ok := (select role = 'township' and township = 'Plainsboro Township' from public.profiles where id = pending);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | confirming email grants township'; end if;

    -- A resident on a municipal domain who never asked is not promoted.
    ok := (select role = 'resident' from public.profiles where id = bo);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | resident default'; end if;

    -- Claiming township later without a municipal email changes nothing.
    update auth.users set raw_user_meta_data = '{"account_type":"township"}' where id = cy;
    ok := (select role = 'resident' from public.profiles where id = cy);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | metadata alone does not grant township'; end if;

    -- Moving off the municipal domain drops the role.
    update auth.users set email = 'dpw@gmail.com' where id = pending;
    ok := (select role = 'resident' and township is null from public.profiles where id = pending);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | leaving domain drops township'; end if;

    foreach r in array array[
        '{"e":"mayor@gmail.com"}', '{"e":"a@princetonnj.gov.example.com"}', '{"e":"a@notprincetonnj.gov"}',
        '{"e":"a@mail.princetonnj.gov"}', '{"e":"a@princetonnj.gov@example.com"}']::jsonb[] loop
        begin
            insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
            values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
                    r ->> 'e', '{"account_type":"township"}');
            failed := failed + 1; failures := failures || ' | township signup accepted: ' || (r ->> 'e');
        exception when sqlstate 'P0001' then passed := passed + 1;
        end;
    end loop;

    ok := public.township_for_email('  Clerk@PlainsboroNJ.com ') = 'Plainsboro Township';
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | domain match ignores case'; end if;

    -- ---- reporting ------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', bo)::text, true);
    r := public.report_hazard('DOWNED_TREE', 'IMPASSABLE', 'IMPASSABLE', false, 'Oak across both lanes.', 40.3318, -74.5893, '12 Dey Rd', '08536', 'Plainsboro');
    h := (r ->> 'id')::uuid;
    ok := not (r ->> 'duplicate')::boolean and (select owner_id = bo from public.hazards where id = h);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | report stores owner'; end if;

    perform set_config('request.jwt.claims', json_build_object('sub', cy)::text, true);
    r := public.report_hazard('DOWNED_TREE', 'LOW', 'CLEAR_TO_PASS', false, 'Same tree.', 40.33185, -74.58935);
    ok := (r ->> 'duplicate')::boolean and (r ->> 'id')::uuid = h and (select upvotes = 2 from public.hazards where id = h);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | nearby duplicate becomes confirmation'; end if;

    r := public.report_hazard('STREET_FLOODING', 'LOW', 'CLEAR_TO_PASS', false, 'Different kind, same spot.', 40.33185, -74.58935);
    ok := not (r ->> 'duplicate')::boolean;
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | different type is not a duplicate'; end if;

    begin
        perform public.report_hazard('OTHER', 'LOW', 'CLEAR_TO_PASS', false, 'Cupertino', 37.33, -122.0);
        failed := failed + 1; failures := failures || ' | out-of-state accepted';
    exception when sqlstate 'P0001' then passed := passed + 1;
    end;

    -- Assigned first: called inside the WHERE clause, the function would run
    -- during a scan that cannot see the row it just inserted.
    r := public.report_hazard('DOWNED_WIRE', 'LOW', 'CLEAR_TO_PASS', false, 'Wire', 40.40, -74.50);
    ok := (select utility_lines_involved from public.hazards where id = (r ->> 'id')::uuid);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | downed wire implies utility lines'; end if;

    -- ---- listing --------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', bo)::text, true);
    ok := (select is_mine from public.list_hazards() where id = h);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | reporter sees is_mine'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub', cy)::text, true);
    ok := (select not is_mine from public.list_hazards() where id = h);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | others do not see is_mine'; end if;

    -- ---- the three-vote rule -------------------------------------------
    perform set_config('request.jwt.claims', '{}', true);
    begin perform public.vote_not_there(h); failed := failed + 1; failures := failures || ' | anonymous vote accepted';
    exception when sqlstate '42501' then passed := passed + 1; end;

    perform set_config('request.jwt.claims', json_build_object('sub', bo)::text, true);
    begin perform public.vote_not_there(h); failed := failed + 1; failures := failures || ' | reporter voted on own';
    exception when sqlstate 'P0001' then passed := passed + 1; end;

    perform set_config('request.jwt.claims', json_build_object('sub', cy)::text, true);
    begin perform public.remove_hazard(h); failed := failed + 1; failures := failures || ' | stranger removed hazard';
    exception when sqlstate '42501' then passed := passed + 1; end;

    r := public.vote_not_there(h); r := public.vote_not_there(h);
    ok := (r ->> 'not_there_votes')::int = 1 and not (r ->> 'removed')::boolean;
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | double vote counted twice'; end if;

    ok := (select not_there_votes = 1 and i_voted_not_there from public.list_hazards() where id = h);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | list shows my vote'; end if;

    perform set_config('request.jwt.claims', json_build_object('sub', di)::text, true);
    r := public.vote_not_there(h);
    ok := (r ->> 'not_there_votes')::int = 2 and not (r ->> 'removed')::boolean and exists (select 1 from public.hazards where id = h);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | removed after only 2 votes'; end if;

    perform set_config('request.jwt.claims', json_build_object('sub', ed)::text, true);
    r := public.vote_not_there(h);
    ok := (r ->> 'removed')::boolean and not exists (select 1 from public.hazards where id = h)
          and not exists (select 1 from public.hazard_votes where hazard_id = h)
          and (select reason = 'community' from public.removed_hazards where id = h);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | third vote did not remove + audit'; end if;

    begin perform public.vote_not_there(h); failed := failed + 1; failures := failures || ' | vote on removed hazard';
    exception when sqlstate 'P0002' then passed := passed + 1; end;

    -- ---- reporter and township removal ---------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', bo)::text, true);
    h2 := ((public.report_hazard('CLOGGED_DRAIN', 'MODERATE', 'ONE_LANE_OPEN', false, 'Drain', 40.35, -74.60)) ->> 'id')::uuid;
    perform public.remove_hazard(h2);
    ok := not exists (select 1 from public.hazards where id = h2)
          and (select reason = 'reporter' and removed_by = bo from public.removed_hazards where id = h2);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | reporter removal'; end if;

    h3 := ((public.report_hazard('OTHER', 'LOW', 'CLEAR_TO_PASS', false, 'Debris', 40.37, -74.62)) ->> 'id')::uuid;
    perform set_config('request.jwt.claims', json_build_object('sub', cy)::text, true);
    begin perform public.set_hazard_status(h3, 'IN_PROGRESS'); failed := failed + 1; failures := failures || ' | resident set crew status';
    exception when sqlstate '42501' then passed := passed + 1; end;

    perform set_config('request.jwt.claims', json_build_object('sub', town)::text, true);
    perform public.set_hazard_status(h3, 'IN_PROGRESS');
    ok := (select status = 'IN_PROGRESS' from public.hazards where id = h3);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | township set crew status'; end if;

    perform public.remove_hazard(h3);
    ok := (select reason = 'township' from public.removed_hazards where id = h3);
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | township removal'; end if;

    -- ---- who may call what ---------------------------------------------
    ok := not has_function_privilege('anon', 'public.list_hazards()', 'execute')
      and not has_function_privilege('anon', 'public.vote_not_there(uuid)', 'execute')
      and not has_function_privilege('anon', 'public.remove_hazard(uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.archive_and_delete_hazard(uuid, text, uuid)', 'execute')
      and not has_function_privilege('authenticated', 'public.sync_profile()', 'execute')
      and has_function_privilege('authenticated', 'public.vote_not_there(uuid)', 'execute')
      and has_function_privilege('anon', 'public.township_for_email(text)', 'execute');
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | function grants'; end if;

    ok := not has_table_privilege('anon', 'public.hazards', 'select') or
          not exists (select 1 from pg_policies where schemaname = 'public' and tablename in
                      ('hazards', 'hazard_votes', 'removed_hazards', 'dispatch_towns'));
    if ok then passed := passed + 1; else failed := failed + 1; failures := failures || ' | private tables have no policies'; end if;

    raise exception 'RESULTS: % passed, % failed%', passed, failed, failures;
end $$;
