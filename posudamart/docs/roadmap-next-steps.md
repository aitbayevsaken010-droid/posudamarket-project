# Roadmap next steps

## Stage 4 (done in current increment)
1. Customer cart + checkout persisted in DB.
2. Reservation runtime (`reservation_hold` / `reservation_release` / `customer_sale`) integrated with existing inventory model.
3. Customer order lifecycle with status history and guarded transitions.
4. Sales-driven replenishment demand events + active product-level aggregation.
5. Wholesaler/admin visibility pages for customer orders and demand.

## Stage 5 priorities
1. Coverage runtime:
   - explicit demand coverage events from procurement receipts,
   - uncovered_qty decrement and automatic demand status transitions.
2. Order operations hardening:
   - optional partial item cancellation,
   - richer cancellation policies and audit notes.
3. UX + observability:
   - richer order detail pages,
   - inventory/reservation debug timeline,
   - alerts for low stock + high uncovered demand.
4. Security hardening:
   - explicit RLS policies for new Stage 4 tables,
   - dedicated SQL APIs for read projections.
5. Planning automation (optional):
   - procurement draft generation from active demand cards (still human-approved).

## Explicitly not completed yet
- Payment/settlement/finance runtime.
- Full supplier selection automation from demand.
- Forecasting engine.
- Automatic demand closure by receiving coverage.
