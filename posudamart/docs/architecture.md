# Architecture (Stage 1 → Stage 4)

## Stage recap
- **Stage 1**: marketplace foundation schema + core role model.
- **Stage 2**: catalog runtime projection (`supplier_products` -> wholesaler/customer-facing catalog).
- **Stage 3**: procurement runtime (`procurement cart -> supplier_orders -> receiving -> inventory bridge`).
- **Stage 4 (current)**: customer operational runtime (`customer cart -> order -> reservation -> release/finalize -> replenishment demand`).

## Stage 4 operational loop
1. Customer browses **wholesaler inventory projection** (`wholesaler_inventory_items.available_qty > 0`).
2. Customer adds unit quantities to DB cart (`customer_carts`, `customer_cart_items`).
3. Checkout RPC `pm_checkout_customer_cart`:
   - validates stock availability at checkout time,
   - creates `customer_orders` + `customer_order_items`,
   - writes reservation records (`stock_reservations`),
   - writes `inventory_movements` with `reservation_hold`,
   - decrements `available_qty`, increments `reserved_qty`.
4. Order lifecycle managed by `pm_set_customer_order_status`:
   - cancellation -> reservation release + movement `reservation_release`,
   - completion -> sale finalization + movement `customer_sale`,
   - `on_hand_qty` reduced only on completion.
5. Completion writes replenishment demand runtime:
   - persists event in `replenishment_demand_events`,
   - updates active aggregate in `replenishment_demands` **by product/variant (not supplier)**,
   - computes box suggestion by upward rounding.

## Consistency rules
- Single source of truth for availability = `wholesaler_inventory_items.available_qty`.
- No second inventory subsystem introduced.
- Reservation and sale are DB-runtime actions (no UI-only simulation).
- Negative inventory prevented by checked update predicates in SQL runtime functions.

## UI/runtime scope in Stage 4
- Customer: catalog add-to-cart, cart, checkout, order list, customer cancel (full-order only).
- Wholesaler: incoming customer orders, allowed status transitions, active demand cards.
- Admin: visibility into customer orders and active demand summary.

## Not in Stage 4
- Payment gateway/finance settlement.
- Auto-procurement creation from demand.
- Automatic demand close by supplier receiving coverage (foundation prepared for next stage).
- Partial per-item cancellation.
