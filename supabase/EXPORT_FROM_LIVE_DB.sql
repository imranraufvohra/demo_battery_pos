-- ============================================================================
-- RUN THIS ON THE *ORIGINAL* (LIVE) SUPABASE DATABASE. READ-ONLY. SCHEMA ONLY. NO DATA.
-- Supabase Dashboard > SQL Editor > New query > paste > Run.
-- It returns ONE cell of text. Click the cell, copy it, and save it as
--   supabase/setup/12_exported_functions_views.sql   in the demo repo.
-- It contains only the functions and views that the old SQL files do NOT already create.
-- ============================================================================
with funcs as (
  select p.proname, pg_get_functiondef(p.oid) || ';' as ddl
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')   -- skip extension functions
    and p.proname <> all (array['_core_report_summary','_core_supplier_summary','_fbr_line_figures','audit_describe','audit_row_change','audit_rs','audit_val','cancel_purchase','create_fbr_bill','create_invoice','create_purchase','create_unreported_bill','current_app_role','enforce_purchase_item_limit','import_fbr_reference','invoice_price_guard','is_owner','money_summary','my_role_info','record_payment','report_summary','role_guard','role_in','save_supplier','set_supplier_active','set_updated_at','set_user_role','supplier_summary','team_list','user_display_names'])
),
vws as (
  select v.viewname, 'create or replace view public.' || quote_ident(v.viewname) || ' as ' || v.definition as ddl
  from pg_views v
  where v.schemaname = 'public'
    and v.viewname <> all (array['invoice_balances','supplier_balances','purchase_balances','supplier_ledger'])
)
select
  E'set check_function_bodies = off;\n\n'
  || coalesce((select string_agg(ddl, E'\n\n' order by proname) from funcs), '-- no extra functions found')
  || E'\n\n'
  || coalesce((select string_agg(ddl, E'\n\n' order by viewname) from vws), '-- no extra views found')
  as export_sql;
