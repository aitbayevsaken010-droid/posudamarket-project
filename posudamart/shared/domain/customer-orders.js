(function initPosudamartCustomerOrdersDomain() {
  if (window.PM_CUSTOMER_ORDERS) return;

  const STATUS_LABELS = Object.freeze({
    new: 'Новый',
    confirmed: 'Подтверждён',
    processing: 'В обработке',
    ready_for_pickup: 'Готов к выдаче',
    shipped: 'Отгружен',
    cancelled: 'Отменён',
    completed: 'Завершён',
  });

  const ACTIVE_STATUSES = Object.freeze(['new', 'confirmed', 'processing', 'ready_for_pickup', 'shipped']);

  function statusLabel(status) {
    return STATUS_LABELS[String(status || '').toLowerCase()] || String(status || '—');
  }

  function statusBadge(status) {
    const s = String(status || '').toLowerCase();
    const label = statusLabel(s);
    if (s === 'cancelled') return `<span class="badge badge-cancelled">${label}</span>`;
    if (s === 'completed' || s === 'confirmed' || s === 'processing' || s === 'ready_for_pickup' || s === 'shipped') {
      return `<span class="badge badge-confirmed">${label}</span>`;
    }
    return `<span class="badge badge-new">${label}</span>`;
  }

  function formatOrderNumber(orderOrId) {
    if (orderOrId && typeof orderOrId === 'object') {
      const explicitOrderNo = String(orderOrId.order_no || '').trim();
      if (explicitOrderNo) return explicitOrderNo;
      return formatOrderNumber(orderOrId.id);
    }
    const raw = String(orderOrId || '').replace(/-/g, '');
    return raw ? `CO-${raw.slice(0, 8).toUpperCase()}` : '—';
  }

  async function runQueryVariants(queries) {
    let lastError = null;
    for (const query of queries) {
      const res = await query();
      if (!res.error) return res;
      lastError = res.error;
    }
    throw lastError;
  }

  function normalizeOrder(order) {
    if (!order) return null;
    return {
      ...order,
      order_no: String(order.order_no || '').trim(),
      customer_user_id: order.customer_user_id || order.customer_id || null,
      total_amount: Number(order.total_amount ?? order.total ?? 0),
    };
  }

  function normalizeOrderItem(item) {
    if (!item) return null;
    const catalog = item.catalog_products || {};
    return {
      ...item,
      quantity: Number(item.quantity || 0),
      unit_price: Number(item.unit_price || 0),
      line_total: Number(item.line_total ?? (Number(item.quantity || 0) * Number(item.unit_price || 0))),
      title: item.title_snapshot || catalog.name || '—',
      article: item.article_snapshot || catalog.article || '—',
    };
  }

  async function getOpenCart(sb, customerUserId) {
    const res = await sb
      .from('customer_carts')
      .select(`
        id, status, wholesaler_id, created_at, updated_at,
        customer_cart_items(
          id, quantity, inventory_item_id,
          wholesaler_inventory_items(
            id, available_qty, unit_sale_price,
            catalog_products(id, name, article, catalog_product_images(image_url, sort_order))
          )
        )
      `)
      .eq('customer_user_id', customerUserId)
      .eq('status', 'open')
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (res.error) throw res.error;
    return res.data || null;
  }

  async function checkoutCart(sb, cartId) {
    const res = await sb.rpc('checkout_customer_cart', { p_cart_id: cartId });
    if (res.error) throw res.error;
    if (res.data && typeof res.data === 'object' && res.data.order_id) return res.data.order_id;
    return res.data;
  }

  async function cancelOrder(sb, orderId) {
    const res = await sb.rpc('cancel_customer_order', { p_order_id: orderId });
    if (res.error) throw res.error;
    return res.data;
  }

  async function completeOrder(sb, orderId) {
    const res = await sb.rpc('complete_customer_order', { p_order_id: orderId });
    if (res.error) throw res.error;
    return res.data;
  }

  async function loadCustomerOrders(sb, customerUserId) {
    const res = await runQueryVariants([
      () => sb
        .from('customer_orders')
        .select('id, order_no, wholesaler_id, customer_user_id, status, total_amount, created_at, updated_at, cancellation_reason')
        .eq('customer_user_id', customerUserId)
        .order('created_at', { ascending: false }),
      () => sb
        .from('customer_orders')
        .select('id, wholesaler_id, customer_id, status, total, created_at')
        .eq('customer_id', customerUserId)
        .order('created_at', { ascending: false }),
    ]);

    return (res.data || []).map(normalizeOrder).filter(Boolean);
  }

  async function loadWholesalerOrders(sb, wholesalerId) {
    const res = await runQueryVariants([
      () => sb
        .from('customer_orders')
        .select('id, order_no, customer_user_id, wholesaler_id, status, total_amount, created_at, updated_at, cancellation_reason')
        .eq('wholesaler_id', wholesalerId)
        .order('created_at', { ascending: false }),
      () => sb
        .from('customer_orders')
        .select('id, customer_id, wholesaler_id, status, total, created_at')
        .eq('wholesaler_id', wholesalerId)
        .order('created_at', { ascending: false }),
    ]);

    return (res.data || []).map(normalizeOrder).filter(Boolean);
  }

  async function loadOrderItems(sb, orderIds) {
    if (Array.isArray(orderIds) && !orderIds.length) {
      return [];
    }

    const queries = [
      async () => {
        let query = sb
          .from('customer_order_items')
          .select('id, order_id, product_id, inventory_item_id, quantity, unit_price, line_total, title_snapshot, article_snapshot, catalog_products(name, article)')
          .order('created_at', { ascending: false });
        if (Array.isArray(orderIds) && orderIds.length) query = query.in('order_id', orderIds);
        return query;
      },
      async () => {
        let query = sb
          .from('customer_order_items')
          .select('id, order_id, product_id, quantity, unit_price, catalog_products(name, article)')
          .order('created_at', { ascending: false });
        if (Array.isArray(orderIds) && orderIds.length) query = query.in('order_id', orderIds);
        return query;
      },
      async () => {
        let query = sb
          .from('customer_order_items')
          .select('id, order_id, product_id, quantity, unit_price')
          .order('created_at', { ascending: false });
        if (Array.isArray(orderIds) && orderIds.length) query = query.in('order_id', orderIds);
        return query;
      },
    ];

    const res = await runQueryVariants(queries);
    return (res.data || []).map(normalizeOrderItem).filter(Boolean);
  }

  window.PM_CUSTOMER_ORDERS = Object.freeze({
    STATUS_LABELS,
    ACTIVE_STATUSES,
    statusLabel,
    statusBadge,
    formatOrderNumber,
    getOpenCart,
    checkoutCart,
    cancelOrder,
    completeOrder,
    loadCustomerOrders,
    loadWholesalerOrders,
    loadOrderItems,
  });
})();
