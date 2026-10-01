# Status and Plan (updated)

## Done
- Clean, branded demo app (no client name in code, SQL or docs). Builds on Vercel (fixed: stray `website-patch/` folder broke type-checking).
- Money: `formatMoney` from env (currency/locale/timezone). Karachi timezone and `en-PK` removed from code and SQL (now env/UTC). Phone placeholders and WhatsApp country code are generic.
- Module flags: FBR/Team/Activity hidden and blocked by URL in demo mode.
- Demo mode: Start page, server-side demo login, banner, iframe permission.
- **Supabase schema**: ordered `supabase/setup/` folder. Tested on a real Postgres 16 with a Supabase-style stub: runs with zero errors. Policies (38) and triggers (49) match your schema CSV exactly.
- **Seed + reset**: `seed_demo()` and `reset_demo()` (20 products, 8 customers, 17 bills, payments, 3 purchases, 10 expenses, 5 claims, 4 charging jobs, 3 scrap). Uses the app's own functions. Verified: sales total equals line-item total, no negative stock, 6 low-stock alerts, reset works twice, owner sees data, unknown user sees nothing.
- Export query for the missing live-database functions (`supabase/EXPORT_FROM_LIVE_DB.sql`), tested.

## Still needed from you (cannot be done without database access)
1. Run `EXPORT_FROM_LIVE_DB.sql` on the original database and save the result as `setup/12_exported_functions_views.sql`. The old schema CSV only has function names, not their code, so 28 functions (+3 the CSV never listed) and 5 views cannot be recreated reliably from the files.
2. Click-through test on the real Supabase + Vercel (nothing here ran against real Supabase).

## Not done yet
- Generic tax (VAT/sales tax) inside `create_invoice()` and reports (columns exist, logic not written).
- UAE/UK/US region switch (currency is one value per deployment now).
- Remaining Pakistan wording: "udhaar" route and labels, CNIC/NTN/province fields, FBR mentions in print/AI, expense methods `easypaisa`/`jazzcash` (DB check constraint + UI).
- Full AI persona/knowledge rewrite, new logo and icons.
- Website: wire `PosDemo` into `/pos-system` (starter component in the separate website patch).
- Phone/device QA, iPhone Safari iframe test.
