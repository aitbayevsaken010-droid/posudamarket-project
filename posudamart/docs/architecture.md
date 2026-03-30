# Architecture — Stage 1 Foundation

## Current stack
- Frontend: static HTML/CSS/JS pages.
- Backend: Supabase Auth + Postgres + Storage.
- Access control: client-side guards + DB/RLS-side policies (to be expanded in next stages).

## Domain-oriented structure introduced
- `shared/domain/constants.js` — single source of truth for enums/constants.
- `shared/domain/access-control.js` — reusable access context and approval-aware role checks.
- `shared/{admin, supplier, client, wholesaler}.js` — role-specific entry points using common access layer.
- `sql/migrations/20260330_marketplace_foundation.sql` — normalized data model foundation.

## Domains mapped in foundation
- auth
- users/profiles
- roles/approvals
- catalog
- supplier
- wholesaler
- customer
- orders
- inventory
- replenishment
- returns
- admin

## Stage 1 scope completed
- Introduced strict target role model (`admin|supplier|wholesaler|customer`).
- Added approval-aware access foundation.
- Added schema skeleton and core links for all required business domains.
- Added wholesaler role entry path and protected starter pages.

## Out of scope for Stage 1
- Full order lifecycles implementation.
- Replenishment calculation engine and UI.
- Goods receiving flow with defect handling UX.
- Full returns workflow automation.
