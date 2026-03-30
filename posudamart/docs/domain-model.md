# Domain Model — Stage 1 Foundation

## Core identity
- `profiles` (existing, extended): account role + account status.
- `role_approvals`: approval requests/decisions for supplier and wholesaler roles.
- `cities`: normalized city dictionary for wholesaler location.
- `wholesalers`: wholesaler legal/profile/location aggregate.

## Catalog
- `catalog_categories`
- `catalog_products`
- `catalog_product_variants`
- `catalog_product_images`
- `supplier_products` (supplier-specific box economics and mapping to canonical product)

## Inventory / sales
- `wholesaler_inventory_items` (piece-level stock)
- `inventory_movements` (event journal)
- `customer_orders`
- `customer_order_items`

## B2B procurement
- `supplier_orders`
- `supplier_order_items`

## Replenishment
- `replenishment_demands` (aggregated uncovered demand per product/variant, supplier-agnostic)
- `replenishment_demand_events` (history and traceability)

## Returns
- `returns`
- `return_items`

## Auditability
- `audit_log` for key business events.
