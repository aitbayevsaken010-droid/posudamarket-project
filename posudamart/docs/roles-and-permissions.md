# Roles and Permissions — Stage 3 Runtime Rules

## Roles
- `admin`
- `supplier`
- `wholesaler`
- `customer`

## Procurement permissions (enforced in DB RPC)

### Wholesaler
- can create procurement orders only through `pm_submit_procurement_cart`.
- can confirm/cancel changed supplier orders only for own `wholesaler_id`.
- can perform receiving only for own orders (`pm_wholesaler_receive_order`).

### Supplier
- can adjust quantities only for own incoming supplier orders.
- cannot increase `confirmed_boxes` above `requested_boxes`.
- can set logistics statuses (`processing`, `shipped`, `in_transit`) only for own orders.

### Admin
- read visibility through admin UI page over supplier orders + receiving summaries.
- no new admin mutation RPC added in Stage 3.

## Validation highlights
- `requested_boxes > 0`.
- `confirmed_boxes >= 0` and `<= requested_boxes`.
- `received_units >= 0`.
- `damaged_units >= 0`.
- `damaged_units <= received_units`.
- receiving bounded by remaining confirmed units.
- inventory quantities stay non-negative by table constraints and additive receiving updates.
