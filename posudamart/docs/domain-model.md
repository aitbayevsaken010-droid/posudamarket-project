# Domain Model — Stage 3 Procurement + Receiving

## Canonical catalog base (unchanged)
- `catalog_categories`
- `catalog_products`
- `catalog_product_variants`
- `catalog_product_images`
- `supplier_products`

## Procurement runtime entities
- `procurement_carts`
- `procurement_cart_items`
- `supplier_orders` (extended)
  - `procurement_cart_id`, shipment/receipt metadata fields, timestamps.
- `supplier_order_items` (extended)
  - snapshots: article/title/units_per_box/price_per_box,
  - requested/confirmed units,
  - cumulative receiving totals.
- `supplier_order_status_history`

## Receiving runtime entities
- `supplier_order_receivings`
- `supplier_order_receiving_items`
- `supplier_order_damaged_goods` (prepared for explicit damaged ledger records)

## Inventory bridge
- `wholesaler_inventory_items` extended with:
  - `on_hand_qty`,
  - `last_received_at`.
- `inventory_movements` uses new movement types:
  - `procurement_received`,
  - `damaged_on_receiving`,
  - (plus existing `manual_adjustment`, legacy movement types).

## Status lifecycle (stage 3 runtime)
- `new`
- `changed_by_supplier`
- `confirmed`
- `processing`
- `shipped`
- `in_transit`
- `received`
- `cancelled`

Compatibility status values from foundation (`adjusted_by_supplier`, `shipment_proof_attached`, `completed`) remain allowed for backward compatibility.
