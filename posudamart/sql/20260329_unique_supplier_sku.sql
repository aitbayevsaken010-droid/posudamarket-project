-- Enforce unique non-empty SKU/article per supplier.
create unique index if not exists ux_products_supplier_sku
on public.products (supplier_id, lower(trim(sku)))
where sku is not null and btrim(sku) <> '';
