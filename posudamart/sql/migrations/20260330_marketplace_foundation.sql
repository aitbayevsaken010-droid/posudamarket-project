-- Stage 1 foundation for multi-role marketplace/ERP domain.
-- Non-destructive migration: adds normalized entities required for future phases.

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type public.app_role as enum ('admin', 'supplier', 'wholesaler', 'customer');
  end if;

  if not exists (select 1 from pg_type where typname = 'approval_status') then
    create type public.approval_status as enum ('not_required', 'pending', 'approved', 'rejected');
  end if;

  if not exists (select 1 from pg_type where typname = 'account_status') then
    create type public.account_status as enum ('active', 'inactive', 'blocked');
  end if;

  if not exists (select 1 from pg_type where typname = 'customer_order_status') then
    create type public.customer_order_status as enum ('new', 'confirmed', 'shipped', 'cancelled', 'completed');
  end if;

  if not exists (select 1 from pg_type where typname = 'supplier_order_status') then
    create type public.supplier_order_status as enum (
      'new',
      'adjusted_by_supplier',
      'awaiting_wholesaler_confirmation',
      'processing',
      'shipment_proof_attached',
      'in_transit',
      'cancelled',
      'completed'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'inventory_movement_type') then
    create type public.inventory_movement_type as enum (
      'receipt_good',
      'receipt_defect',
      'customer_sale',
      'customer_cancel_restock',
      'manual_adjustment',
      'return_in',
      'return_out'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'return_status') then
    create type public.return_status as enum ('requested', 'approved', 'rejected', 'in_transit', 'received', 'closed');
  end if;

  if not exists (select 1 from pg_type where typname = 'replenishment_status') then
    create type public.replenishment_status as enum ('open', 'partially_covered', 'covered', 'archived');
  end if;
end $$;

alter table if exists public.profiles
  add column if not exists account_status public.account_status default 'active',
  add column if not exists role_new public.app_role,
  add column if not exists updated_at timestamptz default now();

update public.profiles
set role_new = case
  when role = 'admin' then 'admin'::public.app_role
  when role = 'supplier' then 'supplier'::public.app_role
  when role = 'wholesaler' then 'wholesaler'::public.app_role
  else 'customer'::public.app_role
end
where role_new is null;

create table if not exists public.cities (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  country_code text not null default 'KZ',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lower(name), country_code)
);

create table if not exists public.role_approvals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  requested_role public.app_role not null,
  status public.approval_status not null default 'pending',
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_role_approvals_user_role on public.role_approvals(user_id, requested_role, created_at desc);

create table if not exists public.wholesalers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  legal_name text,
  display_name text,
  city_id uuid references public.cities(id),
  warehouse_address text,
  phone text,
  approval_status public.approval_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.catalog_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text,
  parent_id uuid references public.catalog_categories(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lower(name))
);

create table if not exists public.catalog_products (
  id uuid primary key default gen_random_uuid(),
  article text not null,
  name text not null,
  category_id uuid references public.catalog_categories(id),
  description text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (article)
);

create table if not exists public.catalog_product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.catalog_products(id) on delete cascade,
  variant_name text not null,
  sku text,
  unit text not null default 'pcs',
  attributes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.catalog_product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.catalog_products(id) on delete cascade,
  image_url text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_products (
  id uuid primary key default gen_random_uuid(),
  supplier_user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.catalog_products(id) on delete cascade,
  variant_id uuid references public.catalog_product_variants(id),
  supplier_article text,
  pieces_per_box integer not null check (pieces_per_box > 0),
  box_price numeric(14,2) not null check (box_price >= 0),
  min_boxes integer not null default 1 check (min_boxes > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (supplier_user_id, product_id, coalesce(variant_id, '00000000-0000-0000-0000-000000000000'::uuid))
);

create table if not exists public.wholesaler_inventory_items (
  id uuid primary key default gen_random_uuid(),
  wholesaler_id uuid not null references public.wholesalers(id) on delete cascade,
  product_id uuid not null references public.catalog_products(id),
  variant_id uuid references public.catalog_product_variants(id),
  available_qty integer not null default 0 check (available_qty >= 0),
  damaged_qty integer not null default 0 check (damaged_qty >= 0),
  reserved_qty integer not null default 0 check (reserved_qty >= 0),
  unit_sale_price numeric(14,2) check (unit_sale_price >= 0),
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (wholesaler_id, product_id, coalesce(variant_id, '00000000-0000-0000-0000-000000000000'::uuid))
);

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  inventory_item_id uuid not null references public.wholesaler_inventory_items(id) on delete cascade,
  movement_type public.inventory_movement_type not null,
  quantity integer not null,
  reason text,
  source_document_type text,
  source_document_id uuid,
  actor_user_id uuid references auth.users(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.customer_orders (
  id uuid primary key default gen_random_uuid(),
  wholesaler_id uuid not null references public.wholesalers(id),
  customer_user_id uuid not null references auth.users(id),
  status public.customer_order_status not null default 'new',
  total_amount numeric(14,2) not null default 0,
  currency text not null default 'KZT',
  placed_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.customer_orders(id) on delete cascade,
  inventory_item_id uuid not null references public.wholesaler_inventory_items(id),
  product_id uuid not null references public.catalog_products(id),
  variant_id uuid references public.catalog_product_variants(id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_orders (
  id uuid primary key default gen_random_uuid(),
  wholesaler_id uuid not null references public.wholesalers(id),
  supplier_user_id uuid not null references auth.users(id),
  status public.supplier_order_status not null default 'new',
  order_total numeric(14,2) not null default 0,
  currency text not null default 'KZT',
  supplier_comment text,
  shipment_proof_url text,
  placed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.supplier_order_items (
  id uuid primary key default gen_random_uuid(),
  supplier_order_id uuid not null references public.supplier_orders(id) on delete cascade,
  supplier_product_id uuid not null references public.supplier_products(id),
  requested_boxes integer not null check (requested_boxes > 0),
  confirmed_boxes integer,
  box_price numeric(14,2) not null check (box_price >= 0),
  pieces_per_box integer not null check (pieces_per_box > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.replenishment_demands (
  id uuid primary key default gen_random_uuid(),
  wholesaler_id uuid not null references public.wholesalers(id),
  product_id uuid not null references public.catalog_products(id),
  variant_id uuid references public.catalog_product_variants(id),
  sold_qty integer not null default 0,
  sales_count integer not null default 0,
  uncovered_qty integer not null default 0,
  pieces_per_box integer not null default 1,
  suggested_boxes integer not null default 0,
  suggested_qty integer not null default 0,
  status public.replenishment_status not null default 'open',
  activated_at timestamptz,
  covered_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (wholesaler_id, product_id, coalesce(variant_id, '00000000-0000-0000-0000-000000000000'::uuid), status)
);

create table if not exists public.replenishment_demand_events (
  id uuid primary key default gen_random_uuid(),
  demand_id uuid not null references public.replenishment_demands(id) on delete cascade,
  event_type text not null,
  quantity_delta integer,
  source_customer_order_item_id uuid references public.customer_order_items(id),
  source_supplier_order_item_id uuid references public.supplier_order_items(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.returns (
  id uuid primary key default gen_random_uuid(),
  return_direction text not null check (return_direction in ('customer_to_wholesaler','wholesaler_to_supplier')),
  status public.return_status not null default 'requested',
  customer_order_id uuid references public.customer_orders(id),
  supplier_order_id uuid references public.supplier_orders(id),
  requested_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.returns(id) on delete cascade,
  product_id uuid not null references public.catalog_products(id),
  variant_id uuid references public.catalog_product_variants(id),
  quantity integer not null check (quantity > 0),
  defect_qty integer not null default 0,
  defect_photo_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- bootstrap approval records for existing suppliers to keep old flow compatible
insert into public.role_approvals (user_id, requested_role, status, requested_at, decided_at)
select s.user_id,
       'supplier'::public.app_role,
       case when s.status = 'active' then 'approved'::public.approval_status
            when s.status = 'rejected' then 'rejected'::public.approval_status
            else 'pending'::public.approval_status end,
       coalesce(s.created_at, now()),
       case when s.status in ('active','rejected') then now() else null end
from public.suppliers s
where not exists (
  select 1 from public.role_approvals ra
  where ra.user_id = s.user_id and ra.requested_role = 'supplier'::public.app_role
);
