# Architecture — Stage 3 Procurement Runtime

## What changed from Stage 1 + Stage 2
- Stage 1 foundation entities are kept and extended (no second order architecture).
- Stage 2 canonical catalog remains source of truth for product identity.
- Stage 3 adds runtime procurement bridge: `supplier_products` → `supplier_orders` → receiving → `wholesaler_inventory_items` + `inventory_movements`.

## Runtime modules
- `shared/domain/catalog.js`
  - unchanged core canonical catalog + supplier offering behavior.
- `shared/domain/procurement.js` (new)
  - status labels/mappers,
  - order normalization,
  - cart submit RPC call,
  - role page helper loaders for supplier/wholesaler views.

## Runtime flow (implemented)
1. Wholesaler browses supplier catalog and builds procurement cart.
2. Cart submit calls DB RPC `pm_submit_procurement_cart`.
3. DB splits cart by supplier and creates one `supplier_orders` per supplier.
4. Supplier adjusts or confirms quantities (`pm_supplier_adjust_order`).
5. Wholesaler confirms/cancels changed order (`pm_wholesaler_confirm_order`).
6. Supplier moves logistics statuses (`pm_supplier_set_logistics_status`).
7. Wholesaler receives with damaged split (`pm_wholesaler_receive_order`).
8. DB writes receiving records + inventory movements + updates stock.

## Persistence strategy
- All procurement/receiving/inventory operations persist in Supabase Postgres.
- No localStorage simulation for inventory updates.
- Status history persisted in `supplier_order_status_history`.

## Deliberate Stage 3 limits
- Attachment handling is metadata-only (`jsonb` with url/reference), not full media pipeline.
- Reservation hold/release movement types are prepared in enum but reservation runtime remains next stage.
