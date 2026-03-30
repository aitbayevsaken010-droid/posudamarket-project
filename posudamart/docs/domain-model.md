# Domain Model — Stage 2 Product/Catalog Runtime

## What is runtime-active in Stage 2

### Canonical product catalog
- `catalog_categories` — category tree/root categories for role-facing catalogs.
- `catalog_products` — base товарная сущность с контролируемой идентичностью по `article`.
- `catalog_product_variants` — варианты базового товара.
- `catalog_product_images` — изображения товара/варианта.

### Supplier offering layer
- `supplier_products` — предложение поставщика поверх canonical product:
  - supplier owner (`supplier_user_id`),
  - supplier article (`supplier_article`),
  - `units_per_box`,
  - `price_per_box`,
  - `derived_unit_price` (generated column),
  - active/inactive status.

### Role-facing projections
- **Wholesaler-facing catalog**: read model built from active `supplier_products` + canonical entities.
- **Customer-facing catalog**: read model built from `wholesaler_inventory_items` + canonical entities (supplier catalog is not exposed directly).

## Identity strategy
- Canonical identity of товар = normalized `catalog_products.article`.
- One article can have multiple supplier offerings through `supplier_products`.

## Stage 2 boundaries (explicitly not runtime here)
- Full procurement flow (supplier order negotiation/receiving) — next stage.
- Full customer checkout and reservation pipeline — next stage.
