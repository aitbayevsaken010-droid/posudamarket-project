# Domain model (runtime-focused)

## Existing inventory core (Stage 3)
- `wholesaler_inventory_items`
  - `available_qty`, `reserved_qty`, `on_hand_qty`, `damaged_qty`
- `inventory_movements`
  - `procurement_received`, `damaged_on_receiving` (Stage 3)

## Stage 4 customer order runtime entities
- `customer_carts`
  - one open cart per customer, bound to one wholesaler.
- `customer_cart_items`
  - unit-based quantities (`quantity > 0`) by `inventory_item_id`.
- `customer_orders`
  - lifecycle status, totals, cancellation metadata.
- `customer_order_items`
  - immutable line snapshot (qty + unit price + product identity).
- `customer_order_status_history`
  - persistent order status history with actor and metadata.
- `stock_reservations`
  - runtime reservation state machine:
    - `active` (hold),
    - `released` (cancel release),
    - `finalized` (completed sale).

## Stage 4 replenishment demand runtime
- `replenishment_demands`
  - aggregate by `(wholesaler_id, product_id, variant_id)` and active status,
  - tracks `sold_qty`, `sales_count`, `uncovered_qty`,
  - computes `suggested_boxes`, `suggested_qty`, `pieces_per_box`.
- `replenishment_demand_events`
  - immutable event stream (`demand_opened`, `sale_finalized`, future coverage events).

## Runtime functions introduced/used in Stage 4
- Cart runtime:
  - `pm_customer_cart_get_or_create`
  - `pm_customer_cart_upsert_item`
  - `pm_customer_cart_set_item_quantity`
  - `pm_customer_cart_remove_item`
- Checkout + reservation:
  - `pm_checkout_customer_cart`
- Order lifecycle / reservation release+finalize:
  - `pm_set_customer_order_status`
  - `pm_customer_order_apply_cancellation`
  - `pm_customer_order_apply_completion`
- Demand helper:
  - `pm_estimate_units_per_box`

## Lifecycle statuses
`customer_order_status`:
- `new`
- `confirmed`
- `processing`
- `ready_for_pickup`
- `shipped`
- `completed`
- `cancelled`

## Movement semantics after Stage 4
- `procurement_received`: increases `available_qty` + `on_hand_qty`
- `damaged_on_receiving`: increases `damaged_qty`
- `reservation_hold`: decreases `available_qty`, increases `reserved_qty`
- `reservation_release`: increases `available_qty`, decreases `reserved_qty`
- `customer_sale`: decreases `reserved_qty` + `on_hand_qty`
