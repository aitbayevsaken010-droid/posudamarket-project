# Roadmap — Next Steps After Stage 2

## Stage 3 (recommended): procurement + receiving runtime
1. Supplier order lifecycle on top of `supplier_products` (boxes only).
2. Goods receiving (good/defect qty) -> `inventory_movements` and piece-level stock activation.
3. Supplier selection UX for same canonical article from multiple suppliers.
4. RLS hardening for catalog tables and projections per role.

## Stage 4: customer sales runtime
1. Customer checkout flow from wholesaler inventory projection.
2. Reservation/decrement/release engine for `wholesaler_inventory_items`.
3. Customer order status pipeline and cancellation effects.

## Stage 5: replenishment and returns
1. Replenishment demand automation from sales + stock gaps.
2. Wholesaler-to-supplier and customer-to-wholesaler returns workflows.
3. Expanded audit logging for product/procurement/inventory critical actions.
