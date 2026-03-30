# Roadmap — Next Steps After Stage 3

## What Stage 3 now covers
1. Real procurement cart to supplier-order conversion split by supplier.
2. Supplier-side quantity adjustment (decrease-only) and confirmation path.
3. Wholesaler receiving with damaged split and attachment metadata.
4. Persistent inventory movement records from receiving outcomes.

## Stage 4 priorities (recommended)
1. Customer order runtime integrated with `available_qty` + reservation engine.
2. Reservation lifecycle (`reservation_hold`/`reservation_release`) runtime logic.
3. Stronger receiving reconciliation dashboards (remaining-to-receive KPIs).
4. RLS hardening for all new procurement/receiving tables and RPC grants.

## Stage 5 priorities
1. Replenishment automation from sales/reservation pressure.
2. Return lifecycle runtime (supplier/wholesaler/customer paths).
3. Production-grade media subsystem for shipment/receiving attachments.
