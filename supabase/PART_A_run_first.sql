-- ======== 01_inventory.sql ========
-- PowerCell POS App, Phase 1: inventory table
-- Run this once in Supabase: SQL Editor > New query > paste all > Run.
-- It is safe to run again; it will not delete existing stock.

create table if not exists public.inventory (
  id              uuid primary key default gen_random_uuid(),
  category        text not null check (category in ('battery', 'panel', 'accessory')),
  brand           text not null,
  model           text not null,
  type            text,                       -- battery: Lithium/Tubular/Lead-acid/Dry; panel and accessory: free text
  voltage         numeric(6,2)  check (voltage is null or voltage > 0),
  plates          integer       check (plates is null or plates > 0),
  ah_rating       numeric(8,2)  check (ah_rating is null or ah_rating > 0),
  wattage         integer       check (wattage is null or wattage > 0),
  warranty_months integer       check (warranty_months is null or warranty_months > 0),
  cost_price      numeric(12,2) not null default 0 check (cost_price >= 0),
  sale_price      numeric(12,2) not null default 0 check (sale_price >= 0),
  quantity        integer       not null default 0 check (quantity >= 0),
  reorder_level   integer       not null default 0 check (reorder_level >= 0),
  -- FBR-ready fields, used by invoices in Phase 3
  hs_code         text check (hs_code is null or hs_code ~ '^[0-9]{4}\.[0-9]{4}$'),
  uom             text not null default 'Numbers, pieces, units',
  created_by      uuid default auth.uid() references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists inventory_category_idx on public.inventory (category);
create index if not exists inventory_brand_model_idx on public.inventory (lower(brand), lower(model));

-- Keep updated_at correct on every edit
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists inventory_set_updated_at on public.inventory;
create trigger inventory_set_updated_at
  before update on public.inventory
  for each row execute function public.set_updated_at();

-- Security: only signed-in users can touch inventory. Nobody else can see it.
-- (Phase 8 will refine this into Owner / Staff / Accountant permissions.)
alter table public.inventory enable row level security;

revoke all on public.inventory from anon;
grant select, insert, update, delete on public.inventory to authenticated;

drop policy if exists "Signed-in users can view inventory"   on public.inventory;
drop policy if exists "Signed-in users can add inventory"    on public.inventory;
drop policy if exists "Signed-in users can edit inventory"   on public.inventory;
drop policy if exists "Signed-in users can delete inventory" on public.inventory;

create policy "Signed-in users can view inventory"
  on public.inventory for select to authenticated using (true);

create policy "Signed-in users can add inventory"
  on public.inventory for insert to authenticated with check (true);

create policy "Signed-in users can edit inventory"
  on public.inventory for update to authenticated using (true) with check (true);

create policy "Signed-in users can delete inventory"
  on public.inventory for delete to authenticated using (true);

-- ======== 02_customers.sql ========
-- PowerCell POS App, Phase 2: customers table
-- Run this once in Supabase: SQL Editor > New query > paste all > Run.
-- Safe to run again; it will not delete existing customers.
-- (If you already ran your original 02_customers.sql, you do NOT need to run this copy.)

create table if not exists public.customers (
  id                uuid primary key default gen_random_uuid(),
  name              text not null check (char_length(name) between 1 and 120),
  phone             text check (phone is null or phone ~ '^\+?[0-9]{10,15}$'),
  address           text,
  registration_type text not null default 'Unregistered' check (registration_type in ('Registered', 'Unregistered')),
  cnic_or_ntn       text check (cnic_or_ntn is null or cnic_or_ntn ~ '^([0-9]{7}|[0-9]{13})$'),
  created_by        uuid default auth.uid() references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint customers_registered_needs_number
    check (registration_type <> 'Registered' or cnic_or_ntn is not null)
);

create index if not exists customers_name_idx on public.customers (lower(name));
create index if not exists customers_phone_idx on public.customers (phone);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists customers_set_updated_at on public.customers;
create trigger customers_set_updated_at
  before update on public.customers
  for each row execute function public.set_updated_at();

alter table public.customers enable row level security;

revoke all on public.customers from anon;
grant select, insert, update, delete on public.customers to authenticated;

drop policy if exists "Signed-in users can view customers"   on public.customers;
drop policy if exists "Signed-in users can add customers"    on public.customers;
drop policy if exists "Signed-in users can edit customers"   on public.customers;
drop policy if exists "Signed-in users can delete customers" on public.customers;

create policy "Signed-in users can view customers"
  on public.customers for select to authenticated using (true);
create policy "Signed-in users can add customers"
  on public.customers for insert to authenticated with check (true);
create policy "Signed-in users can edit customers"
  on public.customers for update to authenticated using (true) with check (true);
create policy "Signed-in users can delete customers"
  on public.customers for delete to authenticated using (true);

-- ======== 03_invoices.sql ========
-- PowerCell POS App, Phase 3: invoicing core (FBR-shaped data)
-- Run this once in Supabase: SQL Editor > New query > paste all > Run.
-- Run 01_inventory.sql and 02_customers.sql first. Safe to run again.
--
-- How it works:
--  * Bills are saved ONLY through the functions create_invoice() and record_payment().
--    The browser cannot insert or edit invoices, items or payments directly.
--  * create_invoice() saves the bill, its lines, the payment and the stock decrease in ONE
--    transaction. If anything fails, nothing is saved and stock stays as it was.
--  * Customer and item details are copied (snapshotted) onto the bill, so old bills never change.
--  * Customers and items that have bills cannot be deleted (on delete restrict).

-- ---------------------------------------------------------------- seller details (FBR needs these later)
create table if not exists public.business_profile (
  id            boolean primary key default true check (id),   -- always exactly one row
  business_name text not null default 'PowerCell Batteries & Solar',
  ntn           text check (ntn is null or ntn ~ '^([0-9]{7}|[0-9]{13})$'),
  address       text,
  province      text,
  phone         text,
  updated_at    timestamptz not null default now()
);
insert into public.business_profile (id) values (true) on conflict (id) do nothing;

-- ---------------------------------------------------------------- invoices
create sequence if not exists public.invoice_number_seq;

create table if not exists public.invoices (
  id                      uuid primary key default gen_random_uuid(),
  invoice_number          text not null unique
                            default ('INV-' || lpad(nextval('public.invoice_number_seq')::text, 6, '0')),
  invoice_type            text not null default 'Sale Invoice' check (invoice_type in ('Sale Invoice', 'Debit Note')),
  invoice_date            date not null,
  customer_id             uuid references public.customers (id) on delete restrict,   -- null = walk-in
  -- snapshot of the buyer at the time of sale
  buyer_name              text not null,
  buyer_registration_type text not null default 'Unregistered' check (buyer_registration_type in ('Registered', 'Unregistered')),
  buyer_cnic_or_ntn       text check (buyer_cnic_or_ntn is null or buyer_cnic_or_ntn ~ '^([0-9]{7}|[0-9]{13})$'),
  buyer_address           text,
  buyer_phone             text,
  note                    text,                                    -- vehicle or any note
  total_value             numeric(14,2) not null check (total_value >= 0),
  status                  text not null default 'Valid' check (status in ('Valid', 'Cancelled', 'Edited')),
  payment_status          text not null check (payment_status in ('Paid', 'Partial', 'Credit')),
  created_by              uuid default auth.uid() references auth.users (id) on delete set null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint invoices_registered_buyer_needs_number
    check (buyer_registration_type <> 'Registered' or buyer_cnic_or_ntn is not null)
);
create index if not exists invoices_customer_idx on public.invoices (customer_id);
create index if not exists invoices_date_idx on public.invoices (invoice_date desc);
create index if not exists invoices_created_idx on public.invoices (created_at desc);

-- ---------------------------------------------------------------- invoice lines
create table if not exists public.invoice_items (
  id              uuid primary key default gen_random_uuid(),
  invoice_id      uuid not null references public.invoices (id) on delete cascade,
  inventory_id    uuid not null references public.inventory (id) on delete restrict,
  -- snapshot of the item at the time of sale
  description     text not null,
  hs_code         text,
  uom             text not null,
  sale_type       text not null default 'Goods at standard rate (default)',
  cost_price      numeric(12,2) not null default 0,
  quantity        integer not null check (quantity > 0),
  rate            numeric(12,2) not null check (rate >= 0),
  value_excl_tax  numeric(14,2) not null check (value_excl_tax >= 0),
  sales_tax_rate  numeric(5,2)  not null default 0 check (sales_tax_rate >= 0),
  sales_tax       numeric(14,2) not null default 0 check (sales_tax >= 0),   -- filled when FBR is connected (Phase 9)
  total           numeric(14,2) not null check (total >= 0),
  created_at      timestamptz not null default now()
);
create index if not exists invoice_items_invoice_idx on public.invoice_items (invoice_id);
create index if not exists invoice_items_inventory_idx on public.invoice_items (inventory_id);

-- ---------------------------------------------------------------- payments (real udhaar balances)
create table if not exists public.payments (
  id           uuid primary key default gen_random_uuid(),
  invoice_id   uuid not null references public.invoices (id) on delete restrict,
  amount       numeric(14,2) not null check (amount > 0),
  method       text not null default 'cash' check (method in ('cash', 'bank', 'other')),
  paid_at      timestamptz not null default now(),
  received_by  uuid default auth.uid() references auth.users (id) on delete set null,
  note         text
);
create index if not exists payments_invoice_idx on public.payments (invoice_id);
create index if not exists payments_paid_at_idx on public.payments (paid_at desc);

drop trigger if exists invoices_set_updated_at on public.invoices;
create trigger invoices_set_updated_at
  before update on public.invoices
  for each row execute function public.set_updated_at();

drop trigger if exists business_profile_set_updated_at on public.business_profile;
create trigger business_profile_set_updated_at
  before update on public.business_profile
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------- security (placeholder until Phase 8)
alter table public.business_profile enable row level security;
alter table public.invoices        enable row level security;
alter table public.invoice_items   enable row level security;
alter table public.payments        enable row level security;

revoke all on public.business_profile, public.invoices, public.invoice_items, public.payments from anon;
revoke all on public.business_profile, public.invoices, public.invoice_items, public.payments from authenticated;
-- Signed-in users can only READ. All writing goes through the functions below.
grant select on public.business_profile, public.invoices, public.invoice_items, public.payments to authenticated;

drop policy if exists "Signed-in users can view business profile" on public.business_profile;
drop policy if exists "Signed-in users can view invoices"         on public.invoices;
drop policy if exists "Signed-in users can view invoice items"    on public.invoice_items;
drop policy if exists "Signed-in users can view payments"         on public.payments;

create policy "Signed-in users can view business profile" on public.business_profile for select to authenticated using (true);
create policy "Signed-in users can view invoices"         on public.invoices         for select to authenticated using (true);
create policy "Signed-in users can view invoice items"    on public.invoice_items    for select to authenticated using (true);
create policy "Signed-in users can view payments"         on public.payments         for select to authenticated using (true);

-- ---------------------------------------------------------------- views used by the screens
-- security_invoker = the viewer's own permissions apply.
create or replace view public.invoice_balances
with (security_invoker = true) as
select
  i.*,
  coalesce(p.paid, 0)                     as paid_total,
  i.total_value - coalesce(p.paid, 0)     as due_total
from public.invoices i
left join (
  select invoice_id, sum(amount) as paid from public.payments group by invoice_id
) p on p.invoice_id = i.id;

grant select on public.invoice_balances to authenticated;
revoke all on public.invoice_balances from anon;

-- ---------------------------------------------------------------- create_invoice
-- p_items is a JSON list: [{"inventory_id": "...", "quantity": 2, "rate": 15500}, ...]
-- Totals are calculated here from quantity x rate. Nothing typed by a person or an AI is trusted.
create or replace function public.create_invoice(
  p_customer_id  uuid,
  p_walkin_name  text,
  p_note         text,
  p_invoice_date date,
  p_items        jsonb,
  p_paid         numeric,
  p_method       text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'UTC')::date;
  v_date      date;
  v_cust      public.customers%rowtype;
  v_inv       public.inventory%rowtype;
  v_line      record;
  v_id        uuid;
  v_total     numeric(14,2) := 0;
  v_paid      numeric(14,2) := coalesce(p_paid, 0);
  v_line_val  numeric(14,2);
  v_method    text := coalesce(nullif(p_method, ''), 'cash');
  v_seller    text;
  v_name      text;
  v_status    text;
begin
  if v_uid is null then
    raise exception 'Please sign in again.';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one item to the bill.';
  end if;

  v_date := coalesce(p_invoice_date, v_today);
  if v_date > v_today then
    raise exception 'The bill date cannot be in the future.';
  end if;

  if v_method not in ('cash', 'bank', 'other') then
    raise exception 'Choose cash, bank or other as the payment method.';
  end if;

  -- Buyer snapshot
  if p_customer_id is not null then
    select * into v_cust from public.customers where id = p_customer_id;
    if not found then
      raise exception 'That customer no longer exists. Choose the customer again.';
    end if;
    v_name := v_cust.name;
  else
    v_name := coalesce(nullif(btrim(p_walkin_name), ''), 'Walk-in customer');
  end if;

  -- FBR rule: buyer and seller must not be the same registration number
  select ntn into v_seller from public.business_profile where id;
  if v_seller is not null and p_customer_id is not null and v_cust.cnic_or_ntn = v_seller then
    raise exception 'The buyer''s CNIC/NTN is the same as the shop''s NTN. A shop cannot bill itself.';
  end if;

  -- Check the lines first (also finds repeated items)
  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(inventory_id uuid, quantity integer, rate numeric)
    where x.inventory_id is null or x.quantity is null or x.quantity <= 0 or x.rate is null or x.rate < 0
  ) then
    raise exception 'Each item needs a quantity of 1 or more and a price of 0 or more.';
  end if;

  if (
    select count(*) - count(distinct x.inventory_id)
    from jsonb_to_recordset(p_items) as x(inventory_id uuid, quantity integer, rate numeric)
  ) > 0 then
    raise exception 'The same item appears twice on the bill. Combine it into one line.';
  end if;

  -- Total, calculated from quantity x rate
  select coalesce(sum(round(x.quantity * round(x.rate, 2), 2)), 0)
    into v_total
  from jsonb_to_recordset(p_items) as x(inventory_id uuid, quantity integer, rate numeric);

  if v_total <= 0 then
    raise exception 'The bill total is zero. Check the prices.';
  end if;

  if v_paid < 0 or v_paid > v_total then
    raise exception 'The amount paid must be between 0 and the bill total.';
  end if;

  if v_paid < v_total and p_customer_id is null then
    raise exception 'Udhaar needs a customer. Choose a customer, or take the full payment.';
  end if;

  v_status := case when v_paid >= v_total then 'Paid' when v_paid = 0 then 'Credit' else 'Partial' end;

  insert into public.invoices (
    invoice_date, customer_id, buyer_name, buyer_registration_type, buyer_cnic_or_ntn,
    buyer_address, buyer_phone, note, total_value, payment_status
  ) values (
    v_date, p_customer_id, v_name,
    coalesce(v_cust.registration_type, 'Unregistered'), v_cust.cnic_or_ntn,
    v_cust.address, v_cust.phone, nullif(btrim(p_note), ''), v_total, v_status
  )
  returning id into v_id;

  -- Lines and stock, in a fixed order so two bills at once cannot deadlock
  for v_line in
    select x.inventory_id, x.quantity, round(x.rate, 2) as rate
    from jsonb_to_recordset(p_items) as x(inventory_id uuid, quantity integer, rate numeric)
    order by x.inventory_id
  loop
    select * into v_inv from public.inventory where id = v_line.inventory_id for update;
    if not found then
      raise exception 'An item on this bill no longer exists. Refresh and try again.';
    end if;
    if v_inv.quantity < v_line.quantity then
      raise exception 'Only % of % left in stock. Lower the quantity and try again.',
        v_inv.quantity, v_inv.brand || ' ' || v_inv.model;
    end if;

    update public.inventory set quantity = quantity - v_line.quantity where id = v_inv.id;

    v_line_val := round(v_line.quantity * v_line.rate, 2);
    insert into public.invoice_items (
      invoice_id, inventory_id, description, hs_code, uom, cost_price,
      quantity, rate, value_excl_tax, total
    ) values (
      v_id, v_inv.id,
      v_inv.brand || ' ' || v_inv.model || coalesce(', ' || nullif(v_inv.type, ''), ''),
      v_inv.hs_code, v_inv.uom, v_inv.cost_price,
      v_line.quantity, v_line.rate, v_line_val, v_line_val
    );
  end loop;

  if v_paid > 0 then
    insert into public.payments (invoice_id, amount, method) values (v_id, v_paid, v_method);
  end if;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------- record_payment (collect udhaar later)
create or replace function public.record_payment(
  p_invoice_id uuid,
  p_amount     numeric,
  p_method     text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv    public.invoices%rowtype;
  v_paid   numeric(14,2);
  v_amount numeric(14,2) := round(coalesce(p_amount, 0), 2);
  v_method text := coalesce(nullif(p_method, ''), 'cash');
begin
  if auth.uid() is null then
    raise exception 'Please sign in again.';
  end if;
  if v_method not in ('cash', 'bank', 'other') then
    raise exception 'Choose cash, bank or other as the payment method.';
  end if;

  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then
    raise exception 'This bill could not be found.';
  end if;
  if v_inv.status = 'Cancelled' then
    raise exception 'This bill is cancelled. Payments cannot be added.';
  end if;

  select coalesce(sum(amount), 0) into v_paid from public.payments where invoice_id = p_invoice_id;

  if v_amount <= 0 then
    raise exception 'Enter an amount greater than zero.';
  end if;
  if v_amount > v_inv.total_value - v_paid then
    raise exception 'That is more than the amount due (Rs %).', (v_inv.total_value - v_paid);
  end if;

  insert into public.payments (invoice_id, amount, method) values (p_invoice_id, v_amount, v_method);

  update public.invoices
     set payment_status = case
           when v_paid + v_amount >= total_value then 'Paid'
           when v_paid + v_amount = 0 then 'Credit'
           else 'Partial' end
   where id = p_invoice_id;
end;
$$;

-- ---------------------------------------------------------------- money_summary (Home cards)
-- p_day is a Pakistan-time date. "Udhaar to collect" is everything still owed on valid bills.
create or replace function public.money_summary(p_day date)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'sales_total',   coalesce((select sum(total_value) from public.invoices
                               where invoice_date = p_day and status <> 'Cancelled'), 0),
    'sales_count',   (select count(*) from public.invoices
                      where invoice_date = p_day and status <> 'Cancelled'),
    'cash_received', coalesce((select sum(p.amount) from public.payments p
                               join public.invoices i on i.id = p.invoice_id
                               where i.status <> 'Cancelled'
                                 and (p.paid_at at time zone 'UTC')::date = p_day), 0),
    'udhaar_total',  coalesce((select sum(due_total) from public.invoice_balances
                               where status <> 'Cancelled' and due_total > 0), 0),
    'udhaar_count',  (select count(*) from public.invoice_balances
                      where status <> 'Cancelled' and due_total > 0)
  );
$$;

-- ---------------------------------------------------------------- who can run the functions
revoke all on function public.create_invoice(uuid, text, text, date, jsonb, numeric, text) from public, anon;
revoke all on function public.record_payment(uuid, numeric, text) from public, anon;
revoke all on function public.money_summary(date) from public, anon;
grant execute on function public.create_invoice(uuid, text, text, date, jsonb, numeric, text) to authenticated;
grant execute on function public.record_payment(uuid, numeric, text) to authenticated;
grant execute on function public.money_summary(date) to authenticated;

-- ======== 04_missing_tables.sql ========
-- 0001a: tables that exist in the CSV but not in the old SQL files. GENERATED from the schema CSV.
-- Run BEFORE 16_roles_and_audit.sql.

create sequence if not exists public.charging_slip_seq;
create sequence if not exists public.claim_slip_seq;
create sequence if not exists public.expense_number_seq;
create sequence if not exists public.scrap_intake_number_seq;
create sequence if not exists public.scrap_sale_number_seq;

create table if not exists public.ai_actions (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid DEFAULT auth.uid(),
  "kind" text NOT NULL,
  "status" text NOT NULL DEFAULT 'proposed'::text,
  "user_message" text,
  "proposal" jsonb NOT NULL,
  "sent_payload" jsonb,
  "result" jsonb,
  "error" text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "resolved_at" timestamp with time zone
);

create table if not exists public.battery_claims (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "claim_number" text NOT NULL DEFAULT ('CLM-'::text || lpad((nextval('claim_slip_seq'::regclass))::text, 6, '0'::text)),
  "customer_id" uuid,
  "customer_name" text NOT NULL,
  "customer_phone" text,
  "battery_brand" text NOT NULL,
  "battery_model" text NOT NULL,
  "battery_number" text,
  "original_invoice_id" uuid,
  "distributor_id" uuid,
  "claim_amount" numeric,
  "extra_charges" numeric,
  "note" text,
  "status" text NOT NULL DEFAULT 'received'::text,
  "received_date" date NOT NULL,
  "sent_to_distributor_at" timestamp with time zone,
  "approved_at" timestamp with time zone,
  "rejected_at" timestamp with time zone,
  "given_to_customer_at" timestamp with time zone,
  "settled_at" timestamp with time zone,
  "created_by" uuid DEFAULT auth.uid(),
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);

create table if not exists public.cash_settings (
  "id" boolean NOT NULL DEFAULT true,
  "opening_balance" numeric NOT NULL DEFAULT 0,
  "opening_date" date NOT NULL DEFAULT CURRENT_DATE,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);

create table if not exists public.charging_jobs (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "slip_number" text NOT NULL DEFAULT ('CHG-'::text || lpad((nextval('charging_slip_seq'::regclass))::text, 6, '0'::text)),
  "customer_id" uuid,
  "customer_name" text NOT NULL,
  "customer_phone" text,
  "battery_brand" text NOT NULL,
  "battery_model" text NOT NULL,
  "battery_number" text,
  "price" numeric NOT NULL DEFAULT 0,
  "note" text,
  "received_date" date NOT NULL,
  "due_date" date NOT NULL,
  "status" text NOT NULL DEFAULT 'in_shop'::text,
  "collected_at" timestamp with time zone,
  "created_by" uuid DEFAULT auth.uid(),
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  "outcome" text,
  "handover_amount" numeric,
  "handover_note" text
);

create table if not exists public.charging_price_list (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "label" text NOT NULL,
  "price" numeric NOT NULL DEFAULT 0,
  "created_by" uuid DEFAULT auth.uid(),
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);

create table if not exists public.distributors (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "name" text NOT NULL,
  "phone" text,
  "address" text,
  "note" text,
  "created_by" uuid DEFAULT auth.uid(),
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  "ntn_or_cnic" text,
  "opening_balance" numeric NOT NULL DEFAULT 0,
  "opening_balance_date" date,
  "is_active" boolean NOT NULL DEFAULT true
);

create table if not exists public.expense_categories (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "name" text NOT NULL,
  "sort_order" integer NOT NULL DEFAULT 0,
  "excluded_from_profit" boolean NOT NULL DEFAULT false,
  "is_active" boolean NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

create table if not exists public.expenses (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "client_id" uuid,
  "expense_number" text NOT NULL DEFAULT ('EX-'::text || lpad((nextval('expense_number_seq'::regclass))::text, 6, '0'::text)),
  "category_id" uuid NOT NULL,
  "amount" numeric NOT NULL,
  "expense_date" date NOT NULL,
  "method" text NOT NULL DEFAULT 'cash'::text,
  "paid_to" text,
  "reference" text,
  "cheque_number" text,
  "cheque_date" date,
  "bank_name" text,
  "note" text,
  "status" text NOT NULL DEFAULT 'Valid'::text,
  "cancel_reason" text,
  "created_by" uuid DEFAULT auth.uid(),
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);

create table if not exists public.scrap_battery_inventory (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "intake_number" text NOT NULL DEFAULT ('SB-'::text || lpad((nextval('scrap_intake_number_seq'::regclass))::text, 6, '0'::text)),
  "invoice_id" uuid,
  "customer_id" uuid,
  "customer_name" text,
  "brand" text NOT NULL,
  "model" text NOT NULL,
  "battery_type" text,
  "battery_number" text,
  "quantity" integer NOT NULL DEFAULT 1,
  "estimated_weight_kg" numeric,
  "note" text,
  "status" text NOT NULL DEFAULT 'in_stock'::text,
  "received_date" date NOT NULL,
  "sold_in_sale_id" uuid,
  "created_by" uuid DEFAULT auth.uid(),
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);

create table if not exists public.scrap_battery_sales (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "sale_number" text NOT NULL DEFAULT ('SS-'::text || lpad((nextval('scrap_sale_number_seq'::regclass))::text, 6, '0'::text)),
  "buyer_name" text NOT NULL,
  "buyer_phone" text,
  "total_weight_kg" numeric NOT NULL,
  "rate_per_kg" numeric NOT NULL,
  "total_amount" numeric NOT NULL,
  "sale_date" date NOT NULL,
  "note" text,
  "created_by" uuid DEFAULT auth.uid(),
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

do $$ begin alter table public.ai_actions add constraint ai_actions_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.battery_claims add constraint battery_claims_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.cash_settings add constraint cash_settings_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_jobs add constraint charging_jobs_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_price_list add constraint charging_price_list_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.distributors add constraint distributors_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expense_categories add constraint expense_categories_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expenses add constraint expenses_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_battery_inventory_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_sales add constraint scrap_battery_sales_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.battery_claims add constraint battery_claims_claim_number_key UNIQUE (claim_number); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_jobs add constraint charging_jobs_slip_number_key UNIQUE (slip_number); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_price_list add constraint charging_price_list_label_key UNIQUE (label); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.distributors add constraint distributors_name_key UNIQUE (name); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expense_categories add constraint expense_categories_name_key UNIQUE (name); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expenses add constraint expenses_expense_number_key UNIQUE (expense_number); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expenses add constraint expenses_client_id_key UNIQUE (client_id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_battery_inventory_intake_number_key UNIQUE (intake_number); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_sales add constraint scrap_battery_sales_sale_number_key UNIQUE (sale_number); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.ai_actions add constraint ai_actions_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'executing'::text, 'confirmed'::text, 'cancelled'::text, 'edited'::text, 'failed'::text]))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.ai_actions add constraint ai_actions_kind_check CHECK ((kind = ANY (ARRAY['create_bill'::text, 'add_item'::text, 'add_customer'::text, 'add_scrap'::text, 'sell_scrap'::text, 'create_charging'::text, 'create_claim'::text]))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.battery_claims add constraint battery_claims_status_check CHECK ((status = ANY (ARRAY['received'::text, 'sent_to_distributor'::text, 'approved'::text, 'rejected'::text, 'given_to_customer'::text, 'settled'::text]))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.battery_claims add constraint battery_claims_claim_amount_check CHECK (((claim_amount IS NULL) OR (claim_amount >= (0)::numeric))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.battery_claims add constraint battery_claims_extra_charges_check CHECK (((extra_charges IS NULL) OR (extra_charges >= (0)::numeric))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.cash_settings add constraint cash_settings_id_check CHECK (id); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.cash_settings add constraint cash_settings_opening_balance_check CHECK ((opening_balance >= (0)::numeric)); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_jobs add constraint charging_jobs_outcome_check CHECK ((outcome = ANY (ARRAY['charged'::text, 'faulty'::text]))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_jobs add constraint charging_jobs_status_check CHECK ((status = ANY (ARRAY['in_shop'::text, 'collected'::text, 'unclaimed'::text]))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_jobs add constraint charging_jobs_price_check CHECK ((price >= (0)::numeric)); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_price_list add constraint charging_price_list_price_check CHECK ((price >= (0)::numeric)); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_price_list add constraint charging_price_list_label_check CHECK (((char_length(label) >= 1) AND (char_length(label) <= 80))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.distributors add constraint distributors_ntn_or_cnic_check CHECK (((ntn_or_cnic IS NULL) OR (ntn_or_cnic ~ '^([0-9]{7}|[0-9]{13})$'::text))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.distributors add constraint distributors_name_check CHECK (((char_length(name) >= 1) AND (char_length(name) <= 120))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expenses add constraint expenses_cheque_needs_number CHECK (((method <> 'cheque'::text) OR (cheque_number IS NOT NULL))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expenses add constraint expenses_amount_check CHECK ((amount > (0)::numeric)); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expenses add constraint expenses_status_check CHECK ((status = ANY (ARRAY['Valid'::text, 'Cancelled'::text]))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expenses add constraint expenses_method_check CHECK ((method = ANY (ARRAY['cash'::text, 'cheque'::text, 'online'::text, 'easypaisa'::text, 'jazzcash'::text]))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_sold_needs_sale CHECK (((status <> 'sold'::text) OR (sold_in_sale_id IS NOT NULL))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_battery_inventory_estimated_weight_kg_check CHECK (((estimated_weight_kg IS NULL) OR (estimated_weight_kg > (0)::numeric))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_battery_inventory_quantity_check CHECK ((quantity > 0)); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_battery_inventory_status_check CHECK ((status = ANY (ARRAY['in_stock'::text, 'sold'::text]))); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_sales add constraint scrap_battery_sales_rate_per_kg_check CHECK ((rate_per_kg >= (0)::numeric)); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_sales add constraint scrap_battery_sales_total_weight_kg_check CHECK ((total_weight_kg > (0)::numeric)); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_sales add constraint scrap_battery_sales_total_amount_check CHECK ((total_amount >= (0)::numeric)); exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.ai_actions add constraint ai_actions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.battery_claims add constraint battery_claims_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.battery_claims add constraint battery_claims_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.battery_claims add constraint battery_claims_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES distributors(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.battery_claims add constraint battery_claims_original_invoice_id_fkey FOREIGN KEY (original_invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_jobs add constraint charging_jobs_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_jobs add constraint charging_jobs_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.charging_price_list add constraint charging_price_list_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.distributors add constraint distributors_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expenses add constraint expenses_category_id_fkey FOREIGN KEY (category_id) REFERENCES expense_categories(id) ON DELETE RESTRICT; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.expenses add constraint expenses_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_battery_inventory_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_battery_inventory_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_battery_inventory_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_inventory add constraint scrap_battery_inventory_sold_in_sale_id_fkey FOREIGN KEY (sold_in_sale_id) REFERENCES scrap_battery_sales(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;
do $$ begin alter table public.scrap_battery_sales add constraint scrap_battery_sales_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table then null; end $$;

CREATE INDEX IF NOT EXISTS ai_actions_status_idx ON public.ai_actions USING btree (status, created_at DESC);
CREATE INDEX IF NOT EXISTS ai_actions_user_idx ON public.ai_actions USING btree (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS battery_claims_distributor_idx ON public.battery_claims USING btree (distributor_id);
CREATE INDEX IF NOT EXISTS battery_claims_status_idx ON public.battery_claims USING btree (status);
CREATE INDEX IF NOT EXISTS battery_claims_customer_idx ON public.battery_claims USING btree (customer_id);
CREATE INDEX IF NOT EXISTS battery_claims_received_idx ON public.battery_claims USING btree (received_date DESC);
CREATE INDEX IF NOT EXISTS charging_jobs_received_idx ON public.charging_jobs USING btree (received_date DESC);
CREATE INDEX IF NOT EXISTS charging_jobs_status_idx ON public.charging_jobs USING btree (status);
CREATE INDEX IF NOT EXISTS charging_jobs_customer_idx ON public.charging_jobs USING btree (customer_id);
CREATE UNIQUE INDEX IF NOT EXISTS distributors_name_lower_idx ON public.distributors USING btree (lower(name));
CREATE INDEX IF NOT EXISTS expenses_created_idx ON public.expenses USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS expenses_expense_date_idx ON public.expenses USING btree (expense_date DESC);
CREATE INDEX IF NOT EXISTS expenses_category_idx ON public.expenses USING btree (category_id);
CREATE INDEX IF NOT EXISTS scrap_battery_inventory_invoice_idx ON public.scrap_battery_inventory USING btree (invoice_id);
CREATE INDEX IF NOT EXISTS scrap_battery_inventory_sale_idx ON public.scrap_battery_inventory USING btree (sold_in_sale_id);
CREATE INDEX IF NOT EXISTS scrap_battery_inventory_status_idx ON public.scrap_battery_inventory USING btree (status);
CREATE INDEX IF NOT EXISTS scrap_battery_sales_date_idx ON public.scrap_battery_sales USING btree (sale_date DESC);

alter table public.ai_actions enable row level security;
alter table public.battery_claims enable row level security;
alter table public.cash_settings enable row level security;
alter table public.charging_jobs enable row level security;
alter table public.charging_price_list enable row level security;
alter table public.distributors enable row level security;
alter table public.expense_categories enable row level security;
alter table public.expenses enable row level security;
alter table public.scrap_battery_inventory enable row level security;
alter table public.scrap_battery_sales enable row level security;

-- ======== 05_reports.sql ========
-- PowerCell POS App, Phase 5: reports
-- Run this once in Supabase: SQL Editor > New query > paste all > Run.
-- Run 03_invoices.sql first. Safe to run again. It only reads data, it never changes it.

-- report_summary(from, to): everything the Reports page shows, in one call.
-- Dates are Pakistan-time dates. Cancelled bills are left out.
-- p_bucket is 'day' or 'month' (how the sales chart is grouped).
create or replace function public.report_summary(p_from date, p_to date, p_bucket text default 'day')
returns jsonb
language sql
stable
set search_path = ''
as $$
  with inv as (
    select * from public.invoices
    where invoice_date between p_from and p_to and status <> 'Cancelled'
  ),
  itm as (
    select ii.* from public.invoice_items ii join inv on inv.id = ii.invoice_id
  ),
  pay as (
    select p.*, i.invoice_date
    from public.payments p
    join public.invoices i on i.id = p.invoice_id
    where i.status <> 'Cancelled'
      and (p.paid_at at time zone 'UTC')::date between p_from and p_to
  ),
  buckets as (
    select generate_series(
             date_trunc(case when p_bucket = 'month' then 'month' else 'day' end, p_from::timestamp),
             p_to::timestamp,
             case when p_bucket = 'month' then interval '1 month' else interval '1 day' end
           )::date as b
  )
  select jsonb_build_object(
    'sales_total',     coalesce((select sum(total_value) from inv), 0),
    'invoice_count',   (select count(*) from inv),
    'gross_profit',    coalesce((select sum(value_excl_tax - cost_price * quantity) from itm), 0),
    'cash_received',   coalesce((select sum(amount) from pay), 0),
    'received_on_older_bills',
                       coalesce((select sum(amount) from pay where invoice_date < p_from), 0),
    'by_method',       jsonb_build_object(
                         'cash',  coalesce((select sum(amount) from pay where method = 'cash'), 0),
                         'bank',  coalesce((select sum(amount) from pay where method = 'bank'), 0),
                         'other', coalesce((select sum(amount) from pay where method = 'other'), 0)),
    'credit_given',    coalesce((select sum(due_total) from public.invoice_balances b
                                 where b.id in (select id from inv) and b.due_total > 0), 0),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object(
               'day', to_char(bk.b, 'YYYY-MM-DD'),
               'sales', coalesce(s.sales, 0),
               'count', coalesce(s.cnt, 0)) order by bk.b)
      from buckets bk
      left join (
        select date_trunc(case when p_bucket = 'month' then 'month' else 'day' end, invoice_date::timestamp)::date as b,
               sum(total_value) as sales, count(*) as cnt
        from inv group by 1
      ) s on s.b = bk.b
    ), '[]'::jsonb),
    'top_items', coalesce((
      select jsonb_agg(t order by t.revenue desc)
      from (
        select description,
               sum(quantity)::int as quantity,
               sum(value_excl_tax) as revenue
        from itm
        group by description
        order by sum(value_excl_tax) desc
        limit 8
      ) t
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.report_summary(date, date, text) from public, anon;
grant execute on function public.report_summary(date, date, text) to authenticated;

-- ======== 06_suppliers_purchases.sql ========
-- PowerCell POS App, Phase F1: Suppliers + Purchase invoice ("Receive stock")
-- Run this once in Supabase: SQL Editor > New query > paste all > Run.
-- Run 01, 02, 03, 05 first (and whatever created `distributors` -- 06_battery_services.sql). Safe to run again.
--
-- ****************************************************************************************************
-- CAUTION -- read before running: Task 1 of Phase F0 (exporting the real schema / the missing
-- 06_battery_services.sql etc.) was never completed, so the exact current shape of `public.distributors`
-- and its RLS policies is UNVERIFIED here. This file only assumes the columns already visible in the
-- app's own code: id, name, phone, address, note. Every ALTER below uses "add column if not exists" so
-- it will not fail if some of these already exist, but if `distributors` turns out to have extra
-- constraints or a different policy setup than assumed, check this file against the real schema before
-- (or right after) running it. Get that schema export when you can and diff it against this file.
-- ****************************************************************************************************
--
-- How it works (same shape as 03_invoices.sql):
--  * Purchases are saved ONLY through create_purchase() and cancel_purchase(). The browser cannot
--    insert or edit purchase invoices, items or stock directly.
--  * create_purchase() saves the bill, its lines, the stock increase, the cost-price update and an
--    optional payment made right now, in ONE transaction. If anything fails, nothing is saved.
--  * A new supplier or a brand-new product can be created inline, in that same transaction.
--  * `supplier_payments` is created here (create_purchase writes to it for "paid now" purchases), but
--    record_supplier_payment() / cancel_supplier_payment() and the Payments screen are Phase F2 --
--    this file does not add a way to record a payment on its own, only as part of a purchase.
--  * Decision D3: cost_price becomes the latest purchase cost, unless the line's "keep old cost" flag
--    is set.
--  * Decision D5: cheque fields are stored now; a bounced cheque is NEVER auto-applied to the ledger --
--    it always needs a separate, manual reversal payment (a future, negative-facing entry in F2/F6).
--    No view or function in this file reads `cheque_status` to adjust a balance.
--  * Decision D6: `stock_movements` keeps a full history, indexed by (inventory_id, created_at).

-- ---------------------------------------------------------------- 1. Suppliers = extended `distributors`
alter table public.distributors
  add column if not exists ntn_or_cnic         text,
  add column if not exists opening_balance     numeric(14,2) not null default 0,
  add column if not exists opening_balance_date date,
  add column if not exists is_active           boolean not null default true,
  add column if not exists created_at          timestamptz not null default now(),
  add column if not exists updated_at          timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'distributors_ntn_or_cnic_check'
  ) then
    alter table public.distributors
      add constraint distributors_ntn_or_cnic_check
      check (ntn_or_cnic is null or ntn_or_cnic ~ '^([0-9]{7}|[0-9]{13})$');
  end if;
end $$;

-- Name unique ignoring case (plan section 2, "Supplier fields"). Skipped, with a notice instead of
-- failing the whole script, if case-insensitive duplicate names already exist in production.
do $$
begin
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'distributors_name_lower_idx') then
    begin
      execute 'create unique index distributors_name_lower_idx on public.distributors (lower(name))';
    exception when unique_violation then
      raise notice 'Skipped unique index on distributors(name): case-insensitive duplicate names exist. Merge or rename them, then run: create unique index distributors_name_lower_idx on public.distributors (lower(name));';
    end;
  end if;
end $$;

drop trigger if exists distributors_set_updated_at on public.distributors;
create trigger distributors_set_updated_at
  before update on public.distributors
  for each row execute function public.set_updated_at();

-- Security: additive only. Does not touch whatever grants/policies 06_battery_services.sql already put
-- in place for Battery claims -- just makes sure signed-in users can at least read the table.
alter table public.distributors enable row level security;
revoke all on public.distributors from anon;
grant select on public.distributors to authenticated;

drop policy if exists "Signed-in users can view suppliers" on public.distributors;
create policy "Signed-in users can view suppliers" on public.distributors for select to authenticated using (true);

-- ---------------------------------------------------------------- 2. purchase_invoices
create sequence if not exists public.purchase_number_seq;

create table if not exists public.purchase_invoices (
  id                      uuid primary key default gen_random_uuid(),
  client_id               uuid unique,   -- set by the browser so an offline retry never double-posts
  purchase_number         text not null unique
                            default ('PB-' || lpad(nextval('public.purchase_number_seq')::text, 6, '0')),
  supplier_id             uuid not null references public.distributors (id) on delete restrict,
  supplier_invoice_number text,
  invoice_date            date not null,
  subtotal                numeric(14,2) not null check (subtotal >= 0),
  discount                numeric(14,2) not null default 0 check (discount >= 0),
  freight                 numeric(14,2) not null default 0 check (freight >= 0),
  total_value             numeric(14,2) not null check (total_value >= 0),
  note                    text,
  status                  text not null default 'Valid' check (status in ('Valid', 'Cancelled')),
  cancelled_at            timestamptz,
  cancel_reason           text,
  created_by              uuid default auth.uid() references auth.users (id) on delete set null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint purchase_invoices_discount_le_subtotal check (discount <= subtotal)
);
create unique index if not exists purchase_invoices_supplier_number_idx
  on public.purchase_invoices (supplier_id, lower(supplier_invoice_number))
  where supplier_invoice_number is not null and status = 'Valid';
create index if not exists purchase_invoices_supplier_idx on public.purchase_invoices (supplier_id);
create index if not exists purchase_invoices_date_idx     on public.purchase_invoices (invoice_date desc);
create index if not exists purchase_invoices_created_idx  on public.purchase_invoices (created_at desc);

-- ---------------------------------------------------------------- 3. purchase_items (max 20 per bill)
create table if not exists public.purchase_items (
  id            uuid primary key default gen_random_uuid(),
  purchase_id   uuid not null references public.purchase_invoices (id) on delete cascade,
  inventory_id  uuid not null references public.inventory (id) on delete restrict,
  description   text not null,
  quantity      integer not null check (quantity > 0),
  unit_cost     numeric(12,2) not null check (unit_cost >= 0),
  line_total    numeric(14,2) not null check (line_total >= 0),
  created_at    timestamptz not null default now()
);
create index if not exists purchase_items_purchase_idx   on public.purchase_items (purchase_id);
create index if not exists purchase_items_inventory_idx  on public.purchase_items (inventory_id);

-- Second safety net alongside the check inside create_purchase().
create or replace function public.enforce_purchase_item_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.purchase_items where purchase_id = new.purchase_id) >= 20 then
    raise exception 'A purchase bill can have up to 20 products. Save this one and make a second bill for the rest.';
  end if;
  return new;
end;
$$;

drop trigger if exists purchase_items_limit on public.purchase_items;
create trigger purchase_items_limit
  before insert on public.purchase_items
  for each row execute function public.enforce_purchase_item_limit();

-- ---------------------------------------------------------------- 4. supplier_payments
-- Table only, in F1 (create_purchase's "paid now" writes here). record_supplier_payment() /
-- cancel_supplier_payment() and the Payments screen itself are Phase F2 (13_supplier_payments.sql).
create sequence if not exists public.supplier_payment_number_seq;

create table if not exists public.supplier_payments (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid unique,
  payment_number  text not null unique
                    default ('SP-' || lpad(nextval('public.supplier_payment_number_seq')::text, 6, '0')),
  supplier_id     uuid not null references public.distributors (id) on delete restrict,
  purchase_id     uuid references public.purchase_invoices (id) on delete restrict,  -- null = on-account
  amount          numeric(14,2) not null check (amount > 0),
  method          text not null default 'cash' check (method in ('cash', 'cheque', 'online', 'easypaisa', 'jazzcash')),
  paid_at         date not null,
  reference       text,
  cheque_number   text,
  cheque_date     date,
  bank_name       text,
  cheque_status   text check (cheque_status is null or cheque_status in ('issued', 'cleared', 'bounced')),
  note            text,
  status          text not null default 'Valid' check (status in ('Valid', 'Cancelled')),
  cancel_reason   text,
  created_by      uuid default auth.uid() references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint supplier_payments_cheque_needs_number check (method <> 'cheque' or cheque_number is not null)
);
create index if not exists supplier_payments_supplier_idx  on public.supplier_payments (supplier_id);
create index if not exists supplier_payments_purchase_idx  on public.supplier_payments (purchase_id);
create index if not exists supplier_payments_paid_at_idx   on public.supplier_payments (paid_at desc);

-- ---------------------------------------------------------------- 5. stock_movements (decision D6)
create table if not exists public.stock_movements (
  id            uuid primary key default gen_random_uuid(),
  inventory_id  uuid not null references public.inventory (id) on delete restrict,
  change        integer not null check (change <> 0),
  reason        text not null check (reason in ('opening', 'purchase', 'purchase_cancel', 'adjustment', 'sale')),
  ref_table     text,
  ref_id        uuid,
  note          text,
  created_by    uuid default auth.uid() references auth.users (id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists stock_movements_inventory_created_idx on public.stock_movements (inventory_id, created_at);

-- ---------------------------------------------------------------- updated_at triggers
drop trigger if exists purchase_invoices_set_updated_at on public.purchase_invoices;
create trigger purchase_invoices_set_updated_at
  before update on public.purchase_invoices
  for each row execute function public.set_updated_at();

drop trigger if exists supplier_payments_set_updated_at on public.supplier_payments;
create trigger supplier_payments_set_updated_at
  before update on public.supplier_payments
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------- security: same pattern as Phase 3
alter table public.purchase_invoices enable row level security;
alter table public.purchase_items    enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.stock_movements   enable row level security;

revoke all on public.purchase_invoices, public.purchase_items, public.supplier_payments, public.stock_movements from anon;
revoke all on public.purchase_invoices, public.purchase_items, public.supplier_payments, public.stock_movements from authenticated;
-- Signed-in users can only READ. All writing goes through the functions below.
grant select on public.purchase_invoices, public.purchase_items, public.supplier_payments, public.stock_movements to authenticated;

drop policy if exists "Signed-in users can view purchase invoices" on public.purchase_invoices;
drop policy if exists "Signed-in users can view purchase items"    on public.purchase_items;
drop policy if exists "Signed-in users can view supplier payments" on public.supplier_payments;
drop policy if exists "Signed-in users can view stock movements"   on public.stock_movements;

create policy "Signed-in users can view purchase invoices" on public.purchase_invoices for select to authenticated using (true);
create policy "Signed-in users can view purchase items"    on public.purchase_items    for select to authenticated using (true);
create policy "Signed-in users can view supplier payments" on public.supplier_payments for select to authenticated using (true);
create policy "Signed-in users can view stock movements"   on public.stock_movements   for select to authenticated using (true);

-- ---------------------------------------------------------------- 6. views used by the screens

-- purchase_balances: one row per purchase invoice, with paid/due, like invoice_balances.
create or replace view public.purchase_balances
with (security_invoker = true) as
select
  pi.*,
  coalesce(sp.paid, 0)                 as paid_total,
  pi.total_value - coalesce(sp.paid, 0) as due_total,
  case
    when coalesce(sp.paid, 0) <= 0            then 'Unpaid'
    when coalesce(sp.paid, 0) >= pi.total_value then 'Paid'
    else 'Part paid'
  end as payment_tag
from public.purchase_invoices pi
left join (
  select purchase_id, sum(amount) as paid
  from public.supplier_payments
  where status = 'Valid' and purchase_id is not null
  group by purchase_id
) sp on sp.purchase_id = pi.id;

grant select on public.purchase_balances to authenticated;
revoke all on public.purchase_balances from anon;

-- supplier_ledger: one row per event per supplier (opening balance, purchase bill, payment), with a
-- running balance ordered by date then created_at. Sign convention: positive = we owe the supplier.
-- IMPORTANT: this never reads `cheque_status` -- a bounced cheque needs its own manual reversal row
-- in supplier_payments (decision D5), it does not change what this view shows on its own.
create or replace view public.supplier_ledger
with (security_invoker = true) as
with events as (
  select
    d.id                                              as supplier_id,
    coalesce(d.opening_balance_date, d.created_at::date) as event_date,
    d.created_at                                      as event_created_at,
    'opening'::text                                   as entry_type,
    'Opening balance'::text                           as entry_label,
    null::text                                        as reference,
    null::uuid                                         as ref_id,
    d.opening_balance                                 as amount
  from public.distributors d
  where coalesce(d.opening_balance, 0) <> 0

  union all

  select
    pi.supplier_id,
    pi.invoice_date,
    pi.created_at,
    'purchase',
    'Purchase bill',
    pi.purchase_number || coalesce(' / Supplier inv ' || pi.supplier_invoice_number, ''),
    pi.id,
    pi.total_value
  from public.purchase_invoices pi
  where pi.status = 'Valid'

  union all

  select
    sp.supplier_id,
    sp.paid_at,
    sp.created_at,
    'payment',
    'Payment - ' || initcap(sp.method),
    sp.payment_number || coalesce(' / Chq ' || sp.cheque_number, ''),
    sp.id,
    -sp.amount
  from public.supplier_payments sp
  where sp.status = 'Valid'
)
select
  e.supplier_id,
  e.event_date,
  e.event_created_at,
  e.entry_type,
  e.entry_label,
  e.reference,
  e.ref_id,
  e.amount,
  sum(e.amount) over (
    partition by e.supplier_id
    order by e.event_date, e.event_created_at
    rows between unbounded preceding and current row
  ) as running_balance
from events e;

grant select on public.supplier_ledger to authenticated;
revoke all on public.supplier_ledger from anon;

-- supplier_balances: one row per supplier. Powers the Suppliers list and "Total we owe".
create or replace view public.supplier_balances
with (security_invoker = true) as
select
  d.id,
  d.name,
  d.phone,
  d.address,
  d.note,
  d.ntn_or_cnic,
  d.opening_balance,
  d.opening_balance_date,
  d.is_active,
  d.created_at,
  d.updated_at,
  coalesce(pb.total_bought, 0) as total_bought,
  coalesce(pp.total_paid, 0)   as total_paid,
  coalesce(d.opening_balance, 0) + coalesce(pb.total_bought, 0) - coalesce(pp.total_paid, 0) as balance,
  pb.last_purchase_date,
  pp.last_payment_date
from public.distributors d
left join (
  select supplier_id, sum(total_value) as total_bought, max(invoice_date) as last_purchase_date
  from public.purchase_invoices
  where status = 'Valid'
  group by supplier_id
) pb on pb.supplier_id = d.id
left join (
  select supplier_id, sum(amount) as total_paid, max(paid_at) as last_payment_date
  from public.supplier_payments
  where status = 'Valid'
  group by supplier_id
) pp on pp.supplier_id = d.id;

grant select on public.supplier_balances to authenticated;
revoke all on public.supplier_balances from anon;

-- ---------------------------------------------------------------- 7. create_purchase
-- p_lines is a JSON list: [{"inventory_id": "...", "quantity": 2, "unit_cost": 15500, "keep_old_cost": false}, ...]
-- or, for a brand-new product: [{"new_item": {"category": "battery", "brand": "...", "model": "...", ...},
-- "quantity": 2, "unit_cost": 15500}, ...]. Totals are calculated here from quantity x unit_cost, minus
-- discount, plus freight. Nothing typed by a person or an AI is trusted.
-- p_client_id: generated in the browser. A retried call with the same id returns the same purchase
-- instead of creating a second one (idempotent, needed for a safe offline retry in F5).
create or replace function public.create_purchase(
  p_client_id               uuid,
  p_supplier_id             uuid,
  p_new_supplier_name       text,
  p_new_supplier_phone      text,
  p_new_supplier_address    text,
  p_supplier_invoice_number text,
  p_invoice_date            date,
  p_note                    text,
  p_lines                   jsonb,
  p_discount                numeric,
  p_freight                 numeric,
  p_paid_now                numeric,
  p_method                  text,
  p_reference               text,
  p_cheque_number           text,
  p_cheque_date             date,
  p_bank_name               text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid := auth.uid();
  v_today        date := (now() at time zone 'UTC')::date;
  v_date         date;
  v_supplier_id  uuid;
  v_purchase_id  uuid;
  v_line         record;
  v_inv          public.inventory%rowtype;
  v_subtotal     numeric(14,2) := 0;
  v_discount     numeric(14,2) := round(coalesce(p_discount, 0), 2);
  v_freight      numeric(14,2) := round(coalesce(p_freight, 0), 2);
  v_total        numeric(14,2);
  v_paid         numeric(14,2) := round(coalesce(p_paid_now, 0), 2);
  v_method       text := coalesce(nullif(p_method, ''), 'cash');
  v_line_total   numeric(14,2);
  v_new_inv_id   uuid;
begin
  if v_uid is null then
    raise exception 'Please sign in again.';
  end if;

  -- Idempotency: a retried offline save with the same client id returns the same purchase, never a duplicate.
  if p_client_id is not null then
    select id into v_purchase_id from public.purchase_invoices where client_id = p_client_id;
    if found then
      return v_purchase_id;
    end if;
  end if;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Add at least one product to the bill.';
  end if;
  if jsonb_array_length(p_lines) > 20 then
    raise exception 'A purchase bill can have up to 20 products. Save this one and make a second bill for the rest.';
  end if;

  v_date := coalesce(p_invoice_date, v_today);
  if v_date > v_today then
    raise exception 'The bill date cannot be in the future.';
  end if;

  if v_method not in ('cash', 'cheque', 'online', 'easypaisa', 'jazzcash') then
    raise exception 'Choose a valid payment method.';
  end if;

  -- Supplier: existing, or created inline right here
  if p_supplier_id is not null then
    select id into v_supplier_id from public.distributors where id = p_supplier_id for update;
    if not found then
      raise exception 'That supplier no longer exists. Choose the supplier again.';
    end if;
  elsif nullif(btrim(p_new_supplier_name), '') is not null then
    select id into v_supplier_id from public.distributors where lower(name) = lower(btrim(p_new_supplier_name));
    if not found then
      insert into public.distributors (name, phone, address)
      values (btrim(p_new_supplier_name), nullif(btrim(p_new_supplier_phone), ''), nullif(btrim(p_new_supplier_address), ''))
      returning id into v_supplier_id;
    end if;
  else
    raise exception 'Choose a supplier, or type a name to add a new one.';
  end if;

  -- Line shape + basic validation
  if exists (
    select 1
    from jsonb_to_recordset(p_lines) as x(inventory_id uuid, quantity integer, unit_cost numeric, keep_old_cost boolean, new_item jsonb)
    where (x.inventory_id is null and x.new_item is null)
       or x.quantity is null or x.quantity <= 0
       or x.unit_cost is null or x.unit_cost < 0
  ) then
    raise exception 'Each product needs a quantity of 1 or more and a cost of 0 or more.';
  end if;

  -- No duplicate existing products (same rule as sale bills; a brand-new product is always distinct)
  if (
    select count(*) - count(distinct x.inventory_id)
    from jsonb_to_recordset(p_lines) as x(inventory_id uuid, quantity integer, unit_cost numeric, keep_old_cost boolean, new_item jsonb)
    where x.inventory_id is not null
  ) > 0 then
    raise exception 'The same product appears twice on the bill. Combine it into one line.';
  end if;

  -- Duplicate supplier-invoice-number check
  if nullif(btrim(p_supplier_invoice_number), '') is not null
     and exists (
       select 1 from public.purchase_invoices
       where supplier_id = v_supplier_id
         and status = 'Valid'
         and lower(supplier_invoice_number) = lower(btrim(p_supplier_invoice_number))
     )
  then
    raise exception 'This bill number is already saved for this supplier.';
  end if;

  -- Subtotal, calculated here from quantity x unit_cost, never trusted from the browser
  select coalesce(sum(round(x.quantity * round(x.unit_cost, 2), 2)), 0)
    into v_subtotal
  from jsonb_to_recordset(p_lines) as x(inventory_id uuid, quantity integer, unit_cost numeric, keep_old_cost boolean, new_item jsonb);

  if v_discount > v_subtotal then
    raise exception 'The discount cannot be more than the subtotal.';
  end if;
  v_total := round(v_subtotal - v_discount + v_freight, 2);
  if v_total <= 0 then
    raise exception 'The bill total is zero. Check the quantities and costs.';
  end if;
  if v_paid < 0 or v_paid > v_total then
    raise exception 'The amount paid must be between 0 and the bill total.';
  end if;
  if v_paid > 0 and v_method = 'cheque' and nullif(btrim(p_cheque_number), '') is null then
    raise exception 'Enter the cheque number.';
  end if;

  insert into public.purchase_invoices (
    client_id, supplier_id, supplier_invoice_number, invoice_date, subtotal, discount, freight, total_value, note
  ) values (
    p_client_id, v_supplier_id, nullif(btrim(p_supplier_invoice_number), ''), v_date,
    v_subtotal, v_discount, v_freight, v_total, nullif(btrim(p_note), '')
  )
  returning id into v_purchase_id;

  -- Lines, stock and cost, in a fixed order so two purchases at once cannot deadlock
  for v_line in
    select
      x.inventory_id,
      x.quantity,
      round(x.unit_cost, 2) as unit_cost,
      coalesce(x.keep_old_cost, false) as keep_old_cost,
      x.new_item
    from jsonb_to_recordset(p_lines) as x(inventory_id uuid, quantity integer, unit_cost numeric, keep_old_cost boolean, new_item jsonb)
    order by x.inventory_id nulls last
  loop
    if v_line.inventory_id is not null then
      select * into v_inv from public.inventory where id = v_line.inventory_id for update;
      if not found then
        raise exception 'A product on this bill no longer exists. Refresh and try again.';
      end if;
    else
      -- Way 2: a brand-new product, created inline from this same bill
      insert into public.inventory (
        category, brand, model, type, voltage, plates, ah_rating, wattage, warranty_months,
        cost_price, sale_price, quantity, reorder_level, hs_code, uom
      ) values (
        v_line.new_item->>'category',
        v_line.new_item->>'brand',
        v_line.new_item->>'model',
        nullif(v_line.new_item->>'type', ''),
        nullif(v_line.new_item->>'voltage', '')::numeric,
        nullif(v_line.new_item->>'plates', '')::integer,
        nullif(v_line.new_item->>'ah_rating', '')::numeric,
        nullif(v_line.new_item->>'wattage', '')::integer,
        nullif(v_line.new_item->>'warranty_months', '')::integer,
        v_line.unit_cost, coalesce(nullif(v_line.new_item->>'sale_price', '')::numeric, 0), 0,
        coalesce(nullif(v_line.new_item->>'reorder_level', '')::integer, 0),
        nullif(v_line.new_item->>'hs_code', ''),
        coalesce(nullif(v_line.new_item->>'uom', ''), 'Numbers, pieces, units')
      )
      returning id into v_new_inv_id;
      select * into v_inv from public.inventory where id = v_new_inv_id for update;
    end if;

    update public.inventory
       set quantity   = quantity + v_line.quantity,
           cost_price = case when v_line.keep_old_cost then cost_price else v_line.unit_cost end
     where id = v_inv.id;

    insert into public.stock_movements (inventory_id, change, reason, ref_table, ref_id)
    values (v_inv.id, v_line.quantity, 'purchase', 'purchase_invoices', v_purchase_id);

    v_line_total := round(v_line.quantity * v_line.unit_cost, 2);
    insert into public.purchase_items (purchase_id, inventory_id, description, quantity, unit_cost, line_total)
    values (
      v_purchase_id, v_inv.id,
      v_inv.brand || ' ' || v_inv.model || coalesce(', ' || nullif(v_inv.type, ''), ''),
      v_line.quantity, v_line.unit_cost, v_line_total
    );
  end loop;

  if v_paid > 0 then
    insert into public.supplier_payments (
      supplier_id, purchase_id, amount, method, paid_at, reference,
      cheque_number, cheque_date, bank_name, cheque_status
    ) values (
      v_supplier_id, v_purchase_id, v_paid, v_method, v_date, nullif(btrim(p_reference), ''),
      nullif(btrim(p_cheque_number), ''), p_cheque_date, nullif(btrim(p_bank_name), ''),
      case when v_method = 'cheque' then 'issued' else null end
    );
  end if;

  return v_purchase_id;
end;
$$;

-- ---------------------------------------------------------------- 8. cancel_purchase
-- Never a hard delete: marks Cancelled, reverses stock, and (via the ledger view reading status = Valid
-- only) drops out of the ledger. Refused if reversing would make any item's stock negative. Any
-- payments already made on this bill are left exactly as they are -- they stay in the ledger as an
-- on-account advance, because that money really did move.
create or replace function public.cancel_purchase(
  p_purchase_id uuid,
  p_reason      text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_purchase public.purchase_invoices%rowtype;
  v_item     record;
  v_inv      public.inventory%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Please sign in again.';
  end if;

  select * into v_purchase from public.purchase_invoices where id = p_purchase_id for update;
  if not found then
    raise exception 'This purchase bill could not be found.';
  end if;
  if v_purchase.status = 'Cancelled' then
    raise exception 'This purchase bill is already cancelled.';
  end if;

  for v_item in
    select inventory_id, quantity
    from public.purchase_items
    where purchase_id = p_purchase_id
    order by inventory_id
  loop
    select * into v_inv from public.inventory where id = v_item.inventory_id for update;
    if v_inv.quantity < v_item.quantity then
      raise exception 'Can''t cancel: % of ''%'' have already been sold. Use a purchase return instead.',
        (v_item.quantity - v_inv.quantity), (v_inv.brand || ' ' || v_inv.model);
    end if;
    update public.inventory set quantity = quantity - v_item.quantity where id = v_inv.id;
    insert into public.stock_movements (inventory_id, change, reason, ref_table, ref_id, note)
    values (v_inv.id, -v_item.quantity, 'purchase_cancel', 'purchase_invoices', p_purchase_id, nullif(btrim(p_reason), ''));
  end loop;

  update public.purchase_invoices
     set status = 'Cancelled', cancelled_at = now(), cancel_reason = nullif(btrim(p_reason), '')
   where id = p_purchase_id;
end;
$$;

-- ---------------------------------------------------------------- 9. supplier_summary (Home / Suppliers list)
create or replace function public.supplier_summary()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'total_owed',             coalesce((select sum(balance) from public.supplier_balances where balance > 0), 0),
    'suppliers_we_owe_count', (select count(*) from public.supplier_balances where balance > 0),
    'total_advance',          coalesce((select sum(-balance) from public.supplier_balances where balance < 0), 0),
    'suppliers_advance_count',(select count(*) from public.supplier_balances where balance < 0)
  );
$$;

-- ---------------------------------------------------------------- who can run the functions
revoke all on function public.create_purchase(
  uuid, uuid, text, text, text, text, date, text, jsonb, numeric, numeric, numeric, text, text, text, date, text
) from public, anon;
revoke all on function public.cancel_purchase(uuid, text) from public, anon;
revoke all on function public.supplier_summary() from public, anon;

grant execute on function public.create_purchase(
  uuid, uuid, text, text, text, text, date, text, jsonb, numeric, numeric, numeric, text, text, text, date, text
) to authenticated;
grant execute on function public.cancel_purchase(uuid, text) to authenticated;
grant execute on function public.supplier_summary() to authenticated;

-- ======== 07_supplier_save.sql ========
-- PowerCell POS App, Phase F1 Part 2: direct Supplier create/edit
-- Run once in Supabase SQL Editor, AFTER 12_suppliers_purchases.sql. Safe to run again.
--
-- Why this file exists: 12_suppliers_purchases.sql locked distributors down to
-- `grant select ... to authenticated` only -- every write goes through a security definer
-- function, same pattern as invoices. But it only ever writes a *new* supplier from inside
-- create_purchase() (name/phone/address only, no NTN or opening balance). The Suppliers list
-- needs its own Add/Edit screen (decision D12: owner enters opening balances per supplier
-- before go-live) with NTN and opening balance fields, which needs its own function.
--
-- No hard delete: `distributors` is shared with Battery claims (decision D1), and a supplier
-- with purchase history must never disappear from the audit trail. A supplier is deactivated
-- instead (is_active = false) -- it stays visible in history, drops out of the "pick a
-- supplier" list for new purchases, matching the existing friendlyDeleteError() copy
-- ("Mark it inactive instead") already shipped in Part 1's lib/invoices.ts.

-- ---------------------------------------------------------------- save_supplier (insert or update)
create or replace function public.save_supplier(
  p_id                   uuid,
  p_name                 text,
  p_phone                text,
  p_address              text,
  p_note                 text,
  p_ntn_or_cnic          text,
  p_opening_balance      numeric,
  p_opening_balance_date date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id   uuid;
  v_name text := nullif(btrim(p_name), '');
  v_ntn  text := nullif(btrim(p_ntn_or_cnic), '');
  v_ob   numeric(14,2) := round(coalesce(p_opening_balance, 0), 2);
begin
  if auth.uid() is null then
    raise exception 'Please sign in again.';
  end if;
  if v_name is null then
    raise exception 'Enter the supplier''s name.';
  end if;
  if v_ntn is not null and v_ntn !~ '^([0-9]{7}|[0-9]{13})$' then
    raise exception 'Use 7 digits for an NTN or 13 digits for a CNIC.';
  end if;
  if v_ob <> 0 and p_opening_balance_date is null then
    raise exception 'Add the "as of" date for the opening balance.';
  end if;

  if p_id is not null then
    if exists (select 1 from public.distributors where id <> p_id and lower(name) = lower(v_name)) then
      raise exception 'A supplier with this name already exists.';
    end if;
    update public.distributors set
      name                   = v_name,
      phone                  = nullif(btrim(p_phone), ''),
      address                = nullif(btrim(p_address), ''),
      note                   = nullif(btrim(p_note), ''),
      ntn_or_cnic             = v_ntn,
      opening_balance        = v_ob,
      opening_balance_date   = case when v_ob <> 0 then p_opening_balance_date else null end
    where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'This supplier could not be found.';
    end if;
  else
    if exists (select 1 from public.distributors where lower(name) = lower(v_name)) then
      raise exception 'A supplier with this name already exists.';
    end if;
    insert into public.distributors (
      name, phone, address, note, ntn_or_cnic, opening_balance, opening_balance_date, is_active
    ) values (
      v_name, nullif(btrim(p_phone), ''), nullif(btrim(p_address), ''), nullif(btrim(p_note), ''),
      v_ntn, v_ob, case when v_ob <> 0 then p_opening_balance_date else null end, true
    )
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.save_supplier(uuid, text, text, text, text, text, numeric, date) from public, anon;
grant execute on function public.save_supplier(uuid, text, text, text, text, text, numeric, date) to authenticated;

-- ---------------------------------------------------------------- set_supplier_active (soft "delete")
create or replace function public.set_supplier_active(p_id uuid, p_is_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Please sign in again.';
  end if;
  update public.distributors set is_active = coalesce(p_is_active, true) where id = p_id;
  if not found then
    raise exception 'This supplier could not be found.';
  end if;
end;
$$;

revoke all on function public.set_supplier_active(uuid, boolean) from public, anon;
grant execute on function public.set_supplier_active(uuid, boolean) to authenticated;

-- ======== 08_roles_and_audit.sql ========
-- =====================================================================================================
-- PowerCell POS App, Phase 8 - PART 1 of 2: team roles + activity log ("who did what")
-- Run once in Supabase: SQL Editor > New query > paste ALL > Run.   Safe to run again.
--
-- What this does:
--   1. Creates the team list (user_roles): each login gets a role - owner / counter_staff / accountant.
--   2. Makes YOUR existing login the Owner (so you can never be locked out).
--   3. Creates the activity log (audit_log) and switches it on for every business table.
--      From now on, every add / edit / delete of stock, customers, bills, payments, purchases,
--      supplier payments, expenses, suppliers, battery services, scrap, and team roles is written
--      down automatically, with WHO did it, WHEN, and WHAT changed.
--
-- What this does NOT do (that is Part 2): it does not restrict anybody yet. Nothing about how bills,
-- stock, prices or reports work changes. It only starts watching and remembering.
-- =====================================================================================================

-- ----------------------------------------------------------------------------------- 1. team list
create table if not exists public.user_roles (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  role       text not null check (role in ('owner', 'counter_staff', 'accountant')),
  full_name  text not null default '',
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists user_roles_set_updated_at on public.user_roles;
create trigger user_roles_set_updated_at
  before update on public.user_roles
  for each row execute function public.set_updated_at();

alter table public.user_roles enable row level security;
revoke all on public.user_roles from anon, authenticated;
grant select on public.user_roles to authenticated;

drop policy if exists "Users can read their own role" on public.user_roles;
create policy "Users can read their own role"
  on public.user_roles for select to authenticated using (user_id = auth.uid());

-- ----------------------------------------------------------------------------------- 2. make the owner the Owner
-- Your login (the one that exists today) becomes the Owner.
insert into public.user_roles (user_id, role, full_name)
select id, 'owner', 'Owner'
from auth.users
where lower(email) = 'sh.abdulrehmanrauf@gmail.com'
on conflict (user_id) do nothing;

-- Safety net: if that email was not found, the oldest login becomes the Owner instead.
insert into public.user_roles (user_id, role, full_name)
select id, 'owner', 'Owner'
from auth.users
where not exists (select 1 from public.user_roles where role = 'owner')
order by created_at
limit 1
on conflict (user_id) do nothing;

-- Last check: refuse to finish (and change nothing) if there is still no Owner.
do $$
begin
  if not exists (select 1 from public.user_roles where role = 'owner' and is_active) then
    raise exception 'No Owner could be created: there is no login in Supabase > Authentication > Users. Create your login first, then run this file again.';
  end if;
end $$;

-- ----------------------------------------------------------------------------------- 3. who am I? helpers
create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select ur.role from public.user_roles ur where ur.user_id = auth.uid() and ur.is_active
$$;

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_app_role() = 'owner', false)
$$;

-- What the app asks right after sign-in: my role, my name, is my account on.
create or replace function public.my_role_info()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select jsonb_build_object('role', ur.role, 'full_name', ur.full_name, 'is_active', ur.is_active)
       from public.user_roles ur where ur.user_id = auth.uid()),
    jsonb_build_object('role', null, 'full_name', null, 'is_active', false)
  )
$$;

-- ----------------------------------------------------------------------------------- 4. team management (Owner only)
create or replace function public.team_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then
    raise exception 'Only the Owner can see the team.';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'user_id',         u.id,
        'email',           u.email,
        'full_name',       coalesce(ur.full_name, ''),
        'role',            ur.role,
        'is_active',       coalesce(ur.is_active, false),
        'has_role',        ur.user_id is not null,
        'last_sign_in_at', u.last_sign_in_at,
        'created_at',      u.created_at
      )
      order by u.created_at
    )
    from auth.users u
    left join public.user_roles ur on ur.user_id = u.id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.set_user_role(
  p_user_id   uuid,
  p_role      text,
  p_full_name text,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_active boolean := coalesce(p_is_active, true);
  v_name   text    := btrim(coalesce(p_full_name, ''));
begin
  if not public.is_owner() then
    raise exception 'Only the Owner can change roles.';
  end if;
  if p_user_id is null or not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'That login could not be found.';
  end if;
  if p_role is null or p_role not in ('owner', 'counter_staff', 'accountant') then
    raise exception 'Choose Owner, Counter staff or Accountant.';
  end if;
  if v_name = '' then
    raise exception 'Enter the person''s name, so the activity log can show who did what.';
  end if;
  if p_user_id = auth.uid() and not v_active then
    raise exception 'You cannot turn off your own account.';
  end if;

  -- The shop must always keep at least one active Owner.
  if (p_role <> 'owner' or not v_active)
     and exists (select 1 from public.user_roles where user_id = p_user_id and role = 'owner' and is_active)
     and not exists (select 1 from public.user_roles where role = 'owner' and is_active and user_id <> p_user_id) then
    raise exception 'There must always be at least one active Owner.';
  end if;

  insert into public.user_roles (user_id, role, full_name, is_active)
  values (p_user_id, p_role, v_name, v_active)
  on conflict (user_id) do update
    set role = excluded.role,
        full_name = excluded.full_name,
        is_active = excluded.is_active;
end;
$$;

-- Names only (no emails): lets any signed-in screen show "Made by Ali".
create or replace function public.user_display_names(p_ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_object_agg(
      u.id::text,
      coalesce(nullif(btrim(ur.full_name), ''), split_part(u.email, '@', 1))
    ),
    '{}'::jsonb
  )
  from auth.users u
  left join public.user_roles ur on ur.user_id = u.id
  where u.id = any (coalesce(p_ids, '{}'::uuid[]))
$$;

-- ----------------------------------------------------------------------------------- 5. the activity log
create table if not exists public.audit_log (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  actor_id        uuid,                                   -- who (kept even if the login is later deleted)
  actor_name      text not null default 'Unknown',
  actor_email     text,
  actor_role      text,
  action          text not null check (action in ('create', 'update', 'delete')),
  table_name      text not null,
  record_id       text,
  summary         text not null,                          -- plain-language sentence shown on the Activity screen
  changed_fields  text[],
  old_data        jsonb,
  new_data        jsonb,
  is_detail       boolean not null default false,         -- automatic side effects (stock change from a sale, bill lines)
  is_side_effect  boolean not null default false,
  txid            bigint not null default txid_current()  -- rows saved by the same click share this
);

create index if not exists audit_log_created_idx on public.audit_log (created_at desc);
create index if not exists audit_log_actor_idx   on public.audit_log (actor_id, created_at desc);
create index if not exists audit_log_table_idx   on public.audit_log (table_name, created_at desc);
create index if not exists audit_log_txid_idx    on public.audit_log (txid);

alter table public.audit_log enable row level security;
revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;      -- nobody can insert, edit or delete from the browser

drop policy if exists "Owner can read the activity log" on public.audit_log;
create policy "Owner can read the activity log"
  on public.audit_log for select to authenticated using (public.is_owner());

-- ----------------------------------------------------------------------------------- 6. wording helpers
create or replace function public.audit_rs(p_n numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_n is null then '?'
              else 'Rs ' || regexp_replace(to_char(p_n, 'FM999,999,999,990.99'), '\.$', '') end
$$;

create or replace function public.audit_val(p_key text, p_val text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_val is null then
    return '(empty)';
  end if;
  if p_key = any (array['cost_price','sale_price','price','total_value','subtotal','discount','freight','amount',
                        'handover_amount','claim_amount','extra_charges','opening_balance','unit_cost','line_total',
                        'rate','total_amount','rate_per_kg'])
     and p_val ~ '^-?[0-9]+(\.[0-9]+)?$' then
    return public.audit_rs(p_val::numeric);
  end if;
  return left(p_val, 40);
end;
$$;

-- Turns one database change into one plain sentence.
create or replace function public.audit_describe(
  p_table   text,
  p_action  text,
  p_old     jsonb,
  p_new     jsonb,
  p_changed text[]
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  r         jsonb := coalesce(p_new, p_old);
  v_label   text;
  v_name    text := '';
  v_extra   text := '';
  v_prefix  text := 'Added';
  v_tmp     text;
  v_deltas  text;
begin
  case p_table
    when 'inventory' then
      v_label := 'stock item';
      v_name  := btrim(coalesce(r->>'brand', '') || ' ' || coalesce(r->>'model', ''));
      v_extra := 'quantity ' || coalesce(r->>'quantity', '?') || ', sale price ' || public.audit_rs((r->>'sale_price')::numeric);
    when 'customers' then
      v_label := 'customer';
      v_name  := coalesce(r->>'name', '');
    when 'invoices' then
      v_label := 'bill'; v_prefix := 'Made';
      v_name  := coalesce(r->>'invoice_number', '') || ' for ' || coalesce(r->>'buyer_name', '');
      v_extra := public.audit_rs((r->>'total_value')::numeric) || ' (' || coalesce(r->>'payment_status', '?') || ')';
    when 'invoice_items' then
      v_label := 'bill line';
      v_name  := coalesce(r->>'description', '');
      v_extra := coalesce(r->>'quantity', '?') || ' x ' || public.audit_rs((r->>'rate')::numeric);
    when 'payments' then
      v_label := 'payment'; v_prefix := 'Received';
      select invoice_number into v_tmp from public.invoices where id = nullif(r->>'invoice_id', '')::uuid;
      v_name  := public.audit_rs((r->>'amount')::numeric) || ' (' || coalesce(r->>'method', '?') || ') on bill ' || coalesce(v_tmp, '?');
    when 'purchase_invoices' then
      v_label := 'purchase bill'; v_prefix := 'Recorded';
      select name into v_tmp from public.distributors where id = nullif(r->>'supplier_id', '')::uuid;
      v_name  := coalesce(r->>'purchase_number', '') || ' from ' || coalesce(v_tmp, '?');
      v_extra := public.audit_rs((r->>'total_value')::numeric);
    when 'purchase_items' then
      v_label := 'purchase line';
      v_name  := coalesce(r->>'description', '');
      v_extra := coalesce(r->>'quantity', '?') || ' x ' || public.audit_rs((r->>'unit_cost')::numeric);
    when 'supplier_payments' then
      v_label := 'supplier payment'; v_prefix := 'Recorded';
      select name into v_tmp from public.distributors where id = nullif(r->>'supplier_id', '')::uuid;
      v_name  := coalesce(r->>'payment_number', '') || ' to ' || coalesce(v_tmp, '?');
      v_extra := public.audit_rs((r->>'amount')::numeric) || ' (' || coalesce(r->>'method', '?') || ')';
    when 'expenses' then
      v_label := 'expense'; v_prefix := 'Recorded';
      select name into v_tmp from public.expense_categories where id = nullif(r->>'category_id', '')::uuid;
      v_name  := coalesce(r->>'expense_number', '') || ' - ' || coalesce(v_tmp, '?');
      v_extra := public.audit_rs((r->>'amount')::numeric) || coalesce(', to ' || nullif(r->>'paid_to', ''), '');
    when 'distributors' then
      v_label := 'supplier';
      v_name  := coalesce(r->>'name', '');
    when 'charging_jobs' then
      v_label := 'charging slip'; v_prefix := 'Made';
      v_name  := coalesce(r->>'slip_number', '') || ' - ' || coalesce(r->>'customer_name', '')
                 || ' (' || btrim(coalesce(r->>'battery_brand', '') || ' ' || coalesce(r->>'battery_model', '')) || ')';
      v_extra := public.audit_rs((r->>'price')::numeric);
    when 'battery_claims' then
      v_label := 'battery claim'; v_prefix := 'Made';
      v_name  := coalesce(r->>'claim_number', '') || ' - ' || coalesce(r->>'customer_name', '')
                 || ' (' || btrim(coalesce(r->>'battery_brand', '') || ' ' || coalesce(r->>'battery_model', '')) || ')';
    when 'scrap_battery_inventory' then
      v_label := 'scrap batch'; v_prefix := 'Took in';
      v_name  := coalesce(r->>'intake_number', '') || ' - ' || btrim(coalesce(r->>'brand', '') || ' ' || coalesce(r->>'model', ''));
      v_extra := 'quantity ' || coalesce(r->>'quantity', '?');
    when 'scrap_battery_sales' then
      v_label := 'scrap sale'; v_prefix := 'Made';
      v_name  := coalesce(r->>'sale_number', '') || ' to ' || coalesce(r->>'buyer_name', '');
      v_extra := public.audit_rs((r->>'total_amount')::numeric);
    when 'cash_settings' then
      v_label := 'cash opening balance';
      v_extra := public.audit_rs((r->>'opening_balance')::numeric) || ' as of ' || coalesce(r->>'opening_date', '?');
    when 'business_profile' then
      v_label := 'shop details';
    when 'charging_price_list' then
      v_label := 'charging price';
      v_name  := coalesce(r->>'name', r->>'label', r->>'battery_type', r->>'description', '');
    when 'user_roles' then
      v_label := 'team member';
      v_name  := coalesce(r->>'full_name', '');
      v_extra := 'role ' || coalesce(r->>'role', '?') || case when (r->>'is_active') = 'false' then ', account turned off' else '' end;
    else
      v_label := replace(p_table, '_', ' ');
  end case;

  if p_action = 'delete' then
    return btrim('Deleted ' || v_label || ' ' || v_name);
  end if;

  if p_action = 'create' then
    return btrim(v_prefix || ' ' || v_label || ' ' || v_name)
           || case when v_extra <> '' then ' - ' || v_extra else '' end;
  end if;

  -- update
  if 'status' = any (p_changed) and p_new->>'status' = 'Cancelled' then
    return btrim('Cancelled ' || v_label || ' ' || v_name)
           || coalesce(' - reason: ' || nullif(btrim(p_new->>'cancel_reason'), ''), '');
  end if;

  select string_agg(
           replace(s.k, '_', ' ') || ': ' || public.audit_val(s.k, p_old->>s.k) || ' -> ' || public.audit_val(s.k, p_new->>s.k),
           ', ' order by s.k)
    into v_deltas
    from (
      select k
      from unnest(p_changed) as k
      where k <> all (array['updated_at','created_at','created_by','id','client_id','cancelled_at'])
      order by k
      limit 6
    ) s;

  return btrim('Edited ' || v_label || ' ' || v_name) || case when v_deltas is not null then ': ' || v_deltas else '' end;
end;
$$;

-- ----------------------------------------------------------------------------------- 7. the recorder
-- Runs after every add / edit / delete on the business tables. If writing the log ever fails,
-- the shop's work is NOT blocked (a warning is raised instead).
create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old     jsonb;
  v_new     jsonb;
  v_row     jsonb;
  v_changed text[];
  v_action  text;
  v_uid     uuid := auth.uid();
  v_name    text;
  v_email   text;
  v_role    text;
  v_summary text;
  v_side    boolean := false;
  v_detail  boolean := false;
  v_tx      bigint := txid_current();
  v_record  text;
begin
  begin
    if tg_op = 'INSERT' then
      v_action := 'create';
      v_new := to_jsonb(new);
      v_row := v_new;
    elsif tg_op = 'UPDATE' then
      v_action := 'update';
      v_old := to_jsonb(old);
      v_new := to_jsonb(new);
      v_row := v_new;
      select coalesce(array_agg(k order by k), '{}'::text[])
        into v_changed
        from jsonb_object_keys(v_new) as k
       where k <> 'updated_at' and (v_old -> k) is distinct from (v_new -> k);
      if coalesce(array_length(v_changed, 1), 0) = 0 then
        return null;                       -- nothing really changed (e.g. a re-sync): do not log
      end if;
    else
      v_action := 'delete';
      v_old := to_jsonb(old);
      v_row := v_old;
    end if;

    v_record := v_row ->> 'id';

    if v_uid is not null then
      select coalesce(nullif(btrim(ur.full_name), ''), split_part(au.email, '@', 1)), au.email, ur.role
        into v_name, v_email, v_role
        from auth.users au
        left join public.user_roles ur on ur.user_id = au.id
       where au.id = v_uid;
    end if;
    v_name := coalesce(v_name, case when v_uid is null then 'System (database)' else 'Unknown user' end);

    -- Automatic knock-on changes are kept, but tucked away by default on the Activity screen.
    if tg_op = 'UPDATE' then
      v_side := coalesce(case tg_table_name
        when 'inventory'               then v_changed <@ array['quantity', 'cost_price']
        when 'invoices'                then v_changed <@ array['payment_status']
        when 'scrap_battery_inventory' then v_changed <@ array['status', 'sold_in_sale_id']
        else false
      end, false);
    end if;
    v_detail := tg_table_name in ('invoice_items', 'purchase_items');
    if v_side then
      v_detail := exists (
        select 1 from public.audit_log a
         where a.txid = v_tx and not a.is_side_effect and not a.is_detail
      );
    end if;

    begin
      v_summary := public.audit_describe(tg_table_name, v_action, v_old, v_new, v_changed);
    exception when others then
      v_summary := initcap(v_action) || ' in ' || replace(tg_table_name, '_', ' ');
    end;

    insert into public.audit_log (
      actor_id, actor_name, actor_email, actor_role, action, table_name, record_id,
      summary, changed_fields, old_data, new_data, is_detail, is_side_effect, txid
    ) values (
      v_uid, v_name, v_email, v_role, v_action, tg_table_name, v_record,
      v_summary, v_changed, v_old, v_new, v_detail, v_side, v_tx
    );

    -- A real action just happened: earlier knock-on rows of the same click become "details".
    if not v_side and not v_detail then
      update public.audit_log
         set is_detail = true
       where txid = v_tx and is_side_effect and not is_detail;
    end if;
  exception when others then
    raise warning 'Activity log could not be written: %', sqlerrm;
  end;

  return null;
end;
$$;

-- ----------------------------------------------------------------------------------- 8. switch the recorder on
do $$
declare
  t text;
begin
  foreach t in array array[
    'inventory', 'customers', 'invoices', 'invoice_items', 'payments',
    'purchase_invoices', 'purchase_items', 'supplier_payments', 'expenses', 'distributors',
    'charging_jobs', 'charging_price_list', 'battery_claims',
    'scrap_battery_inventory', 'scrap_battery_sales',
    'cash_settings', 'business_profile', 'user_roles'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists zz_audit_row_change on public.%I', t);
      execute format(
        'create trigger zz_audit_row_change after insert or update or delete on public.%I
           for each row execute function public.audit_row_change()', t);
    else
      raise notice 'Table % not found - skipped.', t;
    end if;
  end loop;
end $$;

-- ----------------------------------------------------------------------------------- 9. who may call what
revoke all on function public.current_app_role()                      from public, anon;
revoke all on function public.is_owner()                              from public, anon;
revoke all on function public.my_role_info()                          from public, anon;
revoke all on function public.team_list()                             from public, anon;
revoke all on function public.set_user_role(uuid, text, text, boolean) from public, anon;
revoke all on function public.user_display_names(uuid[])              from public, anon;
grant execute on function public.current_app_role()                      to authenticated;
grant execute on function public.is_owner()                              to authenticated;
grant execute on function public.my_role_info()                          to authenticated;
grant execute on function public.team_list()                             to authenticated;
grant execute on function public.set_user_role(uuid, text, text, boolean) to authenticated;
grant execute on function public.user_display_names(uuid[])              to authenticated;

-- Internal helpers: only the database itself may use these.
revoke all on function public.audit_rs(numeric)                                   from public, anon, authenticated;
revoke all on function public.audit_val(text, text)                               from public, anon, authenticated;
revoke all on function public.audit_describe(text, text, jsonb, jsonb, text[])    from public, anon, authenticated;
revoke all on function public.audit_row_change()                                  from public, anon, authenticated;

-- Done. Check: select * from public.user_roles;   (you should see yourself as owner)

-- ======== 09_role_enforcement.sql ========
-- =====================================================================================================
-- PowerCell POS App, Phase 8 - PART 2 of 2: role enforcement in the database
-- Run ONLY after 16_roles_and_audit.sql has been run and your Team page shows you as Owner.
-- Run once in Supabase: SQL Editor > New query > paste ALL > Run.   Safe to run again.
--
-- After this file, the DATABASE itself refuses what a role may not do - even if someone bypasses the
-- screens. Rules (same as lib/roles.ts):
--   Owner          everything
--   Counter staff  make bills at the listed price, receive customer payments, add/edit customers,
--                  battery services, scrap intake. NOT: change prices, add/edit/delete stock,
--                  delete or cancel anything, purchases, suppliers, expenses, reports, scrap sales.
--   Accountant     read everything financial; record expenses, supplier payments, cash opening balance.
--                  NOT: make bills, change stock, customers, purchases.
--   No role / turned off   cannot read or write anything.
--
-- Changes made in the Supabase SQL Editor / dashboard (no signed-in user) are never blocked.
-- =====================================================================================================

-- ----------------------------------------------------------------------------------- 1. helpers
create or replace function public.role_in(p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_app_role() = any (p_roles), false)
$$;
revoke all on function public.role_in(text[]) from public, anon;
grant execute on function public.role_in(text[]) to authenticated;

-- ----------------------------------------------------------------------------------- 2. the write guard
-- Attached to tables that are only written through the app's database functions.
-- Arguments: who may INSERT, who may UPDATE, who may DELETE (each a comma list of roles, '' = nobody).
create or replace function public.role_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role    text;
  v_allowed text;
  v_verb    text;
begin
  if auth.uid() is null then                 -- SQL editor / dashboard / server job: not a shop user
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  v_allowed := case tg_op when 'INSERT' then tg_argv[0] when 'UPDATE' then tg_argv[1] else tg_argv[2] end;
  v_verb    := case tg_op when 'INSERT' then 'add' when 'UPDATE' then 'change' else 'delete' end;
  v_role    := public.current_app_role();

  if v_role is null then
    raise exception 'Your account has no access. Ask the Owner to check your role in Team.' using errcode = '42501';
  end if;

  if v_role <> all (string_to_array(coalesce(v_allowed, ''), ',')) then
    raise exception 'Your role (%) is not allowed to % this (%). Ask the Owner.',
      case v_role when 'counter_staff' then 'Counter staff' when 'accountant' then 'Accountant' else v_role end,
      v_verb,
      replace(tg_table_name, '_', ' ')
      using errcode = '42501';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke all on function public.role_guard() from public, anon, authenticated;

-- Counter staff may only bill at the price on the stock list.
create or replace function public.invoice_price_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_price numeric;
begin
  if auth.uid() is null or public.current_app_role() is distinct from 'counter_staff' then
    return new;
  end if;
  select sale_price into v_price from public.inventory where id = new.inventory_id;
  if v_price is not null and new.rate is distinct from v_price then
    raise exception 'The price of % is % (you entered %). Counter staff cannot change prices. Refresh the page if the Owner changed the price.',
      new.description, public.audit_rs(v_price), public.audit_rs(new.rate)
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.invoice_price_guard() from public, anon, authenticated;

do $$
declare
  r record;
begin
  for r in
    select * from (values
      -- table                     insert                            update                            delete
      ('invoices',                'owner,counter_staff',            'owner,counter_staff',            'owner'),
      ('invoice_items',           'owner,counter_staff',            'owner',                          'owner'),
      ('payments',                'owner,counter_staff',            'owner',                          'owner'),
      ('purchase_invoices',       'owner',                          'owner',                          'owner'),
      ('purchase_items',          'owner',                          'owner',                          'owner'),
      ('supplier_payments',       'owner,accountant',               'owner,accountant',               'owner'),
      ('expenses',                'owner,accountant',               'owner,accountant',               'owner'),
      ('distributors',            'owner,counter_staff',            'owner',                          'owner'),
      ('charging_jobs',           'owner,counter_staff',            'owner,counter_staff',            'owner'),
      ('battery_claims',          'owner,counter_staff',            'owner,counter_staff',            'owner'),
      ('scrap_battery_inventory', 'owner,counter_staff',            'owner,counter_staff',            'owner'),
      ('scrap_battery_sales',     'owner',                          'owner',                          'owner'),
      ('cash_settings',           'owner,accountant',               'owner,accountant',               'owner'),
      ('business_profile',        'owner',                          'owner',                          'owner')
    ) as v(tbl, ins, upd, del)
  loop
    if to_regclass('public.' || r.tbl) is not null then
      execute format('drop trigger if exists aa_role_guard on public.%I', r.tbl);
      execute format(
        'create trigger aa_role_guard before insert or update or delete on public.%I
           for each row execute function public.role_guard(%L, %L, %L)', r.tbl, r.ins, r.upd, r.del);
    else
      raise notice 'Table % not found - skipped.', r.tbl;
    end if;
  end loop;
end $$;

drop trigger if exists aa_price_guard on public.invoice_items;
create trigger aa_price_guard
  before insert on public.invoice_items
  for each row execute function public.invoice_price_guard();

-- ----------------------------------------------------------------------------------- 3. direct-write tables (row rules)
-- inventory / customers / charging prices are saved straight from the screens, so they get row rules.
-- (Bills and purchases still change stock quantity through their own database functions - those are allowed.)
alter table public.inventory enable row level security;
drop policy if exists "Signed-in users can add inventory"    on public.inventory;
drop policy if exists "Signed-in users can edit inventory"   on public.inventory;
drop policy if exists "Signed-in users can delete inventory" on public.inventory;
drop policy if exists "Signed-in users can view inventory"   on public.inventory;
drop policy if exists "Owner can add inventory"    on public.inventory;
drop policy if exists "Owner can edit inventory"   on public.inventory;
drop policy if exists "Owner can delete inventory" on public.inventory;
drop policy if exists "Team can view inventory"    on public.inventory;
create policy "Team can view inventory"   on public.inventory for select to authenticated using ((select public.current_app_role()) is not null);
create policy "Owner can add inventory"   on public.inventory for insert to authenticated with check ((select public.current_app_role()) = 'owner');
create policy "Owner can edit inventory"  on public.inventory for update to authenticated
  using ((select public.current_app_role()) = 'owner') with check ((select public.current_app_role()) = 'owner');
create policy "Owner can delete inventory" on public.inventory for delete to authenticated using ((select public.current_app_role()) = 'owner');

alter table public.customers enable row level security;
drop policy if exists "Signed-in users can add customers"    on public.customers;
drop policy if exists "Signed-in users can edit customers"   on public.customers;
drop policy if exists "Signed-in users can delete customers" on public.customers;
drop policy if exists "Signed-in users can view customers"   on public.customers;
drop policy if exists "Owner and counter staff can add customers"  on public.customers;
drop policy if exists "Owner and counter staff can edit customers" on public.customers;
drop policy if exists "Owner can delete customers" on public.customers;
drop policy if exists "Team can view customers"    on public.customers;
create policy "Team can view customers" on public.customers for select to authenticated using ((select public.current_app_role()) is not null);
create policy "Owner and counter staff can add customers" on public.customers for insert to authenticated
  with check ((select public.current_app_role()) in ('owner', 'counter_staff'));
create policy "Owner and counter staff can edit customers" on public.customers for update to authenticated
  using ((select public.current_app_role()) in ('owner', 'counter_staff'))
  with check ((select public.current_app_role()) in ('owner', 'counter_staff'));
create policy "Owner can delete customers" on public.customers for delete to authenticated using ((select public.current_app_role()) = 'owner');

do $$
begin
  if to_regclass('public.charging_price_list') is not null then
    execute 'alter table public.charging_price_list enable row level security';
    execute 'drop policy if exists "Signed-in users can add charging prices"    on public.charging_price_list';
    execute 'drop policy if exists "Signed-in users can edit charging prices"   on public.charging_price_list';
    execute 'drop policy if exists "Signed-in users can delete charging prices" on public.charging_price_list';
    execute 'drop policy if exists "Signed-in users can view charging prices"   on public.charging_price_list';
    execute 'drop policy if exists "Owner can add charging prices"    on public.charging_price_list';
    execute 'drop policy if exists "Owner can edit charging prices"   on public.charging_price_list';
    execute 'drop policy if exists "Owner can delete charging prices" on public.charging_price_list';
    execute 'drop policy if exists "Team can view charging prices"    on public.charging_price_list';
    execute 'create policy "Team can view charging prices" on public.charging_price_list for select to authenticated using ((select public.current_app_role()) is not null)';
    execute 'create policy "Owner can add charging prices" on public.charging_price_list for insert to authenticated with check ((select public.current_app_role()) = ''owner'')';
    execute 'create policy "Owner can edit charging prices" on public.charging_price_list for update to authenticated using ((select public.current_app_role()) = ''owner'') with check ((select public.current_app_role()) = ''owner'')';
    execute 'create policy "Owner can delete charging prices" on public.charging_price_list for delete to authenticated using ((select public.current_app_role()) = ''owner'')';
  end if;
end $$;

-- ----------------------------------------------------------------------------------- 4. who may READ each table
-- Everyday tables: any active team member. Money-side tables: Owner and Accountant only.
do $$
declare
  r record;
begin
  for r in
    select * from (values
      -- table, old policy names to remove (pipe-separated), who may read
      ('invoices',                 'Signed-in users can view invoices',                 'all'),
      ('invoice_items',            'Signed-in users can view invoice items',            'all'),
      ('payments',                 'Signed-in users can view payments',                 'all'),
      ('business_profile',         'Signed-in users can view business profile',         'all'),
      ('battery_claims',           'Signed-in users can view battery claims',           'all'),
      ('charging_jobs',            'Signed-in users can view charging jobs',            'all'),
      ('scrap_battery_inventory',  'Signed-in users can view scrap inventory',          'all'),
      ('scrap_battery_sales',      'Signed-in users can view scrap sales',              'all'),
      ('distributors',             'Signed-in users can view distributors|Signed-in users can view suppliers', 'all'),
      ('expense_categories',       'Signed-in users can view expense categories',       'all'),
      ('purchase_invoices',        'Signed-in users can view purchase invoices',        'money'),
      ('purchase_items',           'Signed-in users can view purchase items',           'money'),
      ('supplier_payments',        'Signed-in users can view supplier payments',        'money'),
      ('expenses',                 'Signed-in users can view expenses',                 'money'),
      ('cash_settings',            'Signed-in users can view cash settings',            'money'),
      ('stock_movements',          'Signed-in users can view stock movements',          'money')
    ) as v(tbl, old_names, who)
  loop
    if to_regclass('public.' || r.tbl) is null then
      raise notice 'Table % not found - skipped.', r.tbl;
      continue;
    end if;
    declare
      n text;
    begin
      foreach n in array string_to_array(r.old_names, '|') loop
        execute format('drop policy if exists %I on public.%I', n, r.tbl);
      end loop;
      execute format('drop policy if exists %I on public.%I', 'Team can view ' || r.tbl, r.tbl);
      if r.who = 'all' then
        execute format(
          'create policy %I on public.%I for select to authenticated using ((select public.current_app_role()) is not null)',
          'Team can view ' || r.tbl, r.tbl);
      else
        execute format(
          'create policy %I on public.%I for select to authenticated using ((select public.current_app_role()) in (''owner'', ''accountant''))',
          'Team can view ' || r.tbl, r.tbl);
      end if;
    end;
  end loop;
end $$;

-- ----------------------------------------------------------------------------------- 5. reports: Owner and Accountant only
-- The original report functions are kept (renamed with a leading underscore) and locked away;
-- a thin wrapper with the SAME name and inputs checks the role and then calls the original.
-- Do not run 05_reports.sql or 15_cash_book.sql again after this - it would replace the wrappers.
do $$
declare
  f record;
begin
  for f in
    select * from (values
      ('report_summary',    'date, date, text'),
      ('financial_summary', 'date, date'),
      ('cash_book_summary', 'date, date'),
      ('supplier_summary',  '')
    ) as v(fname, args)
  loop
    if to_regprocedure(format('public.%s(%s)', f.fname, f.args)) is null then
      raise notice 'Function %(%) not found - skipped.', f.fname, f.args;
      continue;
    end if;
    if to_regprocedure(format('public._core_%s(%s)', f.fname, f.args)) is null then
      execute format('alter function public.%s(%s) rename to _core_%s', f.fname, f.args, f.fname);
    end if;
    execute format('revoke all on function public._core_%s(%s) from public, anon, authenticated', f.fname, f.args);
  end loop;
end $$;

do $$
begin
  if to_regprocedure('public._core_report_summary(date, date, text)') is not null then
    create or replace function public.report_summary(p_from date, p_to date, p_bucket text default 'day')
    returns jsonb language plpgsql security definer set search_path = '' as $f$
    begin
      if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
        raise exception 'Reports are only for the Owner and the Accountant.' using errcode = '42501';
      end if;
      return public._core_report_summary(p_from, p_to, p_bucket);
    end $f$;
    revoke all on function public.report_summary(date, date, text) from public, anon;
    grant execute on function public.report_summary(date, date, text) to authenticated;
  end if;

  if to_regprocedure('public._core_financial_summary(date, date)') is not null then
    create or replace function public.financial_summary(p_from date, p_to date)
    returns jsonb language plpgsql security definer set search_path = '' as $f$
    begin
      if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
        raise exception 'Reports are only for the Owner and the Accountant.' using errcode = '42501';
      end if;
      return public._core_financial_summary(p_from, p_to);
    end $f$;
    revoke all on function public.financial_summary(date, date) from public, anon;
    grant execute on function public.financial_summary(date, date) to authenticated;
  end if;

  if to_regprocedure('public._core_cash_book_summary(date, date)') is not null then
    create or replace function public.cash_book_summary(p_from date, p_to date)
    returns jsonb language plpgsql security definer set search_path = '' as $f$
    begin
      if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
        raise exception 'Reports are only for the Owner and the Accountant.' using errcode = '42501';
      end if;
      return public._core_cash_book_summary(p_from, p_to);
    end $f$;
    revoke all on function public.cash_book_summary(date, date) from public, anon;
    grant execute on function public.cash_book_summary(date, date) to authenticated;
  end if;

  if to_regprocedure('public._core_supplier_summary()') is not null then
    create or replace function public.supplier_summary()
    returns jsonb language plpgsql security definer set search_path = '' as $f$
    begin
      if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
        raise exception 'Supplier totals are only for the Owner and the Accountant.' using errcode = '42501';
      end if;
      return public._core_supplier_summary();
    end $f$;
    revoke all on function public.supplier_summary() from public, anon;
    grant execute on function public.supplier_summary() to authenticated;
  end if;
end $$;

-- Done. Check: select * from public.user_roles;  (you must still be 'owner' and active)

-- ======== 10_fbr.sql ========
-- =====================================================================================================
-- PowerCell POS App, FBR Digital Invoicing, Phase D1: database  (file name: 18_fbr.sql)
-- Run ONCE in Supabase: SQL Editor > New query > paste ALL > Run.   Safe to run again.
--
-- Run this AFTER 01, 02, 03, 12, 16 and 17 (you already have them).
-- (The plan called this file "16_fbr.sql", but 16 and 17 are already used by roles and audit.)
--
-- What this does:
--   1. Adds FBR settings to business_profile (off by default).
--   2. Adds a province to customers, and FBR tax setup fields to inventory.
--   3. Creates the FBR tables: fbr_invoices, fbr_invoice_items, fbr_submissions,
--      fbr_reference, fbr_heartbeat.
--   4. Creates create_fbr_bill(): a wrapper that calls the EXISTING create_invoice() in the same
--      transaction, then saves the FBR record. If anything fails, nothing is saved.
--
-- What this does NOT do:
--   * It does not change create_invoice(), record_payment(), or any existing bill, payment,
--     stock movement or report. Old bills stay normal bills.
--   * It does not send anything to FBR. The sender (Phase D4) does that later.
--   * Nothing changes on screen until Phase D2. FBR stays OFF (fbr_enabled = false).
-- =====================================================================================================

-- ----------------------------------------------------------------------------------- 0. safety check
do $$
begin
  if to_regprocedure('public.role_in(text[])') is null then
    raise exception 'Run 16_roles_and_audit.sql and 17_role_enforcement.sql first (role_in() is missing).';
  end if;
  -- Your live create_invoice() has extra walk-in inputs (phone, address, registration type, CNIC),
  -- so we look it up by name instead of by one exact list of inputs.
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'create_invoice'
  ) then
    raise exception 'Run 03_invoices.sql first (create_invoice() is missing).';
  end if;
end $$;

-- ----------------------------------------------------------------------------------- 1. business_profile
alter table public.business_profile
  add column if not exists fbr_enabled       boolean not null default false,
  add column if not exists fbr_environment   text    not null default 'sandbox',
  add column if not exists prices_include_tax boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'business_profile_fbr_environment_check'
      and conrelid = 'public.business_profile'::regclass
  ) then
    alter table public.business_profile
      add constraint business_profile_fbr_environment_check
      check (fbr_environment in ('sandbox', 'production'));
  end if;
end $$;

comment on column public.business_profile.prices_include_tax is
  'false = GST is added on top of the selling price (owner decision). Third Schedule items ignore this.';

-- ----------------------------------------------------------------------------------- 2. customers + inventory
alter table public.customers
  add column if not exists province text;   -- exact FBR spelling, e.g. Sindh

alter table public.inventory
  add column if not exists sale_type          text not null default 'Goods at standard rate (default)',
  add column if not exists fbr_rate_desc      text,                       -- e.g. '18%', '10%'. Set per item.
  add column if not exists is_taxable         boolean not null default true,
  add column if not exists retail_price       numeric(14,2),              -- printed price, Third Schedule items
  add column if not exists sro_schedule_no    text,
  add column if not exists sro_item_serial_no text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'inventory_retail_price_check' and conrelid = 'public.inventory'::regclass
  ) then
    alter table public.inventory
      add constraint inventory_retail_price_check check (retail_price is null or retail_price >= 0);
  end if;
end $$;

-- Rates are NEVER hard-coded in the app. They come from these item settings (later from the FBR lists).
-- Optional, do it later from the Inventory screen (Phase D3), or in the SQL editor once the accountant agrees:
--   update public.inventory set fbr_rate_desc = '18%' where category = 'accessory';
--   update public.inventory set fbr_rate_desc = '10%', sale_type = 'Goods at Reduced Rate' where category = 'panel';

-- ----------------------------------------------------------------------------------- 3. FBR tables
-- 3a. one row per FBR bill
create table if not exists public.fbr_invoices (
  invoice_id         uuid primary key references public.invoices (id) on delete restrict,
  environment        text not null default 'sandbox' check (environment in ('sandbox', 'production')),
  buyer_province     text,
  buyer_address      text,
  invoice_ref_no     text,                 -- debit notes only
  scenario_id        text,                 -- sandbox only
  fbr_status         text not null default 'pending'
                       check (fbr_status in ('pending', 'sending', 'sent', 'failed', 'unknown')),
  fbr_invoice_number text unique,
  submitted_at       timestamptz,
  error_code         text,
  error_message      text,
  attempts           integer not null default 0,
  next_retry_at      timestamptz,
  created_offline    boolean not null default false,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists fbr_invoices_status_idx on public.fbr_invoices (fbr_status, created_at);

-- 3b. one row per line: the FBR numbers exactly as they will be sent
create table if not exists public.fbr_invoice_items (
  invoice_item_id     uuid primary key references public.invoice_items (id) on delete cascade,
  invoice_id          uuid not null references public.invoices (id) on delete cascade,
  hs_code             text,
  product_description text,
  fbr_rate_desc       text,                -- FBR "rate", e.g. '18%'. NOT our price.
  uom                 text,
  quantity            numeric(14,4),
  total_values        numeric(14,2),
  value_sales_excl_st numeric(14,2),
  fixed_notified_value numeric(14,2),
  sales_tax_applicable numeric(14,2),
  sales_tax_withheld  numeric(14,2) not null default 0,
  extra_tax           numeric(14,2) not null default 0,
  further_tax         numeric(14,2) not null default 0,
  fed_payable         numeric(14,2) not null default 0,
  discount            numeric(14,2) not null default 0,
  sro_schedule_no     text,
  sro_item_serial_no  text,
  sale_type           text
);
create index if not exists fbr_invoice_items_invoice_idx on public.fbr_invoice_items (invoice_id);

-- 3c. log of every try
create table if not exists public.fbr_submissions (
  id              uuid primary key default gen_random_uuid(),
  invoice_id      uuid not null references public.invoices (id) on delete cascade,
  environment     text,
  attempted_at    timestamptz not null default now(),
  http_status     integer,
  fbr_status_code text,
  error_code      text,
  error_message   text,
  request_json    jsonb,
  response_json   jsonb
);
create index if not exists fbr_submissions_invoice_idx on public.fbr_submissions (invoice_id, attempted_at desc);

-- 3d. cache of the FBR lists (provinces, HS codes, UOM, rates, SRO...)
create table if not exists public.fbr_reference (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null check (kind in ('hs_code', 'uom', 'province', 'rate', 'sale_type', 'sro', 'hs_uom')),
  code       text not null default '',
  label      text,
  payload    jsonb,
  fetched_at timestamptz not null default now(),
  unique (kind, code)
);

-- 3e. one row the sender updates every minute ("sender offline" warning)
create table if not exists public.fbr_heartbeat (
  id             boolean primary key default true check (id),
  last_seen      timestamptz,
  environment    text,
  sender_version text,
  note           text
);
insert into public.fbr_heartbeat (id) values (true) on conflict (id) do nothing;

drop trigger if exists fbr_invoices_set_updated_at on public.fbr_invoices;
create trigger fbr_invoices_set_updated_at
  before update on public.fbr_invoices
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------------- 4. security
-- Signed-in team members can only READ. Only functions and the sender (service-role key) write.
alter table public.fbr_invoices      enable row level security;
alter table public.fbr_invoice_items enable row level security;
alter table public.fbr_submissions   enable row level security;
alter table public.fbr_reference     enable row level security;
alter table public.fbr_heartbeat     enable row level security;

revoke all on public.fbr_invoices, public.fbr_invoice_items, public.fbr_submissions,
              public.fbr_reference, public.fbr_heartbeat from anon, authenticated;
grant select on public.fbr_invoices, public.fbr_invoice_items, public.fbr_submissions,
                public.fbr_reference, public.fbr_heartbeat to authenticated;
grant all on public.fbr_invoices, public.fbr_invoice_items, public.fbr_submissions,
             public.fbr_reference, public.fbr_heartbeat to service_role;

drop policy if exists "Team can view fbr_invoices"      on public.fbr_invoices;
drop policy if exists "Team can view fbr_invoice_items" on public.fbr_invoice_items;
drop policy if exists "Owner can view fbr_submissions"  on public.fbr_submissions;
drop policy if exists "Team can view fbr_reference"     on public.fbr_reference;
drop policy if exists "Team can view fbr_heartbeat"     on public.fbr_heartbeat;

create policy "Team can view fbr_invoices"      on public.fbr_invoices
  for select to authenticated using ((select public.current_app_role()) is not null);
create policy "Team can view fbr_invoice_items" on public.fbr_invoice_items
  for select to authenticated using ((select public.current_app_role()) is not null);
create policy "Owner can view fbr_submissions"  on public.fbr_submissions
  for select to authenticated using ((select public.current_app_role()) in ('owner', 'accountant'));
create policy "Team can view fbr_reference"     on public.fbr_reference
  for select to authenticated using ((select public.current_app_role()) is not null);
create policy "Team can view fbr_heartbeat"     on public.fbr_heartbeat
  for select to authenticated using ((select public.current_app_role()) is not null);

-- ----------------------------------------------------------------------------------- 5. tax maths for one line
-- The ONE place where FBR line figures are calculated in the database (D2 adds lib/tax.ts to match it).
--   Standard / reduced / exempt goods:
--       GST on top:   value = quantity x price,  tax = value x rate,  total = value + tax
--       (if prices_include_tax = true:  value = price / (1 + rate), tax = price - value)
--   Third Schedule goods:  tax = printed retail price x rate. The customer still pays only the printed price.
--
-- PROVISIONAL (settle with PRAL and the sandbox in Phase D6, plan section 1):
--   * fixedNotifiedValueOrRetailPrice is stored as retail price x quantity (line total).
--   * For Third Schedule lines: value = selling line value, total = value + tax.
-- Only this function needs to change when PRAL answers.
create or replace function public._fbr_line_figures(
  p_sale_type   text,
  p_rate_desc   text,
  p_qty         numeric,
  p_price       numeric,
  p_retail      numeric,
  p_sro         text,
  p_sro_serial  text,
  p_incl        boolean,
  p_item        text,
  out o_value   numeric,
  out o_tax     numeric,
  out o_total   numeric,
  out o_fixed   numeric,
  out o_add     numeric      -- tax that is ADDED to what the customer pays
)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rate numeric;
  v_line numeric := round(p_qty * round(p_price, 2), 2);
  v_type text := coalesce(p_sale_type, '');
begin
  if p_rate_desc is null or btrim(p_rate_desc) = '' then
    raise exception 'Set the GST rate for "%" in Inventory before making an FBR bill (for example 18%%).', p_item;
  end if;

  if p_rate_desc ~* '^\s*exempt' then
    v_rate := 0;
  elsif btrim(p_rate_desc) ~ '^[0-9]+(\.[0-9]+)?\s*%$' then
    v_rate := replace(replace(btrim(p_rate_desc), '%', ''), ' ', '')::numeric;
  else
    raise exception 'The GST rate of "%" (%) is not valid. Use a form like 18%%.', p_item, p_rate_desc;
  end if;

  if v_type ilike '%reduced%' or v_type ilike 'exempt%' then
    if nullif(btrim(coalesce(p_sro, '')), '') is null or nullif(btrim(coalesce(p_sro_serial, '')), '') is null then
      raise exception 'Item "%" needs its SRO / Schedule number and item serial in Inventory (FBR errors 0077, 0078).', p_item;
    end if;
  end if;

  if v_type ilike '3rd schedule%' then
    if p_retail is null or p_retail <= 0 then
      raise exception 'Item "%" is a Third Schedule item. Enter its printed retail price in Inventory (FBR error 0090).', p_item;
    end if;
    o_fixed := round(p_retail * p_qty, 2);
    o_value := v_line;
    o_tax   := round(o_fixed * v_rate / 100, 2);
    o_total := o_value + o_tax;
    o_add   := 0;                                   -- printed price already carries the tax
  elsif p_incl then
    o_fixed := 0;
    o_value := round(v_line / (1 + v_rate / 100), 2);
    o_tax   := v_line - o_value;
    o_total := v_line;
    o_add   := 0;
  else
    o_fixed := 0;
    o_value := v_line;
    o_tax   := round(v_line * v_rate / 100, 2);
    o_total := o_value + o_tax;
    o_add   := o_tax;
  end if;
end;
$$;
revoke all on function public._fbr_line_figures(text, text, numeric, numeric, numeric, text, text, boolean, text)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------------- 6. create_fbr_bill
-- Same inputs as create_invoice() (including the walk-in phone/address/type/CNIC), plus the buyer province/address for FBR.
-- 1. Calls the existing create_invoice() (bill, lines, payment, stock, all in this transaction).
-- 2. Saves the FBR header and one FBR line per bill line.
-- 3. If GST is added on top, adds it to the bill total and takes the extra payment.
-- Any error anywhere = the whole thing is undone. The customer's item lines (invoice_items) are not touched.
create or replace function public.create_fbr_bill(
  p_customer_id     uuid,
  p_walkin_name     text,
  p_note            text,
  p_invoice_date    date,
  p_items           jsonb,
  p_paid            numeric,
  p_method          text,
  p_buyer_province  text    default null,
  p_buyer_address   text    default null,
  p_created_offline boolean default false,
  p_walkin_phone    text    default null,
  p_walkin_address  text    default null,
  p_walkin_registration_type text default null,
  p_walkin_cnic_or_ntn       text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prof      public.business_profile%rowtype;
  v_cust      public.customers%rowtype;
  v_id        uuid;
  v_method    text := coalesce(nullif(p_method, ''), 'cash');
  v_paid      numeric(14,2) := round(coalesce(p_paid, 0), 2);
  v_pretax    numeric(14,2);
  v_paid_first numeric(14,2);
  v_tax_add   numeric(14,2) := 0;
  v_grand     numeric(14,2);
  v_prov      text;
  v_addr      text;
  v_line      record;
  f           record;
begin
  if auth.uid() is null then
    raise exception 'Please sign in again.';
  end if;
  if not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to make bills. Ask the Owner.' using errcode = '42501';
  end if;

  select * into v_prof from public.business_profile where id;
  if not v_prof.fbr_enabled then
    raise exception 'FBR bills are switched off. The Owner can switch them on in the shop profile.';
  end if;
  if v_prof.ntn is null then
    raise exception 'The shop NTN is missing in the business profile.';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Add at least one item to the bill.';
  end if;

  -- Same total create_invoice() will calculate (price x quantity, before any GST added on top)
  select coalesce(sum(round(x.quantity * round(x.rate, 2), 2)), 0)
    into v_pretax
  from jsonb_to_recordset(p_items) as x(inventory_id uuid, quantity integer, rate numeric);

  v_paid_first := least(v_paid, v_pretax);

  if p_customer_id is not null then
    select * into v_cust from public.customers where id = p_customer_id;
  end if;

  v_prov := coalesce(nullif(btrim(p_buyer_province), ''), nullif(btrim(v_cust.province), ''), nullif(btrim(v_prof.province), ''));
  v_addr := coalesce(nullif(btrim(p_buyer_address), ''), nullif(btrim(v_cust.address), ''),
                     nullif(btrim(p_walkin_address), ''), nullif(btrim(v_prof.address), ''));
  if v_prov is null then
    raise exception 'Choose the buyer''s province (FBR error 0074).';
  end if;

  -- The normal bill (all existing checks, stock, payment)
  -- Named inputs, exactly as the app calls it today
  v_id := public.create_invoice(
    p_customer_id => p_customer_id,
    p_walkin_name => p_walkin_name,
    p_note        => p_note,
    p_invoice_date => p_invoice_date,
    p_items       => p_items,
    p_paid        => v_paid_first,
    p_method      => v_method,
    p_walkin_phone => p_walkin_phone,
    p_walkin_address => p_walkin_address,
    p_walkin_registration_type => p_walkin_registration_type,
    p_walkin_cnic_or_ntn => p_walkin_cnic_or_ntn
  );

  insert into public.fbr_invoices (invoice_id, environment, buyer_province, buyer_address, created_offline)
  values (v_id, v_prof.fbr_environment, v_prov, v_addr, coalesce(p_created_offline, false));

  for v_line in
    select ii.id, ii.description, ii.hs_code, ii.uom, ii.quantity, ii.rate,
           inv.sale_type, inv.fbr_rate_desc, inv.retail_price, inv.sro_schedule_no, inv.sro_item_serial_no
    from public.invoice_items ii
    join public.inventory inv on inv.id = ii.inventory_id
    where ii.invoice_id = v_id
    order by ii.created_at, ii.id
  loop
    if v_line.hs_code is null then
      raise exception 'Item "%" has no HS code. Add it in Inventory (FBR errors 0019, 0044).', v_line.description;
    end if;

    select * into f
    from public._fbr_line_figures(
      v_line.sale_type, v_line.fbr_rate_desc, v_line.quantity::numeric, v_line.rate, v_line.retail_price,
      v_line.sro_schedule_no, v_line.sro_item_serial_no, v_prof.prices_include_tax, v_line.description
    );

    insert into public.fbr_invoice_items (
      invoice_item_id, invoice_id, hs_code, product_description, fbr_rate_desc, uom, quantity,
      total_values, value_sales_excl_st, fixed_notified_value, sales_tax_applicable,
      sro_schedule_no, sro_item_serial_no, sale_type
    ) values (
      v_line.id, v_id, v_line.hs_code, v_line.description, v_line.fbr_rate_desc, v_line.uom, v_line.quantity,
      f.o_total, f.o_value, f.o_fixed, f.o_tax,
      v_line.sro_schedule_no, v_line.sro_item_serial_no, v_line.sale_type
    );

    v_tax_add := v_tax_add + f.o_add;
  end loop;

  v_grand := v_pretax + v_tax_add;

  if v_paid > v_grand then
    raise exception 'The amount paid (Rs %) is more than the bill total (Rs %).', v_paid, v_grand;
  end if;
  if p_customer_id is null and v_paid < v_grand then
    raise exception 'A walk-in customer must pay the full amount including GST (Rs %). Choose a customer for udhaar.', v_grand;
  end if;

  if v_tax_add > 0 then
    update public.invoices set total_value = v_grand where id = v_id;
  end if;
  if v_paid > v_paid_first then
    insert into public.payments (invoice_id, amount, method) values (v_id, v_paid - v_paid_first, v_method);
  end if;
  update public.invoices
     set payment_status = case when v_paid >= v_grand then 'Paid' when v_paid = 0 then 'Credit' else 'Partial' end
   where id = v_id;

  return v_id;
end;
$$;

revoke all on function public.create_fbr_bill(uuid, text, text, date, jsonb, numeric, text, text, text, boolean, text, text, text, text)
  from public, anon;
grant execute on function public.create_fbr_bill(uuid, text, text, date, jsonb, numeric, text, text, text, boolean, text, text, text, text)
  to authenticated;

-- ----------------------------------------------------------------------------------- done: quick checks
-- Run these one at a time (they only read):
--   select fbr_enabled, fbr_environment, prices_include_tax, business_name, ntn from public.business_profile;
--   select count(*) from public.fbr_invoices;                      -- 0
--   select proname, pg_get_function_identity_arguments(oid) from pg_proc where proname in ('create_invoice','create_fbr_bill');
-- FBR stays OFF until you set:  update public.business_profile set fbr_enabled = true;   (Phase D2 testing, sandbox)

-- ======== 11_fbr_d2_d3.sql ========
-- =====================================================================================================
-- PowerCell POS App, FBR Digital Invoicing, Phases D2 + D3: helper functions.
-- Run ONCE in Supabase: SQL Editor > New query > paste ALL > Run.   Safe to run again.
-- Run AFTER 18_fbr.sql.
--
-- 1. create_unreported_bill(): the ONLY way to save a bill that has taxable items but no FBR bill,
--    while FBR is switched on. Owner only. Writes a line to the Activity log.
-- 2. import_fbr_reference(): Owner loads an FBR list (HS codes, UOM, provinces...) into fbr_reference.
--    Until the sender program (phase D4) exists, the lists are loaded by hand from the FBR portal.
-- Neither function changes create_invoice() or any existing bill.
-- =====================================================================================================

do $$
begin
  if to_regclass('public.fbr_reference') is null or to_regprocedure('public.create_fbr_bill(uuid, text, text, date, jsonb, numeric, text, text, text, boolean, text, text, text, text)') is null then
    raise exception 'Run 18_fbr.sql first.';
  end if;
end $$;

-- ----------------------------------------------------------------------------------- 1. unreported bill (Owner only)
create or replace function public.create_unreported_bill(
  p_customer_id  uuid,
  p_walkin_name  text,
  p_note         text,
  p_invoice_date date,
  p_items        jsonb,
  p_paid         numeric,
  p_method       text,
  p_walkin_phone text default null,
  p_walkin_address text default null,
  p_walkin_registration_type text default null,
  p_walkin_cnic_or_ntn text default null,
  p_reason       text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id    uuid;
  v_name  text;
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'Please sign in again.';
  end if;
  if not public.role_in(array['owner']) then
    raise exception 'Only the Owner can save a taxable bill without an FBR bill.' using errcode = '42501';
  end if;

  v_id := public.create_invoice(
    p_customer_id => p_customer_id,
    p_walkin_name => p_walkin_name,
    p_note        => p_note,
    p_invoice_date => p_invoice_date,
    p_items       => p_items,
    p_paid        => p_paid,
    p_method      => p_method,
    p_walkin_phone => p_walkin_phone,
    p_walkin_address => p_walkin_address,
    p_walkin_registration_type => p_walkin_registration_type,
    p_walkin_cnic_or_ntn => p_walkin_cnic_or_ntn
  );

  select coalesce(nullif(ur.full_name, ''), 'Owner') into v_name from public.user_roles ur where ur.user_id = auth.uid();
  select u.email into v_email from auth.users u where u.id = auth.uid();

  insert into public.audit_log (actor_id, actor_name, actor_email, actor_role, action, table_name, record_id, summary, new_data)
  values (
    auth.uid(), coalesce(v_name, 'Owner'), v_email, 'owner', 'create', 'invoices', v_id::text,
    'Bill saved WITHOUT an FBR bill although it has taxable items' || coalesce(' (' || nullif(btrim(p_reason), '') || ')', ''),
    jsonb_build_object('fbr_skipped', true, 'reason', nullif(btrim(p_reason), ''))
  );

  return v_id;
end;
$$;
revoke all on function public.create_unreported_bill(uuid, text, text, date, jsonb, numeric, text, text, text, text, text, text) from public, anon;
grant execute on function public.create_unreported_bill(uuid, text, text, date, jsonb, numeric, text, text, text, text, text, text) to authenticated;

-- ----------------------------------------------------------------------------------- 2. load an FBR list (Owner only)
-- p_items: [{"code": "8507.2000", "label": "Lead-acid accumulators", "payload": {...}}, ...]
-- p_replace = true replaces the whole list of that kind (in one step). Nothing changes if anything fails.
create or replace function public.import_fbr_reference(
  p_kind    text,
  p_items   jsonb,
  p_replace boolean default true
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Please sign in again.';
  end if;
  if not public.role_in(array['owner']) then
    raise exception 'Only the Owner can load the FBR lists.' using errcode = '42501';
  end if;
  if p_kind not in ('hs_code', 'uom', 'province', 'rate', 'sale_type', 'sro', 'hs_uom') then
    raise exception 'Unknown list type: %', p_kind;
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'The list is empty. Nothing was loaded.';
  end if;

  if p_replace then
    delete from public.fbr_reference where kind = p_kind;
  end if;

  insert into public.fbr_reference (kind, code, label, payload, fetched_at)
  select p_kind, btrim(x.code), nullif(btrim(coalesce(x.label, '')), ''), x.payload, now()
  from jsonb_to_recordset(p_items) as x(code text, label text, payload jsonb)
  where nullif(btrim(coalesce(x.code, '')), '') is not null
  on conflict (kind, code) do update
    set label = excluded.label, payload = excluded.payload, fetched_at = now();

  select count(*) into v_count from public.fbr_reference where kind = p_kind;
  return v_count;
end;
$$;
revoke all on function public.import_fbr_reference(text, jsonb, boolean) from public, anon;
grant execute on function public.import_fbr_reference(text, jsonb, boolean) to authenticated;

-- Quick check (read only):
--   select kind, count(*) from public.fbr_reference group by kind;

