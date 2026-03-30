# Roles and Permissions — Stage 1 Foundation

## Roles
- `admin`
- `supplier`
- `wholesaler`
- `customer`

Legacy role `client` is normalized to `customer` in access layer for backward compatibility.

## One account = one role
- The target model is fixed through app-level constants and DB enum `app_role`.
- `profiles.role_new` introduced as strongly typed role column for migration to strict single-role profile.

## Approval rules
- `supplier`: manual admin approval required.
- `wholesaler`: manual admin approval required.
- `customer`: no manual approval required.
- `admin`: operational role, no approval flow.

## Access foundation implemented
- `PM_ACCESS.loadAccessContext()` loads role + approval context.
- `PM_ACCESS.hasRouteAccess()` enforces role-based page entry.
- `PM_ACCESS.canEnterBusinessSection()` blocks unapproved supplier/wholesaler access.

## Current coverage
- Admin pages: admin-only guard.
- Supplier pages: supplier-only + approved-only.
- Client/customer pages: customer role support (`customer` + legacy `client`).
- Wholesaler pages: wholesaler-only + approved-only (foundation pages).
