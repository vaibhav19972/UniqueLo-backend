-- Corrected security check.
--
-- The first version used `prosrc like '%payment_ref%'`, which matched the
-- COMMENT inside the function body ("payment_ref is NOT written here...") and
-- reported a false INSECURE. Match only an actual READ of the value.
select 'reads_payment_ref_from_json' as check,
       case when prosrc ~* 'p_order\s*(->>|->)\s*''payment_ref'''
            then 'YES - INSECURE' else 'no - correct' end as detail
  from pg_proc
 where proname = 'place_order' and pronamespace = 'public'::regnamespace
union all
select 'writes_payment_method_to_orders',
       case when prosrc ~* 'insert into public\.orders' and prosrc ~* 'payment_method'
            then 'YES' else 'NO - STALE DEFINITION' end
  from pg_proc
 where proname = 'place_order' and pronamespace = 'public'::regnamespace
union all
select 'comment_only_mentions',
       substring(prosrc from '[^\n]*payment_ref[^\n]*')
  from pg_proc
 where proname = 'place_order' and pronamespace = 'public'::regnamespace;
