-- Global settings for the demo. STARTING POINT: verify against the real schema after 0001 is reconciled.
alter table public.business_profile
  add column if not exists currency text not null default 'USD',
  add column if not exists locale text not null default 'en-US',
  add column if not exists country text not null default 'US',
  add column if not exists tax_label text not null default 'VAT',
  add column if not exists tax_rate numeric not null default 0,
  add column if not exists tax_id_label text not null default 'Tax ID',
  add column if not exists tax_id text,
  add column if not exists invoice_prefix text not null default 'INV-';

alter table public.business_profile
  alter column business_name set default 'PowerCell Batteries & Solar';

alter table public.invoices
  add column if not exists subtotal numeric,
  add column if not exists tax_amount numeric not null default 0,
  add column if not exists tax_rate_applied numeric not null default 0;

-- TODO (not done): update create_invoice() to compute tax server-side; update report_summary /
-- _core_report_summary / financial_summary to show tax collected; add reset_demo(), seed_demo(),
-- row-cap triggers. See docs/STATUS_AND_PLAN.md.
