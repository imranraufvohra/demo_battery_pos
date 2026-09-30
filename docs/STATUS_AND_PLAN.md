# Status and Plan: MakeMyStore Battery & Solar POS Demo

Date: 30 Sep 2026. Based on `DEVELOPER_GUIDE_GLOBAL_BATTERY_DEMO_APP.md`.

## 1. Goal
Turn the AK Solar POS into a neutral, English, multi-currency **battery and solar shop demo** for UAE / UK / USA buyers, hosted at `demo.makemystore.online` and embedded on `/pos-system`. No AK Solar name, data or keys.

## 2. What was done (in this repo: `makemystore-pos-demo`)
The AK Solar repo was **read only and not modified**. A clean copy was made with no git history, without `MDF_IELES/`, the nested zip, the schema CSV or any `.env`.

| Guide phase | Status | Detail |
|---|---|---|
| A. Clean repo | Done | Copied without client docs. `18_fbr (1).sql` renamed to `18_fbr.sql`. Migrations moved to `supabase/migrations/`. `'AK-'` invoice prefix changed to `'INV-'` |
| B. Branding | Done | `lib/brand.ts`. Layout, sidebar, top bar, login, print text, SW cache names, offline page, AI persona name updated. Static `manifest.json` replaced by `app/manifest.ts`. **Grep for AK / Al Karam / aksolar = 0 files** |
| C1. Currency | Mostly | New `formatMoney` / `formatMoneyCompact` (Intl, from env: currency, locale, timezone). `formatRs` kept as alias so all 40 files still work. "(Rs)" labels removed. A few "Rs" strings replaced |
| C4. Wording | Partly | Nav label "Udhaar" is now "Credit / Due". Persona no longer uses Urdu/udhaar words |
| D. Module flags | Done | `lib/modules.ts`. Nav filtered. `/fbr`, `/team`, `/activity` return 404 when off (layout guards). FBR is off by default, code kept |
| G. Demo mode | Mostly | `/demo-start` page, `/api/demo-login` (server-side sign-in, optional Turnstile check), middleware redirect in demo mode, demo banner with "Get this for my business", iframe `frame-ancestors` header, no service worker and no install button inside an iframe |
| E. DB | Started | `0002_global_settings.sql` (currency, locale, tax, invoice prefix columns) |
| Checks | | `tsc --noEmit` passes. `next build` compiles and lists all routes (verified in a temp copy, because the sandbox blocks Google Fonts; Vercel will be fine) |

## 3. What is NOT done (honest list)
Nothing below was tested against a live database. **No Supabase project was created, so the app has not been run end to end.**

1. **Database reconcile (biggest risk).** The SQL files only cover 10 migrations. The CSV says 36 tables / 58 functions. Battery claims, charging, scrap, expenses, cash book, distributors are not in the SQL files. Dump the schema only (`pg_dump --schema-only`, never data) from the client's DB into `0001_base.sql`. Needs the owner's access.
2. **Generic tax (new development, about 2 days).** Update `create_invoice()`, reports, bill screen, print, PDF, share text, and add SQL tests. Only the column migration exists so far.
3. **`seed_demo()`, `reset_demo()`, pg_cron, row-cap triggers, demo user.** Not written. Needs the real schema first.
4. **Timezone is hardcoded to Karachi** in about 30 files (`todayKarachi`, `en-PK`). Dates and "today" will be wrong for UAE/UK/US visitors. Must be fixed before launch.
5. **Leftover Pakistan wording:** about 17 "Rs" strings in doc/AI files, "udhaar" in about 27 files (route `/udhaar` and labels), CNIC/NTN/province fields in about 37 files, FBR references outside FBR files (about 31, mostly harmless when flag is off, but check print and AI).
6. **Region switch (UAE/UK/USA)** is not built. Currency is currently one env value per deployment.
7. **AI:** persona default file edited only lightly. Rewrite `personas/default.md` and `knowledge/manual.md` fully, remove FBR proposals, add the per-session/IP limit and a spend cap on a new Groq key.
8. **Logo and icons** are still the old ones (the `/public/icons` set and `LogoMark`). Replace with a neutral mark.
9. **Website integration:** a starter patch is in `website-patch/` (PosDemo component). Not yet wired into the page, GA4, contact prefill, FAQ.
10. **QA:** the full test script in section 13 of the guide, iPhone Safari iframe test, load test.

Rough remaining effort: about 7 to 9 working days, most of it items 1 to 4.

## 4. Recommendations
1. **Make the `aksolar-app` GitHub repo private now.** It is public and contains the client's status docs, schema CSV and a zip. Anyone can read them. Also rotate any key that was ever in it.
2. **Get written permission** from the AK Solar owner to reuse the code as your product template (guide question 17.1). Do this before selling.
3. **Do not push this work into the `aksolar-app` repo.** Create a new private repo `makemystore-pos-demo` and push this folder there (guide rule 1). If you meant "keep updating AK Solar separately", that is fine, they stay two repos.
4. Fix the database reconcile first. Everything else depends on it.
5. Use the **shared demo DB + hourly reset** for v1, as the guide says. Move to per-visitor sandboxes only after you get leads.
6. Keep the AI on in the demo but capped (it is a selling point). Budget a small Groq cost.
7. Do not claim tax compliance for any country. Keep the "tax settings are configurable" note.
8. Set an uptime monitor on the demo. Free Supabase projects can pause.

## 5. Next steps in order
1. Private repo, push this folder. 2. New Supabase project and schema dump into `0001_base.sql`. 3. Run migrations, create demo user. 4. Write `seed_demo` / `reset_demo`. 5. Generic tax. 6. Fix timezone. 7. Deploy to `demo.` subdomain. 8. Add `website-patch/` to the website repo. 9. QA on phones. 10. Launch.
