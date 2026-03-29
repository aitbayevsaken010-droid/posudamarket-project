-- Full stabilization for unified client/supplier/admin order workflow.
-- Safe to run multiple times.

alter table public.client_orders
  add column if not exists delivery_address text,
  add column if not exists client_name text,
  add column if not exists client_email text,
  add column if not exists supplier_comment text,
  add column if not exists updated_by text,
  add column if not exists updated_at timestamptz default now(),
  add column if not exists receipt_image_url text,
  add column if not exists receipt_uploaded_at timestamptz;

update public.client_orders co
set client_name = p.full_name,
    client_email = p.email
from public.profiles p
where co.client_id = p.id
  and (co.client_name is null or co.client_email is null);

-- Normalize old statuses to the new state model.
update public.client_orders set status = 'Скорректирован' where status = 'Изменён';
update public.client_orders set status = 'В работе' where status in ('Подтверждён', 'Принят');
update public.client_orders set status = 'В истории' where status = 'Завершён';
update public.client_orders set status = 'Новый' where status = 'Черновик';

alter table public.client_orders
  drop constraint if exists client_orders_status_workflow_check;

alter table public.client_orders
  add constraint client_orders_status_workflow_check
  check (status in ('Новый','Скорректирован','В работе','Отгружен','В истории','Отменён'));

-- Enforce supplier limitation: only reduce quantity vs originally requested quantity.
create or replace function public.client_orders_validate_supplier_quantity()
returns trigger
language plpgsql
as $$
declare
  idx integer;
  new_item jsonb;
  old_item jsonb;
  new_boxes numeric;
  old_requested numeric;
begin
  if new.updated_by <> 'supplier' then
    return new;
  end if;

  for idx in 0..coalesce(jsonb_array_length(new.items),0)-1 loop
    new_item := new.items -> idx;
    old_item := coalesce(old.items -> idx, new_item);
    new_boxes := coalesce((new_item->>'boxes')::numeric, 0);
    old_requested := coalesce((old_item->>'requestedBoxes')::numeric, (old_item->>'boxes')::numeric, new_boxes);

    if new_boxes > old_requested then
      raise exception 'Supplier cannot increase quantity above requested amount (idx=%).', idx;
    end if;
  end loop;

  return new;
end
$$;

drop trigger if exists trg_client_orders_validate_supplier_quantity on public.client_orders;
create trigger trg_client_orders_validate_supplier_quantity
before update on public.client_orders
for each row
execute function public.client_orders_validate_supplier_quantity();
