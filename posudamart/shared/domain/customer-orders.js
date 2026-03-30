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

  function formatOrderNumber(orderId) {
    const raw = String(orderId || '').replace(/-/g, '');
    return raw ? `CO-${raw.slice(0, 8).toUpperCase()}` : '—';
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

  window.PM_CUSTOMER_ORDERS = Object.freeze({
    STATUS_LABELS,
    ACTIVE_STATUSES,
    statusLabel,
    statusBadge,
    formatOrderNumber,
    getOpenCart,
  });
})();
