-- Stage 2: runtime-ready product/catalog model.

alter table if exists public.catalog_products
  alter column article type text,
  alter column article set not null;

update public.catalog_products
set article = upper(regexp_replace(trim(article), '\\s+', '-', 'g'))
where article is not null;

create unique index if not exists ux_catalog_products_article_normalized
  on public.catalog_products (lower(trim(article)));

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chk_catalog_products_article_not_blank') then
    alter table public.catalog_products
      add constraint chk_catalog_products_article_not_blank check (btrim(article) <> '');
  end if;
end $$;

alter table if exists public.catalog_product_variants
  add column if not exists is_active boolean not null default true;

create unique index if not exists ux_catalog_product_variants_product_variant_name
  on public.catalog_product_variants (product_id, lower(trim(variant_name)));

alter table if exists public.catalog_product_images
  add column if not exists variant_id uuid references public.catalog_product_variants(id) on delete cascade,
  add column if not exists is_primary boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists ux_catalog_product_images_scope_sort
  on public.catalog_product_images (product_id, coalesce(variant_id, '00000000-0000-0000-0000-000000000000'::uuid), sort_order);

alter table if exists public.supplier_products
  add column if not exists units_per_box integer,
  add column if not exists price_per_box numeric(14,2),
  add column if not exists derived_unit_price numeric(14,4) generated always as (
    case
      when coalesce(units_per_box, pieces_per_box, 0) > 0 then round((coalesce(price_per_box, box_price, 0)::numeric / coalesce(units_per_box, pieces_per_box)::numeric), 4)
      else null
    end
  ) stored,
  add column if not exists is_active boolean not null default true;

update public.supplier_products
set units_per_box = coalesce(units_per_box, pieces_per_box),
    price_per_box = coalesce(price_per_box, box_price)
where units_per_box is null or price_per_box is null;

alter table if exists public.supplier_products
  alter column units_per_box set not null,
  alter column price_per_box set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chk_supplier_products_units_per_box_positive') then
    alter table public.supplier_products
      add constraint chk_supplier_products_units_per_box_positive check (units_per_box > 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'chk_supplier_products_price_per_box_non_negative') then
    alter table public.supplier_products
      add constraint chk_supplier_products_price_per_box_non_negative check (price_per_box >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'chk_supplier_products_supplier_article_not_blank') then
    alter table public.supplier_products
      add constraint chk_supplier_products_supplier_article_not_blank check (supplier_article is null or btrim(supplier_article) <> '');
  end if;
end $$;

create unique index if not exists ux_supplier_products_supplier_article
  on public.supplier_products (supplier_user_id, lower(trim(supplier_article)))
  where supplier_article is not null and btrim(supplier_article) <> '';

create index if not exists idx_supplier_products_active_category
  on public.supplier_products (is_active, product_id, supplier_user_id);

create index if not exists idx_catalog_products_category_active
  on public.catalog_products (category_id, is_active);

create index if not exists idx_wholesaler_inventory_active_catalog
  on public.wholesaler_inventory_items (wholesaler_id, product_id, available_qty);
