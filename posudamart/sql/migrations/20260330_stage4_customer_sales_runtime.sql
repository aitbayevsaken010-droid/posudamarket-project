-- Stage 4: customer sales runtime (cart -> reservation -> order lifecycle -> demand events)

create extension if not exists pgcrypto;

do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'customer_order_status' and e.enumlabel = 'processing'
  ) then
    alter type public.customer_order_status add value 'processing';
  end if;

  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'customer_order_status' and e.enumlabel = 'ready_for_pickup'
  ) then
    alter type public.customer_order_status add value 'ready_for_pickup';
  end if;
end $$;

create table if not exists public.customer_carts (
  id uuid primary key default gen_random_uuid(),
  customer_user_id uuid not null references auth.users(id) on delete cascade,
  wholesaler_id uuid references public.wholesalers(id) on delete set null,
  status text not null default 'open' check (status in ('open', 'checked_out', 'cancelled')),
  checked_out_order_id uuid references public.customer_orders(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_customer_carts_open_per_customer
  on public.customer_carts(customer_user_id)
  where status = 'open';

create table if not exists public.customer_cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.customer_carts(id) on delete cascade,
  inventory_item_id uuid not null references public.wholesaler_inventory_items(id) on delete cascade,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (cart_id, inventory_item_id)
);

create table if not exists public.customer_order_status_history (
  id uuid primary key default gen_random_uuid(),
  customer_order_id uuid not null references public.customer_orders(id) on delete cascade,
  status public.customer_order_status not null,
  actor_user_id uuid references auth.users(id),
  note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.stock_reservations (
  id uuid primary key default gen_random_uuid(),
  customer_order_id uuid not null references public.customer_orders(id) on delete cascade,
  customer_order_item_id uuid not null references public.customer_order_items(id) on delete cascade,
  inventory_item_id uuid not null references public.wholesaler_inventory_items(id) on delete cascade,
  reserved_qty integer not null check (reserved_qty > 0),
  released_qty integer not null default 0 check (released_qty >= 0),
  finalized_qty integer not null default 0 check (finalized_qty >= 0),
  status text not null default 'active' check (status in ('active', 'released', 'finalized')),
  held_at timestamptz not null default now(),
  released_at timestamptz,
  finalized_at timestamptz,
  release_reason text,
  finalize_reason text,
  metadata jsonb not null default '{}'::jsonb,
  unique (customer_order_item_id)
);

create index if not exists idx_customer_cart_items_cart on public.customer_cart_items(cart_id);
create index if not exists idx_customer_orders_wholesaler_status on public.customer_orders(wholesaler_id, status, created_at desc);
create index if not exists idx_customer_orders_customer_status on public.customer_orders(customer_user_id, status, created_at desc);
create index if not exists idx_customer_order_status_history_order on public.customer_order_status_history(customer_order_id, created_at desc);
create index if not exists idx_stock_reservations_order on public.stock_reservations(customer_order_id, status);
create index if not exists idx_inventory_movements_source_document on public.inventory_movements(source_document_type, source_document_id, created_at desc);

create or replace function public.pm_require_customer()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Auth required';
  end if;

  v_role := lower(coalesce((select p.role from public.profiles p where p.id = auth.uid()), ''));
  if v_role not in ('customer', 'client') then
    raise exception 'Only customer is allowed';
  end if;

  return auth.uid();
end
$$;

create or replace function public.pm_can_manage_customer_order(
  p_order_id uuid,
  p_actor_user_id uuid,
  p_actor_role text
)
returns boolean
language sql
stable
as $$
  select case
    when p_actor_role = 'admin' then true
    when p_actor_role = 'customer' then exists (
      select 1
      from public.customer_orders co
      where co.id = p_order_id
        and co.customer_user_id = p_actor_user_id
    )
    when p_actor_role = 'wholesaler' then exists (
      select 1
      from public.customer_orders co
      join public.wholesalers w on w.id = co.wholesaler_id
      where co.id = p_order_id
        and w.user_id = p_actor_user_id
    )
    else false
  end
$$;

create or replace function public.pm_customer_cart_get_or_create(p_wholesaler_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_user_id uuid;
  v_cart_id uuid;
begin
  v_customer_user_id := public.pm_require_customer();

  select id into v_cart_id
  from public.customer_carts
  where customer_user_id = v_customer_user_id
    and status = 'open'
  for update;

  if v_cart_id is null then
    insert into public.customer_carts (customer_user_id, wholesaler_id, status)
    values (v_customer_user_id, p_wholesaler_id, 'open')
    returning id into v_cart_id;
  else
    if p_wholesaler_id is not null then
      update public.customer_carts
      set wholesaler_id = coalesce(wholesaler_id, p_wholesaler_id),
          updated_at = now()
      where id = v_cart_id;
    end if;
  end if;

  return v_cart_id;
end
$$;

create or replace function public.pm_customer_cart_upsert_item(
  p_inventory_item_id uuid,
  p_quantity integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_user_id uuid;
  v_cart_id uuid;
  v_inventory record;
  v_current_qty integer;
  v_result_item_id uuid;
begin
  v_customer_user_id := public.pm_require_customer();

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be > 0';
  end if;

  select wii.id, wii.wholesaler_id, wii.available_qty
  into v_inventory
  from public.wholesaler_inventory_items wii
  where wii.id = p_inventory_item_id;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  v_cart_id := public.pm_customer_cart_get_or_create(v_inventory.wholesaler_id);

  if exists (
    select 1
    from public.customer_carts cc
    where cc.id = v_cart_id
      and cc.wholesaler_id is not null
      and cc.wholesaler_id <> v_inventory.wholesaler_id
  ) then
    raise exception 'Cart can contain items from one wholesaler only';
  end if;

  select cci.quantity into v_current_qty
  from public.customer_cart_items cci
  where cci.cart_id = v_cart_id
    and cci.inventory_item_id = p_inventory_item_id;

  if coalesce(v_current_qty, 0) + p_quantity > v_inventory.available_qty then
    raise exception 'Requested quantity exceeds available inventory';
  end if;

  insert into public.customer_cart_items (cart_id, inventory_item_id, quantity)
  values (v_cart_id, p_inventory_item_id, p_quantity)
  on conflict (cart_id, inventory_item_id)
  do update set
    quantity = public.customer_cart_items.quantity + excluded.quantity,
    updated_at = now()
  returning id into v_result_item_id;

  update public.customer_carts set updated_at = now() where id = v_cart_id;

  return v_result_item_id;
end
$$;

create or replace function public.pm_customer_cart_set_item_quantity(
  p_inventory_item_id uuid,
  p_quantity integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_user_id uuid;
  v_cart_id uuid;
  v_available integer;
begin
  v_customer_user_id := public.pm_require_customer();

  select cc.id into v_cart_id
  from public.customer_carts cc
  where cc.customer_user_id = v_customer_user_id
    and cc.status = 'open';

  if v_cart_id is null then
    raise exception 'Open cart not found';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    delete from public.customer_cart_items
    where cart_id = v_cart_id and inventory_item_id = p_inventory_item_id;
    update public.customer_carts set updated_at = now() where id = v_cart_id;
    return;
  end if;

  select wii.available_qty into v_available
  from public.wholesaler_inventory_items wii
  where wii.id = p_inventory_item_id;

  if v_available is null then
    raise exception 'Inventory item not found';
  end if;

  if p_quantity > v_available then
    raise exception 'Requested quantity exceeds available inventory';
  end if;

  update public.customer_cart_items
  set quantity = p_quantity,
      updated_at = now()
  where cart_id = v_cart_id
    and inventory_item_id = p_inventory_item_id;

  update public.customer_carts set updated_at = now() where id = v_cart_id;
end
$$;

create or replace function public.pm_customer_cart_remove_item(p_inventory_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_user_id uuid;
  v_cart_id uuid;
begin
  v_customer_user_id := public.pm_require_customer();

  select cc.id into v_cart_id
  from public.customer_carts cc
  where cc.customer_user_id = v_customer_user_id
    and cc.status = 'open';

  if v_cart_id is null then
    return;
  end if;

  delete from public.customer_cart_items
  where cart_id = v_cart_id and inventory_item_id = p_inventory_item_id;

  update public.customer_carts set updated_at = now() where id = v_cart_id;
end
$$;

create or replace function public.pm_checkout_customer_cart()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_user_id uuid;
  v_cart record;
  v_order_id uuid;
  v_item record;
  v_inventory record;
  v_order_item_id uuid;
  v_total numeric(14,2) := 0;
begin
  v_customer_user_id := public.pm_require_customer();

  select * into v_cart
  from public.customer_carts cc
  where cc.customer_user_id = v_customer_user_id
    and cc.status = 'open'
  for update;

  if not found then
    raise exception 'Open cart not found';
  end if;

  if v_cart.wholesaler_id is null then
    raise exception 'Cart wholesaler is not defined';
  end if;

  if not exists (select 1 from public.customer_cart_items cci where cci.cart_id = v_cart.id) then
    raise exception 'Cart is empty';
  end if;

  for v_item in
    select cci.id, cci.inventory_item_id, cci.quantity
    from public.customer_cart_items cci
    where cci.cart_id = v_cart.id
  loop
    select wii.*, cp.article, cp.name
    into v_inventory
    from public.wholesaler_inventory_items wii
    join public.catalog_products cp on cp.id = wii.product_id
    where wii.id = v_item.inventory_item_id
    for update;

    if not found then
      raise exception 'Inventory item not found in cart';
    end if;

    if v_inventory.wholesaler_id <> v_cart.wholesaler_id then
      raise exception 'Cart contains inventory from another wholesaler';
    end if;

    if v_item.quantity <= 0 then
      raise exception 'Invalid cart quantity';
    end if;

    if v_inventory.available_qty < v_item.quantity then
      raise exception 'Not enough stock for % (%). Available %, requested %', v_inventory.name, v_inventory.article, v_inventory.available_qty, v_item.quantity;
    end if;

    if v_inventory.unit_sale_price is null then
      raise exception 'Unit sale price is required for checkout';
    end if;
  end loop;

  insert into public.customer_orders (
    wholesaler_id,
    customer_user_id,
    status,
    total_amount,
    currency,
    placed_at,
    created_at,
    updated_at
  )
  values (
    v_cart.wholesaler_id,
    v_customer_user_id,
    'new',
    0,
    'KZT',
    now(),
    now(),
    now()
  )
  returning id into v_order_id;

  for v_item in
    select cci.id, cci.inventory_item_id, cci.quantity
    from public.customer_cart_items cci
    where cci.cart_id = v_cart.id
  loop
    select wii.* into v_inventory
    from public.wholesaler_inventory_items wii
    where wii.id = v_item.inventory_item_id
    for update;

    insert into public.customer_order_items (
      order_id,
      inventory_item_id,
      product_id,
      variant_id,
      quantity,
      unit_price,
      created_at
    )
    values (
      v_order_id,
      v_inventory.id,
      v_inventory.product_id,
      v_inventory.variant_id,
      v_item.quantity,
      v_inventory.unit_sale_price,
      now()
    )
    returning id into v_order_item_id;

    update public.wholesaler_inventory_items
    set available_qty = available_qty - v_item.quantity,
        reserved_qty = reserved_qty + v_item.quantity,
        updated_at = now()
    where id = v_inventory.id;

    insert into public.stock_reservations (
      customer_order_id,
      customer_order_item_id,
      inventory_item_id,
      reserved_qty,
      status,
      held_at,
      metadata
    )
    values (
      v_order_id,
      v_order_item_id,
      v_inventory.id,
      v_item.quantity,
      'active',
      now(),
      jsonb_build_object('cart_id', v_cart.id)
    );

    insert into public.inventory_movements (
      inventory_item_id,
      movement_type,
      quantity,
      reason,
      source_document_type,
      source_document_id,
      actor_user_id,
      metadata
    )
    values (
      v_inventory.id,
      'reservation_hold',
      v_item.quantity,
      'Customer order reservation hold',
      'customer_order',
      v_order_id,
      auth.uid(),
      jsonb_build_object('customer_order_item_id', v_order_item_id)
    );

    v_total := v_total + (v_item.quantity * v_inventory.unit_sale_price);
  end loop;

  update public.customer_orders
  set total_amount = v_total,
      updated_at = now()
  where id = v_order_id;

  insert into public.customer_order_status_history (customer_order_id, status, actor_user_id, note, metadata)
  values (v_order_id, 'new', auth.uid(), 'Order created from customer cart', jsonb_build_object('cart_id', v_cart.id));

  update public.customer_carts
  set status = 'checked_out',
      checked_out_order_id = v_order_id,
      updated_at = now()
  where id = v_cart.id;

  return v_order_id;
end
$$;

create or replace function public.pm_customer_order_transition_allowed(
  p_current_status public.customer_order_status,
  p_target_status public.customer_order_status,
  p_actor_role text
)
returns boolean
language plpgsql
stable
as $$
begin
  if p_current_status in ('cancelled', 'completed') then
    return false;
  end if;

  if p_target_status = p_current_status then
    return true;
  end if;

  if p_target_status = 'cancelled' then
    if p_actor_role = 'customer' then
      return p_current_status in ('new', 'confirmed');
    end if;
    return p_actor_role in ('wholesaler', 'admin') and p_current_status in ('new', 'confirmed', 'processing', 'ready_for_pickup', 'shipped');
  end if;

  if p_actor_role not in ('wholesaler', 'admin') then
    return false;
  end if;

  if p_current_status = 'new' and p_target_status in ('confirmed', 'processing') then
    return true;
  end if;

  if p_current_status = 'confirmed' and p_target_status in ('processing', 'ready_for_pickup', 'shipped') then
    return true;
  end if;

  if p_current_status = 'processing' and p_target_status in ('ready_for_pickup', 'shipped') then
    return true;
  end if;

  if p_current_status in ('ready_for_pickup', 'shipped') and p_target_status = 'completed' then
    return true;
  end if;

  return false;
end
$$;

create or replace function public.pm_estimate_units_per_box(
  p_product_id uuid,
  p_variant_id uuid
)
returns integer
language sql
stable
as $$
  select greatest(
    coalesce(
      (
        select sp.pieces_per_box
        from public.supplier_products sp
        where sp.product_id = p_product_id
          and coalesce(sp.variant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_variant_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and sp.is_active = true
        order by sp.updated_at desc nulls last, sp.created_at desc
        limit 1
      ),
      1
    ),
    1
  )
$$;

create or replace function public.pm_customer_order_apply_cancellation(
  p_order_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res record;
begin
  for v_res in
    select sr.id, sr.inventory_item_id, sr.reserved_qty
    from public.stock_reservations sr
    where sr.customer_order_id = p_order_id
      and sr.status = 'active'
    for update
  loop
    update public.wholesaler_inventory_items
    set available_qty = available_qty + v_res.reserved_qty,
        reserved_qty = reserved_qty - v_res.reserved_qty,
        updated_at = now()
    where id = v_res.inventory_item_id
      and reserved_qty >= v_res.reserved_qty;

    if not found then
      raise exception 'Inventory reservation release failed due to insufficient reserved_qty';
    end if;

    update public.stock_reservations
    set status = 'released',
        released_qty = reserved_qty,
        released_at = now(),
        release_reason = coalesce(p_reason, 'order_cancelled')
    where id = v_res.id;

    insert into public.inventory_movements (
      inventory_item_id,
      movement_type,
      quantity,
      reason,
      source_document_type,
      source_document_id,
      actor_user_id,
      metadata
    )
    values (
      v_res.inventory_item_id,
      'reservation_release',
      v_res.reserved_qty,
      'Customer order reservation released',
      'customer_order',
      p_order_id,
      auth.uid(),
      jsonb_build_object('stock_reservation_id', v_res.id)
    );
  end loop;

  update public.customer_orders
  set cancelled_at = now(),
      cancellation_reason = coalesce(p_reason, cancellation_reason),
      updated_at = now()
  where id = p_order_id;
end
$$;

create or replace function public.pm_customer_order_apply_completion(
  p_order_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res record;
  v_item record;
  v_demand_id uuid;
  v_units_per_box integer;
  v_sold_qty integer;
  v_sales_count integer;
  v_uncovered_qty integer;
  v_suggested_boxes integer;
  v_suggested_qty integer;
begin
  for v_res in
    select sr.id, sr.inventory_item_id, sr.customer_order_item_id, sr.reserved_qty
    from public.stock_reservations sr
    where sr.customer_order_id = p_order_id
      and sr.status = 'active'
    for update
  loop
    update public.wholesaler_inventory_items
    set reserved_qty = reserved_qty - v_res.reserved_qty,
        on_hand_qty = on_hand_qty - v_res.reserved_qty,
        updated_at = now()
    where id = v_res.inventory_item_id
      and reserved_qty >= v_res.reserved_qty
      and on_hand_qty >= v_res.reserved_qty;

    if not found then
      raise exception 'Inventory sale finalization failed due to insufficient reserved/on_hand';
    end if;

    update public.stock_reservations
    set status = 'finalized',
        finalized_qty = reserved_qty,
        finalized_at = now(),
        finalize_reason = coalesce(p_reason, 'order_completed')
    where id = v_res.id;

    insert into public.inventory_movements (
      inventory_item_id,
      movement_type,
      quantity,
      reason,
      source_document_type,
      source_document_id,
      actor_user_id,
      metadata
    )
    values (
      v_res.inventory_item_id,
      'customer_sale',
      v_res.reserved_qty,
      'Customer sale finalized from reservation',
      'customer_order',
      p_order_id,
      auth.uid(),
      jsonb_build_object('stock_reservation_id', v_res.id, 'customer_order_item_id', v_res.customer_order_item_id)
    );

    select coi.order_id, coi.product_id, coi.variant_id, coi.quantity, co.wholesaler_id
    into v_item
    from public.customer_order_items coi
    join public.customer_orders co on co.id = coi.order_id
    where coi.id = v_res.customer_order_item_id;

    v_units_per_box := public.pm_estimate_units_per_box(v_item.product_id, v_item.variant_id);

    select rd.id into v_demand_id
    from public.replenishment_demands rd
    where rd.wholesaler_id = v_item.wholesaler_id
      and rd.product_id = v_item.product_id
      and coalesce(rd.variant_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_item.variant_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and rd.status in ('open', 'partially_covered')
    order by rd.created_at
    limit 1
    for update;

    if v_demand_id is null then
      insert into public.replenishment_demands (
        wholesaler_id,
        product_id,
        variant_id,
        sold_qty,
        sales_count,
        uncovered_qty,
        pieces_per_box,
        suggested_boxes,
        suggested_qty,
        status,
        activated_at,
        metadata,
        created_at,
        updated_at
      )
      values (
        v_item.wholesaler_id,
        v_item.product_id,
        v_item.variant_id,
        0,
        0,
        0,
        v_units_per_box,
        0,
        0,
        'open',
        now(),
        '{}'::jsonb,
        now(),
        now()
      )
      returning id into v_demand_id;

      insert into public.replenishment_demand_events (
        demand_id,
        event_type,
        quantity_delta,
        source_customer_order_item_id,
        metadata,
        created_at
      )
      values (
        v_demand_id,
        'demand_opened',
        0,
        v_res.customer_order_item_id,
        jsonb_build_object('customer_order_id', p_order_id),
        now()
      );
    end if;

    update public.replenishment_demands
    set sold_qty = sold_qty + v_res.reserved_qty,
        sales_count = sales_count + 1,
        uncovered_qty = uncovered_qty + v_res.reserved_qty,
        pieces_per_box = greatest(coalesce(pieces_per_box, 1), 1),
        updated_at = now(),
        activated_at = coalesce(activated_at, now())
    where id = v_demand_id
    returning sold_qty, sales_count, uncovered_qty into v_sold_qty, v_sales_count, v_uncovered_qty;

    v_suggested_boxes := case
      when v_units_per_box <= 0 then 0
      when v_uncovered_qty <= 0 then 0
      else ceil(v_uncovered_qty::numeric / v_units_per_box::numeric)::integer
    end;
    v_suggested_qty := v_suggested_boxes * greatest(v_units_per_box, 1);

    update public.replenishment_demands
    set pieces_per_box = v_units_per_box,
        suggested_boxes = v_suggested_boxes,
        suggested_qty = v_suggested_qty,
        status = case when uncovered_qty <= 0 then 'covered' else status end,
        covered_at = case when uncovered_qty <= 0 then now() else covered_at end,
        metadata = jsonb_set(
          jsonb_set(coalesce(metadata, '{}'::jsonb), '{last_sale_order_id}', to_jsonb(p_order_id::text), true),
          '{last_sale_at}',
          to_jsonb(now()::text),
          true
        ),
        updated_at = now()
    where id = v_demand_id;

    insert into public.replenishment_demand_events (
      demand_id,
      event_type,
      quantity_delta,
      source_customer_order_item_id,
      metadata,
      created_at
    )
    values (
      v_demand_id,
      'sale_finalized',
      v_res.reserved_qty,
      v_res.customer_order_item_id,
      jsonb_build_object(
        'customer_order_id',
        p_order_id,
        'uncovered_qty_after',
        v_uncovered_qty,
        'suggested_boxes_after',
        v_suggested_boxes,
        'suggested_qty_after',
        v_suggested_qty,
        'sales_count_after',
        v_sales_count,
        'sold_qty_after',
        v_sold_qty
      ),
      now()
    );
  end loop;
end
$$;

create or replace function public.pm_set_customer_order_status(
  p_order_id uuid,
  p_status public.customer_order_status,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_actor_role text;
begin
  if auth.uid() is null then
    raise exception 'Auth required';
  end if;

  select co.*, w.user_id as wholesaler_user_id
  into v_order
  from public.customer_orders co
  join public.wholesalers w on w.id = co.wholesaler_id
  where co.id = p_order_id
  for update;

  if not found then
    raise exception 'Customer order not found';
  end if;

  v_actor_role := lower(coalesce((select p.role from public.profiles p where p.id = auth.uid()), ''));
  if v_actor_role = 'client' then
    v_actor_role := 'customer';
  end if;

  if not public.pm_can_manage_customer_order(p_order_id, auth.uid(), v_actor_role) then
    raise exception 'Access denied to manage this order';
  end if;

  if not public.pm_customer_order_transition_allowed(v_order.status, p_status, v_actor_role) then
    raise exception 'Transition from % to % is not allowed for role %', v_order.status, p_status, v_actor_role;
  end if;

  if v_order.status = p_status then
    insert into public.customer_order_status_history(customer_order_id, status, actor_user_id, note, metadata)
    values (p_order_id, p_status, auth.uid(), coalesce(p_note, 'status repeated'), jsonb_build_object('idempotent', true));
    return;
  end if;

  if p_status = 'cancelled' then
    perform public.pm_customer_order_apply_cancellation(p_order_id, p_note);
  elsif p_status = 'completed' then
    if v_order.status = 'cancelled' then
      raise exception 'Cancelled order cannot be completed';
    end if;
    perform public.pm_customer_order_apply_completion(p_order_id, p_note);
  end if;

  update public.customer_orders
  set status = p_status,
      updated_at = now(),
      cancelled_at = case when p_status = 'cancelled' then coalesce(cancelled_at, now()) else cancelled_at end,
      cancellation_reason = case when p_status = 'cancelled' then coalesce(nullif(trim(coalesce(p_note, '')), ''), cancellation_reason) else cancellation_reason end
  where id = p_order_id;

  insert into public.customer_order_status_history (customer_order_id, status, actor_user_id, note, metadata)
  values (
    p_order_id,
    p_status,
    auth.uid(),
    p_note,
    jsonb_build_object('from_status', v_order.status, 'actor_role', v_actor_role)
  );
end
$$;

grant execute on function public.pm_customer_cart_get_or_create(uuid) to authenticated;
grant execute on function public.pm_customer_cart_upsert_item(uuid, integer) to authenticated;
grant execute on function public.pm_customer_cart_set_item_quantity(uuid, integer) to authenticated;
grant execute on function public.pm_customer_cart_remove_item(uuid) to authenticated;
grant execute on function public.pm_checkout_customer_cart() to authenticated;
grant execute on function public.pm_set_customer_order_status(uuid, public.customer_order_status, text) to authenticated;
