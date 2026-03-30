# Architecture — Stage 2 Catalog Runtime

## Core principle
Stage 2 switches product runtime from legacy flat tables (`products`, `categories`) to normalized catalog domain introduced in Stage 1 foundation.

## Runtime layers
- `shared/domain/catalog.js`
  - input normalization (`article`, image URL, money),
  - supplier mutation validation,
  - role-aware guard for supplier mutations,
  - mappers:
    - supplier offerings -> wholesaler catalog DTO,
    - wholesaler inventory -> customer catalog DTO.
- Role entry points remain in `shared/{supplier,client,wholesaler,admin}.js`.

## Data model usage
- Write path (supplier):
  1. validate payload,
  2. upsert/find canonical `catalog_products` by normalized article,
  3. write variants/images,
  4. create/update `supplier_products`.
- Read path (wholesaler): category-first browsing of active supplier offerings.
- Read path (customer): category-first browsing of wholesaler inventory projection only.
- Read path (admin): visibility into categories and supplier-owned offerings/status.

## Derived unit price decision
`derived_unit_price` is **stored generated** in DB (`supplier_products`) from `price_per_box / units_per_box`.
Reason: keeps deterministic economics, avoids UI drift, and allows indexing/filtering in later procurement stages.

## Legacy status
- Legacy pages tied to `products/categories` are partially replaced for Stage 2 catalog pages.
- Legacy order flows are preserved and intentionally not fully migrated in Stage 2.
