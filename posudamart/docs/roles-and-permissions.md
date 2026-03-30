# Roles and permissions (runtime)

## Admin
- Full visibility into customer order runtime and replenishment demand summary.
- Can update customer order statuses through the same guarded SQL transition logic.

## Supplier
- Stage 3 scope preserved: supplier procurement lifecycle only.
- Stage 4 customer order runtime does not grant supplier direct mutation rights.

## Wholesaler
- Views incoming customer orders for its own wholesaler profile.
- Allowed to move order through operational statuses (`confirmed`, `processing`, `ready_for_pickup`/`shipped`, `completed`, `cancelled`).
- Sees active replenishment demand aggregated by product.

## Customer
- Can manage own cart and create checkout only as customer role.
- Can view only own customer orders.
- Can cancel only allowed early statuses (`new`, `confirmed`).
- Cannot force finalize or alter other customers' orders.

## Guardrails implemented in DB runtime
- `pm_require_customer` enforces role for checkout/cart RPCs.
- `pm_set_customer_order_status` validates:
  - actor ownership/scope,
  - allowed transitions,
  - no cancelled->completed,
  - terminal state protection.
- Inventory updates in reservation release/finalize use guarded predicates to prevent negative stock states.

## Notes
- Stage 4 keeps full-order cancellation only (no partial item-level cancel yet).
- Demand is generated only from finalized sale path (`completed`) and tied to real `customer_order_items`.
