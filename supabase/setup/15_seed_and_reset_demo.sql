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
