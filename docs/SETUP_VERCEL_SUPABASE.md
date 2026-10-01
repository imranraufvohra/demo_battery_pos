# Setup: Supabase + Vercel (step by step)

## A. Fix the Vercel build (already done in this version)
The build failed because a stray `website-patch/` folder inside the app was compiled by TypeScript
(it imports a file that only exists in the website). It is removed, and `tsconfig.json` now ignores it.
Also removed: an old zip file, `desktop.ini`, `sada/`, `public/icons/cdcd.png` (junk file).

## B. Supabase (new project, demo data only)
1. supabase.com > New project (name `makemystore-pos-demo`). Save the DB password.
2. **Authentication > Users > Add user**: `demo@makemystore.online` + a strong password, tick **Auto Confirm**.
   Then Authentication > Sign In / Providers: turn **off** "Allow new users to sign up".
3. **SQL Editor**: run `supabase/setup/01` to `07`, one file at a time (open file, copy all, paste, Run).
4. Run `08`, `09`, `10`, `11`. (08 makes the demo user the Owner. It fails with "No Owner could be created" if step 2 was skipped.)
5. **Get the missing functions from the ORIGINAL database** (needs access to the original Supabase project):
   open it, SQL Editor, paste `supabase/EXPORT_FROM_LIVE_DB.sql`, Run. It returns one cell of text.
   Copy that cell, paste it into `supabase/setup/12_exported_functions_views.sql` (replace everything), then run that file in the NEW project.
   It is read-only and contains no data, only code for about 31 functions and 5 views.
6. Run `13`, `14`, `15`.
7. Load the demo data: SQL Editor > `select public.reset_demo();`
8. Hourly reset: Database > Extensions > enable **pg_cron**, then run:
   `select cron.schedule('reset-demo-hourly','0 * * * *','select public.reset_demo()');`
9. Settings > API: copy **Project URL** and the **anon public** key.
10. Authentication > URL Configuration: set Site URL to your Vercel URL (later `https://demo.makemystore.online`).

Without step 5 the app opens, but these features will error: cancel/delete invoice, expenses, battery claims,
charging jobs, scrap sales, cash book, financial report, supplier payments, AI actions.

## C. Vercel
1. Push this folder to your GitHub repo (replace old files). Vercel > Add New > Project > import the repo. Framework: Next.js (auto).
2. Settings > Environment Variables (Production AND Preview):

| Name | Value |
|---|---|
| NEXT_PUBLIC_SUPABASE_URL | from step B9 |
| NEXT_PUBLIC_SUPABASE_ANON_KEY | from step B9 |
| NEXT_PUBLIC_DEMO_MODE | true |
| DEMO_USER_EMAIL | demo@makemystore.online |
| DEMO_USER_PASSWORD | the password from B2 |
| NEXT_PUBLIC_CURRENCY | USD (or AED / GBP) |
| NEXT_PUBLIC_LOCALE | en-US (or en-GB / en-AE) |
| NEXT_PUBLIC_TIMEZONE | UTC (or America/New_York, Europe/London, Asia/Dubai) |
| NEXT_PUBLIC_AI_ENABLED | false until you add a Groq key |
| NEXT_PUBLIC_WEBSITE_URL | https://www.makemystore.online |

   Optional: GROQ_API_KEY (then set NEXT_PUBLIC_AI_ENABLED=true), TURNSTILE_SECRET_KEY + NEXT_PUBLIC_TURNSTILE_SITE_KEY.
   `NEXT_PUBLIC_*` values are baked in at build time: after changing one, **Redeploy**.
3. Deploy. Open `https://<your-app>.vercel.app` : you should land on **Start demo**; click it and you are in the dashboard.
4. Domain: add `demo.makemystore.online` in Vercel > Domains and the CNAME it shows in your DNS.

## D. If something fails
| Symptom | Fix |
|---|---|
| Build error mentioning a file path | Send the first red error lines |
| Page says "Setup needed: the Supabase settings are missing" | Env vars missing or not redeployed |
| "Could not start the demo" | DEMO_USER_* wrong, user not confirmed, or Site URL not set |
| Dashboard empty | Step B7 not run |
| Blank screens / errors when saving | Step B5 not done |
