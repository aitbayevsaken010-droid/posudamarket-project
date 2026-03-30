# Roadmap — Next Steps After Stage 1

## Stage 2 (recommended)
1. Migrate runtime writes from legacy entities to new normalized tables.
2. Implement admin approval cabinet for both supplier and wholesaler requests (`role_approvals`).
3. Add wholesaler onboarding profile form (city + warehouse + legal details).
4. Align RLS policies with new role model and approval-aware access.

## Stage 3
1. Implement supplier order confirmation negotiation flow (full/partial + return for wholesaler confirmation).
2. Implement wholesaler goods receiving (actual qty, defect qty, defect photo).
3. Activate piece-level inventory movement pipeline.

## Stage 4
1. Implement customer storefront from wholesaler inventory only.
2. Immediate stock reservation/decrement on order placement.
3. Stock return on cancellation.

## Stage 5
1. Implement replenishment demand engine and active queue rules:
   - demand aggregate by product/variant only;
   - visible after >3 sales events;
   - round-up to full boxes;
   - auto-close demand after covered procurement;
   - preserve historical demand events.
2. Implement returns workflows in both directions.
3. Expand audit logs with key event emitters.
