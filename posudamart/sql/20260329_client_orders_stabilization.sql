-- Stabilization for client/supplier order workflow fields and statuses.
-- Safe to run multiple times.

alter table public.client_orders
  add column if not exists delivery_address text,
  add column if not exists client_name text,
  add column if not exists client_email text,
  add column if not exists supplier_comment text,
  add column if not exists updated_by text,
  add column if not exists updated_at timestamptz default now();

-- Backfill optional display fields from profiles when available.
update public.client_orders co
set client_name = p.full_name,
    client_email = p.email
from public.profiles p
where co.client_id = p.id
  and (co.client_name is null or co.client_email is null);

-- Ensure status is from the supported lifecycle.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'client_orders_status_workflow_check'
      and conrelid = 'public.client_orders'::regclass
  ) then
    alter table public.client_orders
      add constraint client_orders_status_workflow_check
      check (status in ('Черновик','Новый','Изменён','Подтверждён','Принят','Завершён','Отменён'));
  end if;
end
$$;
