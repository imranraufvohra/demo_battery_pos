-- ======== 12_exported_functions_views.sql (rebuilt) ========
-- =====================================================================================================
-- 12_exported_functions_views.sql  (REBUILT for the universal demo; replaces the empty placeholder)
-- Run AFTER files 01-11. Safe to run again.
-- These functions were not in the repo, so they were REWRITTEN from the schema notes and from the way
-- the app calls them. They are tested on a clean database but are not copies of the original code.
-- =====================================================================================================

alter table public.invoices add column if not exists cancel_reason text;
alter table public.invoices add column if not exists cancelled_at  timestamptz;

-- ------------------------------------------------------------------------------------------ 1. views
create or replace view public.expense_details with (security_invoker = true) as
select e.*, c.name as category_name, c.excluded_from_profit
from public.expenses e
join public.expense_categories c on c.id = e.category_id;

create or replace view public.payment_details with (security_invoker = true) as
select sp.*, pi.purchase_number, d.name as supplier_name
from public.supplier_payments sp
join public.distributors d on d.id = sp.supplier_id
left join public.purchase_invoices pi on pi.id = sp.purchase_id;

create or replace view public.battery_claims_by_distributor with (security_invoker = true) as
select bc.distributor_id, d.name as distributor_name, bc.status, count(*)::int as count
from public.battery_claims bc
join public.distributors d on d.id = bc.distributor_id
where bc.status in ('sent_to_distributor', 'approved')
group by bc.distributor_id, d.name, bc.status;

create or replace view public.battery_stock_summary with (security_invoker = true) as
select 'charging'::text as kind, cj.status, count(*)::int as count
  from public.charging_jobs cj where cj.status in ('in_shop', 'unclaimed') group by cj.status
union all
select 'claim'::text, bc.status, count(*)::int
  from public.battery_claims bc where bc.status not in ('given_to_customer', 'settled', 'rejected') group by bc.status;

create or replace view public.scrap_stock_summary with (security_invoker = true) as
select
  count(*) filter (where status = 'in_stock')::int                                         as batches_in_stock,
  count(*) filter (where status = 'sold')::int                                             as batches_sold,
  coalesce(sum(quantity) filter (where status = 'in_stock'), 0)::int                       as batteries_in_stock,
  coalesce(sum(quantity) filter (where status = 'sold'), 0)::int                           as batteries_sold,
  coalesce(sum(estimated_weight_kg) filter (where status = 'in_stock'), 0)::numeric        as estimated_weight_in_stock_kg
from public.scrap_battery_inventory;

grant select on public.expense_details, public.payment_details, public.battery_claims_by_distributor,
                public.battery_stock_summary, public.scrap_stock_summary to authenticated;
revoke all on public.expense_details, public.payment_details, public.battery_claims_by_distributor,
                public.battery_stock_summary, public.scrap_stock_summary from anon;

-- ------------------------------------------------------------------------- 2. invoices: udhaar, cancel, delete
create or replace function public.add_udhaar_entry(
  p_customer_id uuid, p_invoice_number text, p_invoice_date date, p_amount numeric, p_note text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_c public.customers%rowtype; v_id uuid;
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to add udhaar.' using errcode = '42501';
  end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'The amount must be more than zero.'; end if;
  select * into v_c from public.customers where id = p_customer_id;
  if not found then raise exception 'Customer not found.'; end if;
  insert into public.invoices (invoice_number, invoice_date, customer_id, buyer_name, buyer_registration_type,
                               buyer_cnic_or_ntn, buyer_address, buyer_phone, note, total_value, payment_status, status)
  values (coalesce(nullif(trim(p_invoice_number), ''), 'INV-' || lpad(nextval('public.invoice_number_seq')::text, 6, '0')),
          coalesce(p_invoice_date, current_date), v_c.id, v_c.name, v_c.registration_type, v_c.cnic_or_ntn,
          v_c.address, v_c.phone, coalesce(p_note, 'Old udhaar'), round(p_amount, 2), 'Credit', 'Valid')
  returning id into v_id;
  return v_id;
end $$;

create or replace function public._restock_invoice(p_invoice_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.inventory i set quantity = i.quantity + s.q
  from (select inventory_id, sum(quantity)::int as q from public.invoice_items
        where invoice_id = p_invoice_id group by inventory_id) s
  where i.id = s.inventory_id;
end $$;

create or replace function public.cancel_invoice(p_invoice_id uuid, p_reason text, p_restock boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
declare v_inv public.invoices%rowtype;
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to cancel bills.' using errcode = '42501';
  end if;
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Bill not found.'; end if;
  if v_inv.status = 'Cancelled' then raise exception 'This bill is already cancelled.'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please write a reason.'; end if;
  if exists (select 1 from public.fbr_invoices where invoice_id = p_invoice_id and fbr_status = 'sent') then
    raise exception 'This bill was already accepted by FBR. Make a debit note instead of cancelling it.';
  end if;
  update public.invoices set status = 'Cancelled', cancel_reason = trim(p_reason), cancelled_at = now() where id = p_invoice_id;
  if p_restock then perform public._restock_invoice(p_invoice_id); end if;
end $$;

create or replace function public._delete_invoice_core(p_invoice_id uuid, p_restock boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  select status into v_status from public.invoices where id = p_invoice_id for update;
  if not found then return; end if;
  if p_restock and v_status <> 'Cancelled' then perform public._restock_invoice(p_invoice_id); end if;
  delete from public.fbr_submissions    where invoice_id = p_invoice_id;
  delete from public.fbr_invoice_items  where invoice_id = p_invoice_id;
  delete from public.fbr_invoices       where invoice_id = p_invoice_id;
  delete from public.payments           where invoice_id = p_invoice_id;
  delete from public.invoices           where id = p_invoice_id;
end $$;

create or replace function public.delete_invoice(p_invoice_id uuid, p_restock boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_owner() then
    raise exception 'Only the Owner can delete a bill.' using errcode = '42501';
  end if;
  if exists (select 1 from public.fbr_invoices where invoice_id = p_invoice_id and fbr_status = 'sent') then
    raise exception 'A bill accepted by FBR cannot be deleted.';
  end if;
  perform public._delete_invoice_core(p_invoice_id, p_restock);
end $$;

create or replace function public.delete_sandbox_fbr_bill(p_invoice_id uuid, p_restock boolean default true)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_owner() then
    raise exception 'Only the Owner can delete a test bill.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.fbr_invoices where invoice_id = p_invoice_id and environment = 'sandbox') then
    raise exception 'Only test (sandbox) FBR bills can be deleted this way.';
  end if;
  perform public._delete_invoice_core(p_invoice_id, p_restock);
end $$;

create or replace function public.delete_customer_and_bills(p_customer_id uuid, p_restock boolean default true)
returns integer language plpgsql security definer set search_path = '' as $$
declare r record; n integer := 0;
begin
  if auth.uid() is not null and not public.is_owner() then
    raise exception 'Only the Owner can delete a customer.' using errcode = '42501';
  end if;
  for r in select id from public.invoices where customer_id = p_customer_id loop
    perform public._delete_invoice_core(r.id, p_restock);
    n := n + 1;
  end loop;
  delete from public.customers where id = p_customer_id;
  return n;
end $$;

-- ---------------------------------------------------------------------------------- 3. expenses and cash
create or replace function public.create_expense(
  p_client_id uuid, p_category_id uuid, p_amount numeric, p_expense_date date, p_method text default 'cash',
  p_paid_to text default null, p_reference text default null, p_cheque_number text default null,
  p_cheque_date date default null, p_bank_name text default null, p_note text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
    raise exception 'Only the Owner and the Accountant can add expenses.' using errcode = '42501';
  end if;
  if p_client_id is not null then
    select id into v_id from public.expenses where client_id = p_client_id;
    if found then return v_id; end if;
  end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'The amount must be more than zero.'; end if;
  insert into public.expenses (client_id, category_id, amount, expense_date, method, paid_to, reference,
                               cheque_number, cheque_date, bank_name, note)
  values (p_client_id, p_category_id, round(p_amount, 2), coalesce(p_expense_date, current_date),
          coalesce(nullif(p_method, ''), 'cash'), nullif(trim(p_paid_to), ''), nullif(trim(p_reference), ''),
          nullif(trim(p_cheque_number), ''), p_cheque_date, nullif(trim(p_bank_name), ''), nullif(trim(p_note), ''))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.update_expense(
  p_expense_id uuid, p_category_id uuid, p_amount numeric, p_expense_date date, p_method text default 'cash',
  p_paid_to text default null, p_reference text default null, p_cheque_number text default null,
  p_cheque_date date default null, p_bank_name text default null, p_note text default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
    raise exception 'Only the Owner and the Accountant can change expenses.' using errcode = '42501';
  end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'The amount must be more than zero.'; end if;
  update public.expenses set category_id = p_category_id, amount = round(p_amount, 2),
         expense_date = coalesce(p_expense_date, expense_date), method = coalesce(nullif(p_method, ''), 'cash'),
         paid_to = nullif(trim(p_paid_to), ''), reference = nullif(trim(p_reference), ''),
         cheque_number = nullif(trim(p_cheque_number), ''), cheque_date = p_cheque_date,
         bank_name = nullif(trim(p_bank_name), ''), note = nullif(trim(p_note), '')
  where id = p_expense_id and status = 'Valid';
  if not found then raise exception 'Expense not found, or it is already cancelled.'; end if;
end $$;

create or replace function public.cancel_expense(p_expense_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
    raise exception 'Only the Owner and the Accountant can cancel expenses.' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please write a reason.'; end if;
  update public.expenses set status = 'Cancelled', cancel_reason = trim(p_reason)
  where id = p_expense_id and status = 'Valid';
  if not found then raise exception 'Expense not found, or it is already cancelled.'; end if;
end $$;

create or replace function public.save_cash_opening_balance(p_opening_balance numeric, p_opening_date date)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_owner() then
    raise exception 'Only the Owner can set the opening cash.' using errcode = '42501';
  end if;
  if coalesce(p_opening_balance, 0) < 0 then raise exception 'Opening cash cannot be negative.'; end if;
  insert into public.cash_settings (id, opening_balance, opening_date)
  values (true, round(coalesce(p_opening_balance, 0), 2), coalesce(p_opening_date, current_date))
  on conflict (id) do update set opening_balance = excluded.opening_balance,
        opening_date = excluded.opening_date, updated_at = now();
end $$;

-- ------------------------------------------------------------------------------- 4. supplier payments
create or replace function public.record_supplier_payment(
  p_client_id uuid, p_supplier_id uuid, p_purchase_id uuid, p_amount numeric, p_method text,
  p_paid_at date, p_reference text default null, p_cheque_number text default null,
  p_cheque_date date default null, p_bank_name text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_method text := coalesce(nullif(p_method, ''), 'cash');
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
    raise exception 'Only the Owner and the Accountant can record supplier payments.' using errcode = '42501';
  end if;
  if p_client_id is not null then
    select id into v_id from public.supplier_payments where client_id = p_client_id;
    if found then return v_id; end if;
  end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'The amount must be more than zero.'; end if;
  if p_purchase_id is not null and not exists (
       select 1 from public.purchase_invoices where id = p_purchase_id and supplier_id = p_supplier_id and status = 'Valid') then
    raise exception 'That bill does not belong to this supplier, or it is cancelled.';
  end if;
  insert into public.supplier_payments (client_id, supplier_id, purchase_id, amount, method, paid_at, reference,
                                        cheque_number, cheque_date, bank_name, cheque_status)
  values (p_client_id, p_supplier_id, p_purchase_id, round(p_amount, 2), v_method, coalesce(p_paid_at, current_date),
          nullif(trim(p_reference), ''), nullif(trim(p_cheque_number), ''), p_cheque_date, nullif(trim(p_bank_name), ''),
          case when v_method = 'cheque' then 'issued' end)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.cancel_supplier_payment(p_payment_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
    raise exception 'Only the Owner and the Accountant can cancel supplier payments.' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Please write a reason.'; end if;
  update public.supplier_payments set status = 'Cancelled', cancel_reason = trim(p_reason)
  where id = p_payment_id and status = 'Valid';
  if not found then raise exception 'Payment not found, or it is already cancelled.'; end if;
end $$;

-- ------------------------------------------------------------------- 5. charging, claims, scrap
create or replace function public.create_charging_job(
  p_customer_id uuid, p_walkin_name text, p_walkin_phone text, p_battery_brand text, p_battery_model text,
  p_battery_number text, p_price numeric, p_note text, p_received_date date
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_c public.customers%rowtype; v_id uuid; v_d date := coalesce(p_received_date, current_date);
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to add a charging slip.' using errcode = '42501';
  end if;
  if p_customer_id is not null then select * into v_c from public.customers where id = p_customer_id; end if;
  insert into public.charging_jobs (customer_id, customer_name, customer_phone, battery_brand, battery_model,
                                    battery_number, price, note, received_date, due_date)
  values (v_c.id, coalesce(v_c.name, nullif(trim(p_walkin_name), ''), 'Walk-in customer'),
          coalesce(v_c.phone, nullif(trim(p_walkin_phone), '')), trim(p_battery_brand), trim(p_battery_model),
          nullif(trim(p_battery_number), ''), greatest(coalesce(p_price, 0), 0), nullif(trim(p_note), ''), v_d, v_d + 2)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.update_charging_job_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to change a charging slip.' using errcode = '42501';
  end if;
  if p_status not in ('in_shop', 'collected', 'unclaimed') then raise exception 'Unknown status.'; end if;
  update public.charging_jobs set status = p_status,
         collected_at = case when p_status = 'collected' then coalesce(collected_at, now()) else null end
  where id = p_id;
  if not found then raise exception 'Charging slip not found.'; end if;
end $$;

create or replace function public.record_charging_handover(
  p_id uuid, p_outcome text, p_amount numeric default null, p_note text default null
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to hand over a battery.' using errcode = '42501';
  end if;
  if p_outcome not in ('charged', 'faulty') then raise exception 'Outcome must be charged or faulty.'; end if;
  update public.charging_jobs set outcome = p_outcome, status = 'collected', collected_at = now(),
         handover_amount = case when p_outcome = 'charged' then greatest(coalesce(p_amount, price), 0) else 0 end,
         handover_note = nullif(trim(p_note), '')
  where id = p_id;
  if not found then raise exception 'Charging slip not found.'; end if;
end $$;

create or replace function public.delete_charging_job(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_owner() then
    raise exception 'Only the Owner can delete a charging slip.' using errcode = '42501';
  end if;
  delete from public.charging_jobs where id = p_id;
end $$;

create or replace function public.get_or_create_distributor(p_distributor_id uuid, p_new_distributor_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_name text := nullif(trim(p_new_distributor_name), '');
begin
  if p_distributor_id is not null then return p_distributor_id; end if;
  if v_name is null then return null; end if;
  select id into v_id from public.distributors where lower(name) = lower(v_name) limit 1;
  if found then return v_id; end if;
  insert into public.distributors (name) values (v_name) returning id into v_id;
  return v_id;
end $$;

create or replace function public.create_battery_claim(
  p_customer_id uuid, p_walkin_name text, p_walkin_phone text, p_battery_brand text, p_battery_model text,
  p_battery_number text, p_original_invoice_id uuid, p_claim_amount numeric, p_extra_charges numeric,
  p_note text, p_received_date date, p_distributor_id uuid default null, p_new_distributor_name text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_c public.customers%rowtype; v_id uuid; v_dist uuid;
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to add a claim.' using errcode = '42501';
  end if;
  if p_customer_id is not null then select * into v_c from public.customers where id = p_customer_id; end if;
  v_dist := public.get_or_create_distributor(p_distributor_id, p_new_distributor_name);
  insert into public.battery_claims (customer_id, customer_name, customer_phone, battery_brand, battery_model,
         battery_number, original_invoice_id, distributor_id, claim_amount, extra_charges, note, received_date,
         status, sent_to_distributor_at)
  values (v_c.id, coalesce(v_c.name, nullif(trim(p_walkin_name), ''), 'Walk-in customer'),
          coalesce(v_c.phone, nullif(trim(p_walkin_phone), '')), trim(p_battery_brand), trim(p_battery_model),
          nullif(trim(p_battery_number), ''), p_original_invoice_id, v_dist, p_claim_amount, p_extra_charges,
          nullif(trim(p_note), ''), coalesce(p_received_date, current_date),
          case when v_dist is null then 'received' else 'sent_to_distributor' end,
          case when v_dist is null then null else now() end)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.update_battery_claim_status(
  p_id uuid, p_status text, p_distributor_id uuid default null, p_note text default null,
  p_new_distributor_name text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare v_dist uuid;
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to change a claim.' using errcode = '42501';
  end if;
  if p_status not in ('received', 'sent_to_distributor', 'approved', 'rejected', 'given_to_customer', 'settled') then
    raise exception 'Unknown status.';
  end if;
  v_dist := public.get_or_create_distributor(p_distributor_id, p_new_distributor_name);
  if p_status = 'sent_to_distributor' and v_dist is null
     and not exists (select 1 from public.battery_claims where id = p_id and distributor_id is not null) then
    raise exception 'Pick the distributor this battery is being sent to.';
  end if;
  update public.battery_claims set status = p_status,
         distributor_id = coalesce(v_dist, distributor_id),
         note = coalesce(nullif(trim(p_note), ''), note),
         sent_to_distributor_at = case when p_status = 'sent_to_distributor' then coalesce(sent_to_distributor_at, now()) else sent_to_distributor_at end,
         approved_at            = case when p_status = 'approved'            then coalesce(approved_at, now())            else approved_at end,
         rejected_at            = case when p_status = 'rejected'            then coalesce(rejected_at, now())            else rejected_at end,
         given_to_customer_at   = case when p_status = 'given_to_customer'   then coalesce(given_to_customer_at, now())   else given_to_customer_at end,
         settled_at             = case when p_status = 'settled'             then coalesce(settled_at, now())             else settled_at end
  where id = p_id;
  if not found then raise exception 'Claim not found.'; end if;
end $$;

create or replace function public.delete_battery_claim(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.is_owner() then
    raise exception 'Only the Owner can delete a claim.' using errcode = '42501';
  end if;
  delete from public.battery_claims where id = p_id;
end $$;

create or replace function public.record_scrap_intake(
  p_invoice_id uuid, p_customer_id uuid, p_customer_name text, p_brand text, p_model text, p_battery_type text,
  p_battery_number text, p_quantity integer, p_estimated_weight_kg numeric, p_note text, p_received_date date
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to add scrap batteries.' using errcode = '42501';
  end if;
  insert into public.scrap_battery_inventory (invoice_id, customer_id, customer_name, brand, model, battery_type,
         battery_number, quantity, estimated_weight_kg, note, received_date)
  values (p_invoice_id, p_customer_id, nullif(trim(p_customer_name), ''), trim(p_brand), trim(p_model),
          nullif(trim(p_battery_type), ''), nullif(trim(p_battery_number), ''), greatest(coalesce(p_quantity, 1), 1),
          nullif(p_estimated_weight_kg, 0), nullif(trim(p_note), ''), coalesce(p_received_date, current_date))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.sell_scrap(
  p_intake_ids uuid[], p_buyer_name text, p_buyer_phone text, p_total_weight_kg numeric, p_rate_per_kg numeric,
  p_sale_date date, p_note text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_n integer;
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'counter_staff']) then
    raise exception 'Your role is not allowed to sell scrap.' using errcode = '42501';
  end if;
  if coalesce(array_length(p_intake_ids, 1), 0) = 0 then raise exception 'Pick at least one scrap batch.'; end if;
  select count(*) into v_n from public.scrap_battery_inventory where id = any (p_intake_ids) and status = 'in_stock';
  if v_n <> array_length(p_intake_ids, 1) then raise exception 'Some of these batches are already sold.'; end if;
  insert into public.scrap_battery_sales (buyer_name, buyer_phone, total_weight_kg, rate_per_kg, total_amount, sale_date, note)
  values (trim(p_buyer_name), nullif(trim(p_buyer_phone), ''), p_total_weight_kg, p_rate_per_kg,
          round(p_total_weight_kg * p_rate_per_kg, 2), coalesce(p_sale_date, current_date), nullif(trim(p_note), ''))
  returning id into v_id;
  update public.scrap_battery_inventory set status = 'sold', sold_in_sale_id = v_id where id = any (p_intake_ids);
  return v_id;
end $$;

-- ------------------------------------------------------------------------------------ 6. AI assistant
create or replace function public.ai_log_proposal(p_kind text, p_message text, p_proposal jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  insert into public.ai_actions (user_id, kind, user_message, proposal) values (auth.uid(), p_kind, left(p_message, 500), p_proposal)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.ai_claim_action(p_id uuid)
returns public.ai_actions language plpgsql security definer set search_path = '' as $$
declare r public.ai_actions;
begin
  update public.ai_actions set status = 'executing'
  where id = p_id and user_id = auth.uid() and status in ('proposed', 'edited')
  returning * into r;
  if r.id is null then raise exception 'This action was already used or does not exist.'; end if;
  return r;
end $$;

create or replace function public.ai_finish_action(p_id uuid, p_status text, p_sent jsonb, p_result jsonb, p_error text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.ai_actions set status = p_status, sent_payload = p_sent, result = p_result, error = p_error, resolved_at = now()
  where id = p_id and user_id = auth.uid();
end $$;

create or replace function public.ai_resolve_action(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.ai_actions set status = p_status, resolved_at = now()
  where id = p_id and user_id = auth.uid() and status in ('proposed', 'edited');
end $$;

create table if not exists public.ai_rate_limits (
  user_id uuid primary key, window_start timestamptz not null default now(), hits integer not null default 0
);
alter table public.ai_rate_limits enable row level security;
revoke all on public.ai_rate_limits from anon, authenticated;

create or replace function public.ai_rate_limit_check(p_limit integer, p_window_seconds integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.ai_rate_limits; v_now timestamptz := now();
begin
  if auth.uid() is null then return jsonb_build_object('allowed', true); end if;
  insert into public.ai_rate_limits (user_id) values (auth.uid()) on conflict (user_id) do nothing;
  select * into r from public.ai_rate_limits where user_id = auth.uid() for update;
  if v_now >= r.window_start + make_interval(secs => p_window_seconds) then
    update public.ai_rate_limits set window_start = v_now, hits = 1 where user_id = auth.uid();
    return jsonb_build_object('allowed', true);
  end if;
  if r.hits >= p_limit then
    return jsonb_build_object('allowed', false,
      'retry_after_seconds', greatest(1, ceil(extract(epoch from (r.window_start + make_interval(secs => p_window_seconds) - v_now)))::int));
  end if;
  update public.ai_rate_limits set hits = hits + 1 where user_id = auth.uid();
  return jsonb_build_object('allowed', true);
end $$;

-- ---------------------------------------------------------------------------- 7. money reports (cash book)
-- Cash only (method = 'cash'). Dates are UTC dates, the same as report_summary.
create or replace function public._cash_parts(p_from date, p_to date)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'cash_sales', coalesce((select sum(p.amount) from public.payments p join public.invoices i on i.id = p.invoice_id
        where i.status <> 'Cancelled' and p.method = 'cash' and (p.paid_at at time zone 'UTC')::date between p_from and p_to), 0),
    'scrap',      coalesce((select sum(total_amount) from public.scrap_battery_sales where sale_date between p_from and p_to), 0),
    'charging',   coalesce((select sum(handover_amount) from public.charging_jobs
        where outcome = 'charged' and (collected_at at time zone 'UTC')::date between p_from and p_to), 0),
    'claims',     coalesce((select sum(extra_charges) from public.battery_claims
        where (given_to_customer_at at time zone 'UTC')::date between p_from and p_to), 0),
    'suppliers',  coalesce((select sum(amount) from public.supplier_payments
        where status = 'Valid' and method = 'cash' and paid_at between p_from and p_to), 0),
    'expenses',   coalesce((select sum(amount) from public.expenses
        where status = 'Valid' and method = 'cash' and expense_date between p_from and p_to), 0));
$$;

create or replace function public._core_cash_book_summary(p_from date, p_to date)
returns jsonb language plpgsql stable set search_path = '' as $$
declare v_set public.cash_settings%rowtype; v_open numeric := 0; v_prior jsonb; v_cur jsonb;
        v_other numeric; v_in numeric;
begin
  select * into v_set from public.cash_settings limit 1;
  v_open := coalesce(v_set.opening_balance, 0);
  if found and p_from > v_set.opening_date then
    v_prior := public._cash_parts(v_set.opening_date, p_from - 1);
    v_open := v_open + (v_prior->>'cash_sales')::numeric + (v_prior->>'scrap')::numeric + (v_prior->>'charging')::numeric
              + (v_prior->>'claims')::numeric - (v_prior->>'suppliers')::numeric - (v_prior->>'expenses')::numeric;
  end if;
  v_cur := public._cash_parts(p_from, p_to);
  v_other := (v_cur->>'scrap')::numeric + (v_cur->>'charging')::numeric + (v_cur->>'claims')::numeric;
  return jsonb_build_object(
    'opening_balance_as_of', to_char(coalesce(v_set.opening_date, current_date), 'YYYY-MM-DD'),
    'opening_for_period', v_open,
    'cash_sales', (v_cur->>'cash_sales')::numeric,
    'other_cash_income', v_other,
    'other_cash_income_breakdown', jsonb_build_object('scrap', (v_cur->>'scrap')::numeric,
        'charging', (v_cur->>'charging')::numeric, 'claims', (v_cur->>'claims')::numeric),
    'cash_paid_to_suppliers', (v_cur->>'suppliers')::numeric,
    'cash_expenses', (v_cur->>'expenses')::numeric,
    'closing_balance', v_open + (v_cur->>'cash_sales')::numeric + v_other
                       - (v_cur->>'suppliers')::numeric - (v_cur->>'expenses')::numeric);
end $$;

create or replace function public._core_financial_summary(p_from date, p_to date)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'expenses_total', coalesce((select sum(amount) from public.expenses
        where status = 'Valid' and expense_date between p_from and p_to), 0),
    'expenses_excluded_total', coalesce((select sum(e.amount) from public.expenses e
        join public.expense_categories c on c.id = e.category_id
        where e.status = 'Valid' and c.excluded_from_profit and e.expense_date between p_from and p_to), 0),
    'purchases_total', coalesce((select sum(total_value) from public.purchase_invoices
        where status = 'Valid' and invoice_date between p_from and p_to), 0),
    'paid_to_suppliers_total', coalesce((select sum(amount) from public.supplier_payments
        where status = 'Valid' and paid_at between p_from and p_to), 0),
    'we_owe_total', coalesce((select sum(balance) from public.supplier_balances where balance > 0), 0),
    'we_owe_count', coalesce((select count(*) from public.supplier_balances where balance > 0), 0));
$$;

revoke all on function public._cash_parts(date, date), public._core_cash_book_summary(date, date),
               public._core_financial_summary(date, date) from public, anon, authenticated;

create or replace function public.financial_summary(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
    raise exception 'Reports are only for the Owner and the Accountant.' using errcode = '42501';
  end if;
  return public._core_financial_summary(p_from, p_to);
end $$;

create or replace function public.cash_book_summary(p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null and not public.role_in(array['owner', 'accountant']) then
    raise exception 'Reports are only for the Owner and the Accountant.' using errcode = '42501';
  end if;
  return public._core_cash_book_summary(p_from, p_to);
end $$;

-- ------------------------------------------------------------------------------------- 8. who may call what
do $$
declare f text;
begin
  foreach f in array array[
    'add_udhaar_entry(uuid, text, date, numeric, text)', 'cancel_invoice(uuid, text, boolean)',
    'delete_invoice(uuid, boolean)', 'delete_sandbox_fbr_bill(uuid, boolean)', 'delete_customer_and_bills(uuid, boolean)',
    'create_expense(uuid, uuid, numeric, date, text, text, text, text, date, text, text)',
    'update_expense(uuid, uuid, numeric, date, text, text, text, text, date, text, text)',
    'cancel_expense(uuid, text)', 'save_cash_opening_balance(numeric, date)',
    'record_supplier_payment(uuid, uuid, uuid, numeric, text, date, text, text, date, text)',
    'cancel_supplier_payment(uuid, text)',
    'create_charging_job(uuid, text, text, text, text, text, numeric, text, date)',
    'update_charging_job_status(uuid, text)', 'record_charging_handover(uuid, text, numeric, text)',
    'delete_charging_job(uuid)', 'get_or_create_distributor(uuid, text)',
    'create_battery_claim(uuid, text, text, text, text, text, uuid, numeric, numeric, text, date, uuid, text)',
    'update_battery_claim_status(uuid, text, uuid, text, text)', 'delete_battery_claim(uuid)',
    'record_scrap_intake(uuid, uuid, text, text, text, text, text, integer, numeric, text, date)',
    'sell_scrap(uuid[], text, text, numeric, numeric, date, text)',
    'ai_log_proposal(text, text, jsonb)', 'ai_claim_action(uuid)', 'ai_finish_action(uuid, text, jsonb, jsonb, text)',
    'ai_resolve_action(uuid, text)', 'ai_rate_limit_check(integer, integer)',
    'financial_summary(date, date)', 'cash_book_summary(date, date)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public._restock_invoice(uuid), public._delete_invoice_core(uuid, boolean) from public, anon, authenticated;

-- Done. Check: select proname from pg_proc where pronamespace = 'public'::regnamespace order by 1;

-- ======== 13_missing_policies_triggers.sql ========
-- 0001c: RLS policies and triggers for the tables in 0001a. GENERATED from the schema CSV.
-- Run AFTER all functions exist (16, 17, and the exported functions).

drop policy if exists "Users can view their own AI actions" on public.ai_actions;
create policy "Users can view their own AI actions" on public.ai_actions for select to authenticated using ((user_id = auth.uid()));
drop policy if exists "Team can view battery_claims" on public.battery_claims;
create policy "Team can view battery_claims" on public.battery_claims for select to authenticated using ((( SELECT current_app_role() AS current_app_role) IS NOT NULL));
drop policy if exists "Team can view cash_settings" on public.cash_settings;
create policy "Team can view cash_settings" on public.cash_settings for select to authenticated using ((( SELECT current_app_role() AS current_app_role) = ANY (ARRAY['owner'::text, 'accountant'::text])));
drop policy if exists "Team can view charging_jobs" on public.charging_jobs;
create policy "Team can view charging_jobs" on public.charging_jobs for select to authenticated using ((( SELECT current_app_role() AS current_app_role) IS NOT NULL));
drop policy if exists "Team can view charging prices" on public.charging_price_list;
create policy "Team can view charging prices" on public.charging_price_list for select to authenticated using ((( SELECT current_app_role() AS current_app_role) IS NOT NULL));
drop policy if exists "Owner can edit charging prices" on public.charging_price_list;
create policy "Owner can edit charging prices" on public.charging_price_list for update to authenticated using ((( SELECT current_app_role() AS current_app_role) = 'owner'::text)) with check ((( SELECT current_app_role() AS current_app_role) = 'owner'::text));
drop policy if exists "Owner can delete charging prices" on public.charging_price_list;
create policy "Owner can delete charging prices" on public.charging_price_list for delete to authenticated using ((( SELECT current_app_role() AS current_app_role) = 'owner'::text));
drop policy if exists "Owner can add charging prices" on public.charging_price_list;
create policy "Owner can add charging prices" on public.charging_price_list for insert to authenticated with check ((( SELECT current_app_role() AS current_app_role) = 'owner'::text));
drop policy if exists "Signed-in users can edit distributors" on public.distributors;
create policy "Signed-in users can edit distributors" on public.distributors for update to authenticated using (true) with check (true);
drop policy if exists "Signed-in users can add distributors" on public.distributors;
create policy "Signed-in users can add distributors" on public.distributors for insert to authenticated with check (true);
drop policy if exists "Team can view distributors" on public.distributors;
create policy "Team can view distributors" on public.distributors for select to authenticated using ((( SELECT current_app_role() AS current_app_role) IS NOT NULL));
drop policy if exists "Team can view expense_categories" on public.expense_categories;
create policy "Team can view expense_categories" on public.expense_categories for select to authenticated using ((( SELECT current_app_role() AS current_app_role) IS NOT NULL));
drop policy if exists "Team can view expenses" on public.expenses;
create policy "Team can view expenses" on public.expenses for select to authenticated using ((( SELECT current_app_role() AS current_app_role) = ANY (ARRAY['owner'::text, 'accountant'::text])));
drop policy if exists "Team can view scrap_battery_inventory" on public.scrap_battery_inventory;
create policy "Team can view scrap_battery_inventory" on public.scrap_battery_inventory for select to authenticated using ((( SELECT current_app_role() AS current_app_role) IS NOT NULL));
drop policy if exists "Team can view scrap_battery_sales" on public.scrap_battery_sales;
create policy "Team can view scrap_battery_sales" on public.scrap_battery_sales for select to authenticated using ((( SELECT current_app_role() AS current_app_role) IS NOT NULL));

drop trigger if exists aa_role_guard on public.battery_claims;
create trigger aa_role_guard BEFORE DELETE OR INSERT OR UPDATE on public.battery_claims for each row EXECUTE FUNCTION role_guard('owner,counter_staff', 'owner,counter_staff', 'owner');
drop trigger if exists zz_audit_row_change on public.battery_claims;
create trigger zz_audit_row_change AFTER INSERT OR DELETE OR UPDATE on public.battery_claims for each row EXECUTE FUNCTION audit_row_change();
drop trigger if exists battery_claims_set_updated_at on public.battery_claims;
create trigger battery_claims_set_updated_at BEFORE UPDATE on public.battery_claims for each row EXECUTE FUNCTION set_updated_at();
drop trigger if exists aa_role_guard on public.cash_settings;
create trigger aa_role_guard BEFORE DELETE OR UPDATE OR INSERT on public.cash_settings for each row EXECUTE FUNCTION role_guard('owner,accountant', 'owner,accountant', 'owner');
drop trigger if exists zz_audit_row_change on public.cash_settings;
create trigger zz_audit_row_change AFTER UPDATE OR DELETE OR INSERT on public.cash_settings for each row EXECUTE FUNCTION audit_row_change();
drop trigger if exists cash_settings_set_updated_at on public.cash_settings;
create trigger cash_settings_set_updated_at BEFORE UPDATE on public.cash_settings for each row EXECUTE FUNCTION set_updated_at();
drop trigger if exists aa_role_guard on public.charging_jobs;
create trigger aa_role_guard BEFORE DELETE OR INSERT OR UPDATE on public.charging_jobs for each row EXECUTE FUNCTION role_guard('owner,counter_staff', 'owner,counter_staff', 'owner');
drop trigger if exists zz_audit_row_change on public.charging_jobs;
create trigger zz_audit_row_change AFTER UPDATE OR DELETE OR INSERT on public.charging_jobs for each row EXECUTE FUNCTION audit_row_change();
drop trigger if exists charging_jobs_set_updated_at on public.charging_jobs;
create trigger charging_jobs_set_updated_at BEFORE UPDATE on public.charging_jobs for each row EXECUTE FUNCTION set_updated_at();
drop trigger if exists zz_audit_row_change on public.charging_price_list;
create trigger zz_audit_row_change AFTER DELETE OR INSERT OR UPDATE on public.charging_price_list for each row EXECUTE FUNCTION audit_row_change();
drop trigger if exists charging_price_list_set_updated_at on public.charging_price_list;
create trigger charging_price_list_set_updated_at BEFORE UPDATE on public.charging_price_list for each row EXECUTE FUNCTION set_updated_at();
drop trigger if exists zz_audit_row_change on public.distributors;
create trigger zz_audit_row_change AFTER UPDATE OR DELETE OR INSERT on public.distributors for each row EXECUTE FUNCTION audit_row_change();
drop trigger if exists distributors_set_updated_at on public.distributors;
create trigger distributors_set_updated_at BEFORE UPDATE on public.distributors for each row EXECUTE FUNCTION set_updated_at();
drop trigger if exists aa_role_guard on public.distributors;
create trigger aa_role_guard BEFORE UPDATE OR DELETE OR INSERT on public.distributors for each row EXECUTE FUNCTION role_guard('owner,counter_staff', 'owner', 'owner');
drop trigger if exists zz_audit_row_change on public.expenses;
create trigger zz_audit_row_change AFTER DELETE OR INSERT OR UPDATE on public.expenses for each row EXECUTE FUNCTION audit_row_change();
drop trigger if exists expenses_set_updated_at on public.expenses;
create trigger expenses_set_updated_at BEFORE UPDATE on public.expenses for each row EXECUTE FUNCTION set_updated_at();
drop trigger if exists aa_role_guard on public.expenses;
create trigger aa_role_guard BEFORE INSERT OR DELETE OR UPDATE on public.expenses for each row EXECUTE FUNCTION role_guard('owner,accountant', 'owner,accountant', 'owner');
drop trigger if exists scrap_battery_inventory_set_updated_at on public.scrap_battery_inventory;
create trigger scrap_battery_inventory_set_updated_at BEFORE UPDATE on public.scrap_battery_inventory for each row EXECUTE FUNCTION set_updated_at();
drop trigger if exists zz_audit_row_change on public.scrap_battery_inventory;
create trigger zz_audit_row_change AFTER INSERT OR DELETE OR UPDATE on public.scrap_battery_inventory for each row EXECUTE FUNCTION audit_row_change();
drop trigger if exists aa_role_guard on public.scrap_battery_inventory;
create trigger aa_role_guard BEFORE INSERT OR DELETE OR UPDATE on public.scrap_battery_inventory for each row EXECUTE FUNCTION role_guard('owner,counter_staff', 'owner,counter_staff', 'owner');
drop trigger if exists aa_role_guard on public.scrap_battery_sales;
create trigger aa_role_guard BEFORE DELETE OR UPDATE OR INSERT on public.scrap_battery_sales for each row EXECUTE FUNCTION role_guard('owner', 'owner', 'owner');
drop trigger if exists zz_audit_row_change on public.scrap_battery_sales;
create trigger zz_audit_row_change AFTER INSERT OR UPDATE OR DELETE on public.scrap_battery_sales for each row EXECUTE FUNCTION audit_row_change();

-- ======== 14_global_settings.sql ========
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

-- ======== 15_seed_and_reset_demo.sql ========
-- 15: demo data + hourly reset. Uses the app's OWN functions (create_invoice, record_payment,
-- create_purchase, save_supplier) so stock, totals and ledgers stay consistent.
-- All names, phones and emails are fictional. Dates are relative to today.

create or replace function public.seed_demo()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
  r record; v_items jsonb; v_total numeric; v_paid numeric; v_cust uuid; v_inv uuid;
  v_sup1 uuid; v_sup2 uuid; v_sup3 uuid;
begin
  select user_id into v_owner from public.user_roles where role = 'owner' and is_active order by created_at limit 1;
  if v_owner is null then raise exception 'seed_demo: create the demo user first (it becomes the Owner in step 08).'; end if;
  -- act as the demo owner so the app functions and role guards accept the calls
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);

  update public.business_profile set
    business_name = 'PowerCell Batteries & Solar', address = '12 Example Street, Demo City',
    phone = '+15550100100', ntn = null, province = null, currency = 'USD', locale = 'en-US', country = 'US',
    tax_label = 'Sales tax', tax_rate = 0, tax_id_label = 'Tax ID', tax_id = 'DEMO-000000';

  insert into public.expense_categories(name, sort_order)
  select n, o from (values ('Rent',1),('Electricity',2),('Salaries',3),('Fuel & delivery',4),('Marketing',5),('Repairs',6),('Other',7)) v(n,o)
  where not exists (select 1 from public.expense_categories);

  -- ---------- stock ----------
  insert into public.inventory(category,brand,model,type,voltage,plates,ah_rating,wattage,warranty_months,cost_price,sale_price,quantity,reorder_level) values
   ('battery','VoltMax','VM-45','Car',12,9,45,null,18,55,78,14,5),
   ('battery','VoltMax','VM-65','Car',12,13,65,null,24,70,95,16,5),
   ('battery','VoltMax','VM-100','Truck / SUV',12,15,100,null,24,105,140,8,4),
   ('battery','Enduro','EN-12','Motorcycle',12,null,12,null,12,18,29,22,8),
   ('battery','Enduro','EN-7','Motorcycle',12,null,7,null,12,12,20,9,8),
   ('battery','Enduro','TB-150','Tubular (inverter)',12,null,150,null,36,150,199,7,3),
   ('battery','Enduro','TB-200','Tubular (inverter)',12,null,200,null,36,190,255,5,3),
   ('battery','SunGrid','SG-100','Deep cycle (solar)',12,null,100,null,30,120,165,6,4),
   ('panel','SunGrid','SP-400','Mono 400W',null,null,null,400,120,95,130,30,10),
   ('panel','SunGrid','SP-550','Mono 550W',null,null,null,550,120,125,170,24,10),
   ('panel','SunGrid','SP-200','Mono 200W',null,null,null,200,120,55,78,4,6),
   ('accessory','SunGrid','CC-30','MPPT charge controller 30A',null,null,null,null,24,38,60,12,5),
   ('accessory','SunGrid','CC-60','MPPT charge controller 60A',null,null,null,null,24,85,125,3,4),
   ('accessory','SunGrid','INV-1000','Inverter 1 kW',null,null,null,null,24,140,195,8,3),
   ('accessory','SunGrid','INV-3000','Hybrid inverter 3 kW',null,null,null,null,24,420,575,4,2),
   ('accessory','Enduro','CB-35','Battery cable 35 mm (per metre)',null,null,null,null,null,6,11,50,15),
   ('accessory','Enduro','DW-5L','Distilled water 5 L',null,null,null,null,null,1.5,3,40,15),
   ('accessory','Enduro','TM-02','Terminal clamp (pair)',null,null,null,null,null,2,5,5,10),
   ('accessory','VoltMax','MC-10','Battery charger 12V 10A',null,null,null,null,12,20,34,11,4),
   ('accessory','SunGrid','MB-4','Mounting rail kit (4 panels)',null,null,null,null,null,45,70,14,5);

  -- ---------- customers ----------
  insert into public.customers(name, phone, address) values
   ('Sam Carter','+15550100101','14 Oak Lane'),
   ('Northside Garage','+15550100102','80 Industrial Rd'),
   ('BrightRoof Solar Installers','+447700900101','5 Solar Way'),
   ('Metro Cab Fleet','+447700900102','Depot 3, Ring Road'),
   ('Priya Nair','+971500000103','Marina Walk, Apt 12'),
   ('Omar Haddad','+971500000104','Al Quoz Industrial 2'),
   ('Lena Fischer','+15550100105','7 Birch Street'),
   ('GreenField Farm','+447700900103','Green Field Rd');

  -- ---------- suppliers (purchases) ----------
  v_sup1 := public.save_supplier(null,'VoltMax Distribution','+15550100201','Warehouse 4, Trade Park',null,null,0,null);
  v_sup2 := public.save_supplier(null,'SunGrid Wholesale','+447700900201','Unit 9, Energy Estate',null,null,0,null);
  v_sup3 := public.save_supplier(null,'Enduro Power Supplies','+97140000203','Dubai Industrial City',null,null,0,null);

  -- ---------- sales: [days ago, customer, items(model,qty), paid: full|part|none] ----------
  for r in select * from jsonb_to_recordset('[
    {"d":58,"c":null,"i":[["VM-65",1]],"p":"full"},
    {"d":55,"c":"Northside Garage","i":[["VM-45",2],["DW-5L",3]],"p":"full"},
    {"d":50,"c":"Sam Carter","i":[["EN-12",1]],"p":"full"},
    {"d":46,"c":"BrightRoof Solar Installers","i":[["SP-400",6],["CC-30",1],["MB-4",1]],"p":"part"},
    {"d":42,"c":null,"i":[["EN-7",2],["TM-02",1]],"p":"full"},
    {"d":38,"c":"Metro Cab Fleet","i":[["VM-100",3]],"p":"part"},
    {"d":34,"c":"Priya Nair","i":[["TB-150",1],["INV-1000",1]],"p":"full"},
    {"d":30,"c":"Omar Haddad","i":[["VM-65",2],["MC-10",1]],"p":"none"},
    {"d":27,"c":null,"i":[["VM-45",1],["CB-35",4]],"p":"full"},
    {"d":23,"c":"GreenField Farm","i":[["SG-100",2],["SP-550",4],["CC-60",1]],"p":"part"},
    {"d":19,"c":"Lena Fischer","i":[["EN-12",1],["DW-5L",2]],"p":"full"},
    {"d":15,"c":"Northside Garage","i":[["VM-65",3]],"p":"none"},
    {"d":11,"c":"BrightRoof Solar Installers","i":[["SP-550",8],["INV-3000",1]],"p":"part"},
    {"d":7,"c":null,"i":[["EN-7",1]],"p":"full"},
    {"d":4,"c":"Sam Carter","i":[["VM-65",1],["TM-02",2]],"p":"full"},
    {"d":2,"c":"Metro Cab Fleet","i":[["VM-100",1],["TB-200",1]],"p":"part"},
    {"d":0,"c":null,"i":[["SP-200",1]],"p":"full"}
  ]'::jsonb) as x(d int, c text, i jsonb, p text) loop
    select coalesce(jsonb_agg(jsonb_build_object('inventory_id', inv.id, 'quantity', (e->>1)::int, 'rate', inv.sale_price)),'[]'::jsonb),
           coalesce(sum(inv.sale_price * (e->>1)::int),0)
      into v_items, v_total
      from jsonb_array_elements(r.i) e join public.inventory inv on inv.model = e->>0;
    v_paid := case r.p when 'full' then v_total when 'part' then round(v_total * 0.5, 2) else 0 end;
    v_cust := (select id from public.customers where name = r.c);
    perform public.create_invoice(v_cust, case when r.c is null then 'Walk-in customer' end, null,
                                  current_date - r.d, v_items, v_paid, 'cash');
  end loop;

  -- a couple of later payments against credit bills
  for r in select i.id, (b.due_total)::numeric as due from public.invoices i
           join public.invoice_balances b on b.id = i.id
           where b.due_total > 0 and b.status <> 'cancelled' order by i.invoice_date limit 2 loop
    perform public.record_payment(r.id, round(r.due * 0.4, 2), 'cash');
  end loop;

  -- ---------- purchases: restock ----------
  perform public.create_purchase(gen_random_uuid(), v_sup1, null,null,null, 'VD-1001', current_date-40, null,
     jsonb_build_array(jsonb_build_object('inventory_id',(select id from public.inventory where model='VM-65'),'quantity',10,'unit_cost',70,'keep_old_cost',false),
                       jsonb_build_object('inventory_id',(select id from public.inventory where model='VM-45'),'quantity',6,'unit_cost',55,'keep_old_cost',false)),
     0, 0, 800, 'cash', null, null, null, null);
  perform public.create_purchase(gen_random_uuid(), v_sup2, null,null,null, 'SW-2044', current_date-21, null,
     jsonb_build_array(jsonb_build_object('inventory_id',(select id from public.inventory where model='SP-550'),'quantity',12,'unit_cost',125,'keep_old_cost',false)),
     0, 40, 500, 'cash', null, null, null, null);
  perform public.create_purchase(gen_random_uuid(), v_sup3, null,null,null, 'EP-310', current_date-8, null,
     jsonb_build_array(jsonb_build_object('inventory_id',(select id from public.inventory where model='TB-150'),'quantity',4,'unit_cost',150,'keep_old_cost',false)),
     0, 0, 0, 'cash', null, null, null, null);

  -- ---------- expenses ----------
  insert into public.expenses(category_id, amount, expense_date, method, paid_to, note)
  select c.id, v.a, current_date - v.d, v.m, v.p, v.n
  from (values ('Rent',1200,50,'online','Landlord LLC','Shop rent'),('Rent',1200,20,'online','Landlord LLC','Shop rent'),
               ('Electricity',185,45,'online','City Power','Monthly bill'),('Electricity',172,15,'online','City Power','Monthly bill'),
               ('Salaries',1800,48,'cash','Staff','Monthly salaries'),('Salaries',1800,18,'cash','Staff','Monthly salaries'),
               ('Fuel & delivery',60,33,'cash','Fuel station','Delivery van'),('Marketing',150,26,'online','Local Ads Co','Flyers and online ads'),
               ('Repairs',75,12,'cash','Fix-It Co','Shelf repair'),('Other',40,5,'cash','Office store','Stationery')) v(cat,a,d,m,p,n)
  join public.expense_categories c on c.name = v.cat;

  -- ---------- battery services ----------
  insert into public.battery_claims(customer_id, customer_name, customer_phone, battery_brand, battery_model, battery_number,
        distributor_id, claim_amount, note, status, received_date, sent_to_distributor_at, approved_at, rejected_at, given_to_customer_at) values
   ((select id from public.customers where name='Sam Carter'),'Sam Carter','+15550100101','VoltMax','VM-65','VM65-2291',v_sup1,null,'Will not hold charge','received',current_date-3,null,null,null,null),
   ((select id from public.customers where name='Northside Garage'),'Northside Garage','+15550100102','VoltMax','VM-45','VM45-1180',v_sup1,95,'Dead cell, within warranty','sent_to_distributor',current_date-12,now()-interval '9 days',null,null,null),
   ((select id from public.customers where name='Metro Cab Fleet'),'Metro Cab Fleet','+447700900102','VoltMax','VM-100','VM100-0712',v_sup1,140,'Swollen case','approved',current_date-25,now()-interval '22 days',now()-interval '15 days',null,null),
   (null,'Walk-in customer',null,'Enduro','EN-7','EN7-0045',v_sup3,null,'Customer misuse, not covered','rejected',current_date-30,now()-interval '27 days',null,now()-interval '20 days',null),
   ((select id from public.customers where name='Lena Fischer'),'Lena Fischer','+15550100105','Enduro','EN-12','EN12-5521',v_sup3,29,'Replaced under warranty','given_to_customer',current_date-40,now()-interval '36 days',now()-interval '30 days',null,now()-interval '26 days');

  insert into public.charging_jobs(customer_id, customer_name, customer_phone, battery_brand, battery_model, price, note, received_date, due_date, status, collected_at, outcome) values
   ((select id from public.customers where name='Priya Nair'),'Priya Nair','+971500000103','VoltMax','VM-65',8,'Deep charge',current_date,current_date+1,'in_shop',null,null),
   (null,'Walk-in customer',null,'Enduro','EN-12',4,'Quick charge',current_date-1,current_date,'in_shop',null,null),
   ((select id from public.customers where name='Omar Haddad'),'Omar Haddad','+971500000104','Enduro','TB-150',15,'Inverter battery top-up',current_date-6,current_date-4,'collected',now()-interval '4 days','charged'),
   (null,'Walk-in customer',null,'VoltMax','VM-45',0,'Would not take charge',current_date-9,current_date-7,'collected',now()-interval '7 days','faulty');

  insert into public.scrap_battery_inventory(customer_name, brand, model, battery_type, quantity, estimated_weight_kg, note, status, received_date) values
   ('Sam Carter','VoltMax','Old 45Ah','Car',1,11,'Trade-in','in_stock',current_date-4),
   ('Northside Garage','Mixed','Assorted','Car',4,44,'Garage lot','in_stock',current_date-14),
   (null,'Enduro','Old 12Ah','Motorcycle',2,6,'Walk-in trade-in','in_stock',current_date-9);

  insert into public.cash_settings(opening_balance, opening_date)
  select 5000, current_date - 60 where not exists (select 1 from public.cash_settings);
end $$;

-- Wipes ALL transactional data and re-seeds. Keeps user_roles, business_profile, expense_categories.
create or replace function public.reset_demo()
returns void language plpgsql security definer set search_path = public as $$
begin
  truncate table
    public.invoice_items, public.invoices, public.payments,
    public.purchase_items, public.purchase_invoices, public.supplier_payments,
    public.expenses, public.stock_movements, public.battery_claims, public.charging_jobs,
    public.scrap_battery_sales, public.scrap_battery_inventory,
    public.customers, public.inventory, public.distributors, public.audit_log, public.ai_actions,
    public.fbr_invoice_items, public.fbr_invoices, public.fbr_submissions
    restart identity cascade;
  perform setval(c.oid, 1, false) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'S';
  delete from public.cash_settings;
  perform public.seed_demo();
end $$;

revoke all on function public.seed_demo(), public.reset_demo() from public, anon, authenticated;
grant execute on function public.seed_demo(), public.reset_demo() to service_role;

-- First load (run once after creating the demo user):
--   select public.reset_demo();
-- Hourly reset (Supabase Dashboard > Integrations > Cron, or pg_cron):
--   select cron.schedule('reset-demo-hourly', '0 * * * *', 'select public.reset_demo()');

