# Supabase setup

Run the files in `supabase/setup/` **in number order** in Supabase > SQL Editor (paste, Run, next).
Full step-by-step guide: `docs/SETUP_VERCEL_SUPABASE.md`.

| # | File | Note |
|---|---|---|
| 01-03 | inventory, customers, invoices | |
| 04 | missing_tables | tables that were not in the old SQL files (generated from the schema CSV) |
| 05-07 | reports, suppliers/purchases, supplier_save | |
| (!) | **Create the demo user in Authentication > Users first** | file 08 makes the first user the Owner |
| 08-11 | roles/audit, role enforcement, FBR (kept, switched off in the app) | |
| 12 | exported_functions_views | **you create this file** with `EXPORT_FROM_LIVE_DB.sql` run on the ORIGINAL database |
| 13 | missing_policies_triggers | |
| 14 | global_settings | currency, locale, tax columns |
| 15 | seed_and_reset_demo | then run `select public.reset_demo();` |

`EXPORT_FROM_LIVE_DB.sql` is read-only and exports schema only (function bodies and views). No data.
