-- Stage 3: procurement lifecycle runtime (wholesaler -> supplier -> receiving -> inventory bridge)

create extension if not exists pgcrypto;

-- Enums evolution (non-destructive)
do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'supplier_order_status' and e.enumlabel = 'changed_by_supplier'
  ) then
    alter type public.supplier_order_status add value 'changed_by_supplier';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'supplier_order_status' and e.enumlabel = 'confirmed'
  ) then
    alter type public.supplier_order_status add value 'confirmed';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'supplier_order_status' and e.enumlabel = 'shipped'
  ) then
    alter type public.supplier_order_status add value 'shipped';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'supplier_order_status' and e.enumlabel = 'received'
  ) then
    alter type public.supplier_order_status add value 'received';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'inventory_movement_type' and e.enumlabel = 'procurement_received'
  ) then
    alter type public.inventory_movement_type add value 'procurement_received';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'inventory_movement_type' and e.enumlabel = 'damaged_on_receiving'
  ) then
    alter type public.inventory_movement_type add value 'damaged_on_receiving';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'inventory_movement_type' and e.enumlabel = 'reservation_hold'
  ) then
    alter type public.inventory_movement_type add value 'reservation_hold';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'inventory_movement_type' and e.enumlabel = 'reservation_release'
  ) then
    alter type public.inventory_movement_type add value 'reservation_release';
  end if;
end $$;

alter table if exists public.wholesaler_inventory_items
  add column if not exists on_hand_qty integer not null default 0 check (on_hand_qty >= 0),
  add column if not exists last_received_at timestamptz;

update public.wholesaler_inventory_items
set on_hand_qty = greatest(coalesce(on_hand_qty, 0), coalesce(available_qty, 0) + coalesce(reserved_qty, 0))
where on_hand_qty is null or on_hand_qty < coalesce(available_qty, 0) + coalesce(reserved_qty, 0);

alter table if exists public.supplier_orders
  add column if not exists procurement_cart_id uuid,
  add column if not exists wholesaler_comment text,
  add column if not exists cancellation_reason text,
  add column if not exists confirmed_at timestamptz,
  add column if not exists shipped_at timestamptz,
  add column if not exists received_at timestamptz,
  add column if not exists shipment_attachment jsonb not null default '{}'::jsonb;

alter table if exists public.supplier_order_items
  add column if not exists confirmed_boxes integer check (confirmed_boxes >= 0),
  add column if not exists article_snapshot text,
  add column if not exists title_snapshot text,
  add column if not exists units_per_box_snapshot integer,
  add column if not exists price_per_box_snapshot numeric(14,2),
  add column if not exists requested_units integer,
  add column if not exists confirmed_units integer,
  add column if not exists received_units_total integer not null default 0 check (received_units_total >= 0),
  add column if not exists damaged_units_total integer not null default 0 check (damaged_units_total >= 0),
  add column if not exists accepted_units_total integer not null default 0 check (accepted_units_total >= 0),
  add column if not exists updated_at timestamptz not null default now();

update public.supplier_order_items
set units_per_box_snapshot = coalesce(units_per_box_snapshot, pieces_per_box, 1),
    price_per_box_snapshot = coalesce(price_per_box_snapshot, box_price, 0),
    requested_units = coalesce(requested_units, requested_boxes * coalesce(units_per_box_snapshot, pieces_per_box, 1)),
    confirmed_boxes = coalesce(confirmed_boxes, requested_boxes),
    confirmed_units = coalesce(confirmed_units, coalesce(confirmed_boxes, requested_boxes) * coalesce(units_per_box_snapshot, pieces_per_box, 1))
where units_per_box_snapshot is null
   or price_per_box_snapshot is null
   or requested_units is null
   or confirmed_units is null
   or confirmed_boxes is null;

create table if not exists public.procurement_carts (
  id uuid primary key default gen_random_uuid(),
  wholesaler_id uuid not null references public.wholesalers(id) on delete cascade,
  status text not null default 'open' check (status in ('open', 'submitted', 'cancelled')),
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.procurement_cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.procurement_carts(id) on delete cascade,
  supplier_product_id uuid not null references public.supplier_products(id),
  requested_boxes integer not null check (requested_boxes > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(cart_id, supplier_product_id)
);

create table if not exists public.supplier_order_status_history (
  id uuid primary key default gen_random_uuid(),
  supplier_order_id uuid not null references public.supplier_orders(id) on delete cascade,
  status public.supplier_order_status not null,
  actor_user_id uuid references auth.users(id),
  note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_order_receivings (
  id uuid primary key default gen_random_uuid(),
  supplier_order_id uuid not null references public.supplier_orders(id) on delete cascade,
  wholesaler_id uuid not null references public.wholesalers(id) on delete cascade,
  received_by_user_id uuid not null references auth.users(id),
  receipt_attachment jsonb not null default '{}'::jsonb,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_order_receiving_items (
  id uuid primary key default gen_random_uuid(),
  receiving_id uuid not null references public.supplier_order_receivings(id) on delete cascade,
  supplier_order_item_id uuid not null references public.supplier_order_items(id) on delete cascade,
  expected_boxes integer not null default 0 check (expected_boxes >= 0),
  expected_units integer not null default 0 check (expected_units >= 0),
  received_units integer not null default 0 check (received_units >= 0),
  damaged_units integer not null default 0 check (damaged_units >= 0),
  accepted_units integer not null default 0 check (accepted_units >= 0),
  damaged_attachment jsonb not null default '{}'::jsonb,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.supplier_order_damaged_goods (
  id uuid primary key default gen_random_uuid(),
  receiving_item_id uuid not null references public.supplier_order_receiving_items(id) on delete cascade,
  supplier_order_item_id uuid not null references public.supplier_order_items(id) on delete cascade,
  damaged_units integer not null check (damaged_units > 0),
  attachment jsonb not null default '{}'::jsonb,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_supplier_orders_wholesaler_status on public.supplier_orders(wholesaler_id, status, created_at desc);
create index if not exists idx_supplier_orders_supplier_status on public.supplier_orders(supplier_user_id, status, created_at desc);
create index if not exists idx_supplier_order_items_order on public.supplier_order_items(supplier_order_id);
create index if not exists idx_supplier_order_status_history_order on public.supplier_order_status_history(supplier_order_id, created_at desc);
create index if not exists idx_receivings_order on public.supplier_order_receivings(supplier_order_id, created_at desc);

create or replace function public.pm_current_role()
returns text
language sql
stable
as $$
  select lower(coalesce((select p.role from public.profiles p where p.id = auth.uid()), ''))
$$;

create or replace function public.pm_require_wholesaler()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wholesaler_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Auth required';
  end if;
  if public.pm_current_role() <> 'wholesaler' then
    raise exception 'Only wholesaler is allowed';
  end if;
  select w.id into v_wholesaler_id from public.wholesalers w where w.user_id = auth.uid();
  if v_wholesaler_id is null then
    raise exception 'Wholesaler profile not found';
  end if;
  return v_wholesaler_id;
end
$$;

create or replace function public.pm_require_supplier_for_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_supplier_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Auth required';
  end if;
  if public.pm_current_role() <> 'supplier' then
    raise exception 'Only supplier is allowed';
  end if;

  select so.supplier_user_id into v_supplier_user_id
  from public.supplier_orders so
  where so.id = p_order_id;

  if v_supplier_user_id is null then
    raise exception 'Order not found';
  end if;
  if v_supplier_user_id <> auth.uid() then
    raise exception 'Supplier access denied';
  end if;
end
$$;

create or replace function public.pm_set_order_status(
  p_order_id uuid,
  p_status public.supplier_order_status,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.supplier_orders
  set status = p_status,
      updated_at = now(),
      confirmed_at = case when p_status = 'confirmed' then now() else confirmed_at end,
      shipped_at = case when p_status in ('shipped', 'in_transit') then now() else shipped_at end,
      received_at = case when p_status = 'received' then now() else received_at end
  where id = p_order_id;

  insert into public.supplier_order_status_history (supplier_order_id, status, actor_user_id, note, metadata)
  values (p_order_id, p_status, auth.uid(), p_note, coalesce(p_metadata, '{}'::jsonb));
end
$$;

create or replace function public.pm_submit_procurement_cart(p_items jsonb)
returns table(created_order_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wholesaler_id uuid;
  v_cart_id uuid;
  v_item jsonb;
  v_supplier_product_id uuid;
  v_requested_boxes integer;
  v_supplier_user_id uuid;
  v_order_id uuid;
  v_product record;
begin
  v_wholesaler_id := public.pm_require_wholesaler();

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Cart items are required';
  end if;

  insert into public.procurement_carts (wholesaler_id)
  values (v_wholesaler_id)
  returning id into v_cart_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_supplier_product_id := (v_item->>'supplier_product_id')::uuid;
    v_requested_boxes := coalesce((v_item->>'requested_boxes')::integer, 0);

    if v_supplier_product_id is null then
      raise exception 'supplier_product_id is required';
    end if;
    if v_requested_boxes <= 0 then
      raise exception 'requested_boxes must be > 0';
    end if;

    insert into public.procurement_cart_items (cart_id, supplier_product_id, requested_boxes)
    values (v_cart_id, v_supplier_product_id, v_requested_boxes)
    on conflict (cart_id, supplier_product_id)
    do update set requested_boxes = excluded.requested_boxes, updated_at = now();
  end loop;

  for v_supplier_user_id in
    select distinct sp.supplier_user_id
    from public.procurement_cart_items pci
    join public.supplier_products sp on sp.id = pci.supplier_product_id
    where pci.cart_id = v_cart_id
  loop
    insert into public.supplier_orders (wholesaler_id, supplier_user_id, status, procurement_cart_id, placed_at)
    values (v_wholesaler_id, v_supplier_user_id, 'new', v_cart_id, now())
    returning id into v_order_id;

    for v_product in
      select pci.requested_boxes, sp.id as supplier_product_id, sp.product_id, sp.variant_id,
             cp.article, cp.name as title, sp.units_per_box, sp.price_per_box
      from public.procurement_cart_items pci
      join public.supplier_products sp on sp.id = pci.supplier_product_id
      join public.catalog_products cp on cp.id = sp.product_id
      where pci.cart_id = v_cart_id
        and sp.supplier_user_id = v_supplier_user_id
    loop
      insert into public.supplier_order_items (
        supplier_order_id, supplier_product_id,
        requested_boxes, confirmed_boxes,
        box_price, pieces_per_box,
        article_snapshot, title_snapshot,
        units_per_box_snapshot, price_per_box_snapshot,
        requested_units, confirmed_units,
        updated_at
      )
      values (
        v_order_id, v_product.supplier_product_id,
        v_product.requested_boxes, v_product.requested_boxes,
        v_product.price_per_box, v_product.units_per_box,
        v_product.article, v_product.title,
        v_product.units_per_box, v_product.price_per_box,
        v_product.requested_boxes * v_product.units_per_box,
        v_product.requested_boxes * v_product.units_per_box,
        now()
      );
    end loop;

    update public.supplier_orders so
    set order_total = coalesce((
      select sum(soi.confirmed_boxes * soi.price_per_box_snapshot)::numeric(14,2)
      from public.supplier_order_items soi
      where soi.supplier_order_id = so.id
    ), 0),
    updated_at = now()
    where so.id = v_order_id;

    perform public.pm_set_order_status(v_order_id, 'new', 'Order created from procurement cart', jsonb_build_object('cart_id', v_cart_id));

    created_order_id := v_order_id;
    return next;
  end loop;

  update public.procurement_carts set status = 'submitted', submitted_at = now(), updated_at = now() where id = v_cart_id;
end
$$;

create or replace function public.pm_supplier_adjust_order(
  p_order_id uuid,
  p_items jsonb,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_order_item_id uuid;
  v_confirmed_boxes integer;
  v_requested integer;
  v_units integer;
  v_has_changes boolean := false;
begin
  perform public.pm_require_supplier_for_order(p_order_id);

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Adjusted items payload is required';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_order_item_id := (v_item->>'supplier_order_item_id')::uuid;
    v_confirmed_boxes := coalesce((v_item->>'confirmed_boxes')::integer, -1);

    if v_order_item_id is null then
      raise exception 'supplier_order_item_id is required';
    end if;
    if v_confirmed_boxes < 0 then
      raise exception 'confirmed_boxes cannot be negative';
    end if;

    select requested_boxes, units_per_box_snapshot into v_requested, v_units
    from public.supplier_order_items
    where id = v_order_item_id and supplier_order_id = p_order_id;

    if v_requested is null then
      raise exception 'Order item % not found for order', v_order_item_id;
    end if;

    if v_confirmed_boxes > v_requested then
      raise exception 'Supplier cannot increase boxes above requested';
    end if;

    if v_confirmed_boxes <> v_requested then
      v_has_changes := true;
    end if;

    update public.supplier_order_items
    set confirmed_boxes = v_confirmed_boxes,
        confirmed_units = v_confirmed_boxes * units_per_box_snapshot,
        updated_at = now()
    where id = v_order_item_id;
  end loop;

  update public.supplier_orders so
  set order_total = coalesce((
    select sum(soi.confirmed_boxes * soi.price_per_box_snapshot)::numeric(14,2)
    from public.supplier_order_items soi
    where soi.supplier_order_id = so.id
  ), 0),
  supplier_comment = coalesce(p_note, supplier_comment),
  updated_at = now()
  where so.id = p_order_id;

  if v_has_changes then
    perform public.pm_set_order_status(p_order_id, 'changed_by_supplier', p_note, '{}'::jsonb);
  else
    perform public.pm_set_order_status(p_order_id, 'confirmed', p_note, '{}'::jsonb);
  end if;
end
$$;

create or replace function public.pm_wholesaler_confirm_order(
  p_order_id uuid,
  p_accept boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wholesaler_id uuid;
  v_order_wholesaler_id uuid;
begin
  v_wholesaler_id := public.pm_require_wholesaler();

  select wholesaler_id into v_order_wholesaler_id from public.supplier_orders where id = p_order_id;
  if v_order_wholesaler_id is null then
    raise exception 'Order not found';
  end if;
  if v_order_wholesaler_id <> v_wholesaler_id then
    raise exception 'Wholesaler access denied';
  end if;

  if p_accept then
    perform public.pm_set_order_status(p_order_id, 'confirmed', p_note, '{}'::jsonb);
  else
    update public.supplier_orders set cancellation_reason = coalesce(p_note, cancellation_reason), updated_at = now() where id = p_order_id;
    perform public.pm_set_order_status(p_order_id, 'cancelled', p_note, '{}'::jsonb);
  end if;
end
$$;

create or replace function public.pm_supplier_set_logistics_status(
  p_order_id uuid,
  p_status public.supplier_order_status,
  p_note text default null,
  p_shipment_attachment jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.pm_require_supplier_for_order(p_order_id);

  if p_status not in ('processing', 'shipped', 'in_transit') then
    raise exception 'Unsupported status transition';
  end if;

  if p_shipment_attachment is not null then
    update public.supplier_orders
    set shipment_attachment = p_shipment_attachment,
        updated_at = now()
    where id = p_order_id;
  end if;

  perform public.pm_set_order_status(p_order_id, p_status, p_note, coalesce(p_shipment_attachment, '{}'::jsonb));
end
$$;

create or replace function public.pm_wholesaler_receive_order(
  p_order_id uuid,
  p_items jsonb,
  p_note text default null,
  p_receipt_attachment jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wholesaler_id uuid;
  v_order record;
  v_receiving_id uuid;
  v_item jsonb;
  v_order_item record;
  v_received integer;
  v_damaged integer;
  v_accepted integer;
  v_max_receivable integer;
  v_inventory_item_id uuid;
begin
  v_wholesaler_id := public.pm_require_wholesaler();

  select * into v_order from public.supplier_orders where id = p_order_id;
  if not found then raise exception 'Order not found'; end if;
  if v_order.wholesaler_id <> v_wholesaler_id then raise exception 'Wholesaler access denied'; end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Receiving items are required';
  end if;

  insert into public.supplier_order_receivings (supplier_order_id, wholesaler_id, received_by_user_id, note, receipt_attachment)
  values (p_order_id, v_wholesaler_id, auth.uid(), p_note, coalesce(p_receipt_attachment, '{}'::jsonb))
  returning id into v_receiving_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    select soi.*, sp.product_id, sp.variant_id
    into v_order_item
    from public.supplier_order_items soi
    join public.supplier_products sp on sp.id = soi.supplier_product_id
    where soi.id = (v_item->>'supplier_order_item_id')::uuid
      and soi.supplier_order_id = p_order_id;

    if not found then
      raise exception 'Receiving item references unknown order item';
    end if;

    v_received := coalesce((v_item->>'received_units')::integer, 0);
    v_damaged := coalesce((v_item->>'damaged_units')::integer, 0);

    if v_received < 0 or v_damaged < 0 then
      raise exception 'received_units and damaged_units cannot be negative';
    end if;
    if v_damaged > v_received then
      raise exception 'damaged_units cannot exceed received_units';
    end if;

    v_max_receivable := greatest(coalesce(v_order_item.confirmed_units, 0) - coalesce(v_order_item.received_units_total, 0), 0);
    if v_received > v_max_receivable then
      raise exception 'received_units exceeds remaining confirmed units';
    end if;

    v_accepted := v_received - v_damaged;

    insert into public.supplier_order_receiving_items (
      receiving_id, supplier_order_item_id,
      expected_boxes, expected_units,
      received_units, damaged_units, accepted_units,
      note, damaged_attachment
    )
    values (
      v_receiving_id, v_order_item.id,
      coalesce(v_order_item.confirmed_boxes, 0),
      coalesce(v_order_item.confirmed_units, 0),
      v_received, v_damaged, v_accepted,
      nullif(trim(coalesce(v_item->>'note', '')), ''),
      coalesce((v_item->'damaged_attachment'), '{}'::jsonb)
    );

    update public.supplier_order_items
    set received_units_total = received_units_total + v_received,
        damaged_units_total = damaged_units_total + v_damaged,
        accepted_units_total = accepted_units_total + v_accepted,
        updated_at = now()
    where id = v_order_item.id;

    select id into v_inventory_item_id
    from public.wholesaler_inventory_items wii
    where wii.wholesaler_id = v_wholesaler_id
      and wii.product_id = v_order_item.product_id
      and coalesce(wii.variant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_order_item.variant_id, '00000000-0000-0000-0000-000000000000'::uuid)
    limit 1;

    if v_inventory_item_id is null then
      insert into public.wholesaler_inventory_items (
        wholesaler_id, product_id, variant_id,
        available_qty, on_hand_qty, damaged_qty,
        last_received_at, updated_at
      )
      values (
        v_wholesaler_id, v_order_item.product_id, v_order_item.variant_id,
        0, 0, 0,
        now(), now()
      )
      returning id into v_inventory_item_id;
    end if;

    if v_accepted > 0 then
      update public.wholesaler_inventory_items
      set on_hand_qty = on_hand_qty + v_accepted,
          available_qty = available_qty + v_accepted,
          last_received_at = now(),
          updated_at = now()
      where id = v_inventory_item_id;

      insert into public.inventory_movements (
        inventory_item_id, movement_type, quantity,
        reason, source_document_type, source_document_id, actor_user_id,
        metadata
      )
      values (
        v_inventory_item_id, 'procurement_received', v_accepted,
        'goods accepted on receiving', 'supplier_order_receiving', v_receiving_id, auth.uid(),
        jsonb_build_object('supplier_order_id', p_order_id, 'supplier_order_item_id', v_order_item.id)
      );
    end if;

    if v_damaged > 0 then
      update public.wholesaler_inventory_items
      set damaged_qty = damaged_qty + v_damaged,
          updated_at = now()
      where id = v_inventory_item_id;

      insert into public.inventory_movements (
        inventory_item_id, movement_type, quantity,
        reason, source_document_type, source_document_id, actor_user_id,
        metadata
      )
      values (
        v_inventory_item_id, 'damaged_on_receiving', v_damaged,
        'damaged units detected on receiving', 'supplier_order_receiving', v_receiving_id, auth.uid(),
        jsonb_build_object('supplier_order_id', p_order_id, 'supplier_order_item_id', v_order_item.id)
      );
    end if;
  end loop;

  if exists (
    select 1
    from public.supplier_order_items soi
    where soi.supplier_order_id = p_order_id
      and coalesce(soi.received_units_total, 0) < coalesce(soi.confirmed_units, 0)
  ) then
    null;
  else
    perform public.pm_set_order_status(p_order_id, 'received', p_note, jsonb_build_object('receiving_id', v_receiving_id));
  end if;

  return v_receiving_id;
end
$$;
