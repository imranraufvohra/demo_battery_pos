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
