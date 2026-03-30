# Contract audit: frontend ↔ Supabase (2026-03-30)

## Scope and evidence

- Static audit covered all frontend Supabase calls in `posudamart/**/*.html` and `posudamart/shared/**/*.js`.
- Runtime verification against Supabase REST/GraphQL endpoints was attempted with project URL and anon key from runtime config, but the project returned HTTP `403 Forbidden` for metadata/data calls from this environment.
- Therefore, **"real production DB" is treated as**:
  1) confirmed incident fact: `public.profiles.account_status` is missing in production, and
  2) SQL contract declared by runtime migrations in `posudamart/sql/migrations`, with legacy delta scripts in `posudamart/sql/*.sql`.

## 1) Real DB schema used (contract baseline)

### Core identity/access tables (used by auth/guards)
- `profiles`: existing table altered by migration to add `account_status`, `role_new`, `updated_at`.
- `role_approvals`: `id,user_id,requested_role,status,requested_at,decided_at,decided_by,notes,created_at,updated_at`.
- `suppliers`: legacy table actively used by runtime code (`user_id,status,name,...`).
- `wholesalers`: `id,user_id,legal_name,display_name,city_id,warehouse_address,phone,approval_status,created_at,updated_at`.

### Catalog/procurement/customer tables used by runtime pages
- `catalog_categories`, `catalog_products`, `catalog_product_variants`, `catalog_product_images`.
- `supplier_products` (stage2 extends with `units_per_box`, `price_per_box`, `derived_unit_price`, `is_active`).
- `supplier_orders`, `supplier_order_items` (stage3 extends with snapshots and lifecycle fields).
- `wholesaler_inventory_items` (including `on_hand_qty`).
- `customer_orders`, `customer_order_items`, `customer_carts`, `customer_cart_items`.
- `replenishment_demands`, `replenishment_demand_events`.

### RPC/functions called by frontend (declared in migrations)
- Procurement: `pm_submit_procurement_cart`, `pm_supplier_adjust_order`, `pm_supplier_set_logistics_status`, `pm_wholesaler_confirm_order`, `pm_wholesaler_receive_order`.
- Customer sales: `pm_customer_cart_upsert_item`, `pm_customer_cart_set_item_quantity`, `pm_customer_cart_remove_item`, `pm_checkout_customer_cart`, `pm_set_customer_order_status`.

## 2) Frontend query inventory (all Supabase/PostgREST touchpoints)

### Active (new model) query surfaces
- Auth/access/profile: `profiles`, `role_approvals`, `suppliers`, `wholesalers`.
- Catalog: `catalog_categories`, `catalog_products`, `catalog_product_variants`, `catalog_product_images`, `supplier_products`.
- Orders/procurement/customer: `supplier_orders`, `supplier_order_items`, `customer_orders`, `customer_order_items`, `wholesaler_inventory_items`, `replenishment_demands`, `customer_carts`.
- RPC calls: `pm_*` functions listed above.
- Realtime: `suppliers`, `supplier_orders`, `supplier_products`.

### Legacy query surfaces still present in frontend
- Tables: `products`, `orders`, `categories`, `client_orders`, `app_settings`.
- Realtime legacy channels: table `orders`, table `client_orders`.

### Full inventory source
- Raw call inventory collected from code scan: `/tmp/query_calls.txt` (generated during audit run).

## 3) Mismatch detection (code vs DB contract)

### Confirmed mismatch (production fact)
1. `profiles.account_status` requested by frontend guard, missing in production `public.profiles`.
   - Impact: auth/profile bootstrap fails with 400.
   - Severity: **critical**.

### High-confidence structural mismatches (code vs migration contract)
2. Legacy tables used by frontend but not declared in runtime migrations:
   - `products`, `orders`, `categories`, `app_settings`.
   - Severity: high/critical depending on page.
3. `client_orders` used by legacy pages but absent from runtime migration set (exists only in legacy stabilization script).
   - Severity: high.
4. Legacy Russian status model used in old pages (`Закрыт`, `Отгружен`, `В истории`, etc.) while runtime migrations define enum statuses in English (`new`,`confirmed`,`processing`,...).
   - Severity: high.
5. Legacy realtime listeners attached to `orders` / `client_orders` in supplier dashboard.
   - Severity: high.

### Potential drift mismatches requiring direct DB introspection
6. Any column-level drift beyond `profiles.account_status` cannot be proven from this environment due 403 on direct introspection.

## 4) Page impact analysis

- **Entry / auth guards** (`index.html`, all role dashboards via shared guards):
  - `profiles.account_status` select mismatch → 400 → auth failure / redirect loop risk.
  - Severity: **critical**.
- **Supplier dashboard** (`supplier/sup-dashboard.html`):
  - depended on legacy `products/orders/client_orders` and legacy realtime tables.
  - With new DB-only deployments this breaks dashboard load and realtime refresh.
  - Severity: **critical**.
- **Admin catalog/history/suppliers legacy pages** (`admin/adm-catalog.html`, `admin/adm-history.html`, `admin/adm-suppliers.html` partly):
  - use legacy tables + statuses; can cause blank data or failed saves.
  - Severity: high.
- **Other pages** using new model (`wholesaler/*`, `client/*`, `supplier/sup-products.html`, `supplier/sup-orders.html`):
  - generally aligned with runtime migration model.
  - Severity: low to medium residual risk (depends on unverified prod drift).

## 5) Fix strategy per mismatch

- `profiles.account_status` in runtime path: **code must be changed** (do not request absent column in guard).
- Supplier dashboard legacy table usage: **code must be changed** to new model tables/RPC (`supplier_products` + `supplier_orders`).
- Remaining legacy admin pages on old tables:
  - If architecture target is new marketplace model: **code must be migrated** to new tables/status enums.
  - If business still requires legacy flow: **explicit DB compatibility layer/migrations** must be added and versioned (not ad-hoc SQL only).

## 6) Critical-first fixes applied in this patch

1. Removed `account_status` from access bootstrap profile query.
2. Reworked supplier dashboard data/realtime contract:
   - products count from `supplier_products` by `supplier_user_id`;
   - orders via `PM_PROCUREMENT.loadSupplierOrders` (`supplier_orders` + nested items);
   - realtime subscriptions moved to `supplier_orders` and `supplier_products`.

## 7) What is unblocked now

- App entry / role-based auth guard no longer requires missing `profiles.account_status`.
- Supplier dashboard no longer depends on legacy `products/orders/client_orders` tables.

## 8) Remaining mismatches

- Admin legacy pages still reference old tables/status model (`products/orders/categories/client_orders/app_settings`).
- These are **not** fixed in this patch by design (critical-first scope only).
- Full contract integrity requires second pass to migrate those pages or formalize backward-compatible DB objects.

## 9) Safety assessment for next stage

- **Partially safe**:
  - Critical app-entry and supplier-dashboard blockers addressed.
  - Project is **not fully contract-clean** due remaining legacy admin surfaces and inability to directly introspect production schema from this environment.
- Recommendation before next feature stage:
  1) run DB introspection with service-role access,
  2) reconcile all legacy admin pages,
  3) freeze a machine-readable contract (generated types/OpenAPI snapshot) and gate CI on it.
