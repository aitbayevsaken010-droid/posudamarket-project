(function initProcurementDomain() {
  if (window.PM_PROCUREMENT) return;

  const STATUS_LABELS = Object.freeze({
    new: 'Новый',
    changed_by_supplier: 'Скорректирован поставщиком',
    awaiting_wholesaler_confirmation: 'Ожидает подтверждения оптовика',
    adjusted_by_supplier: 'Скорректирован поставщиком (legacy)',
    confirmed: 'Подтвержден',
    processing: 'В обработке',
    shipment_proof_attached: 'Есть подтверждение отгрузки',
    shipped: 'Отгружен',
    in_transit: 'В пути',
    received: 'Принят',
    completed: 'Завершен (legacy)',
    cancelled: 'Отменен',
  });

  function toInt(v, fallback = 0) {
    const n = Number(v);
    return Number.isFinite(n) ? Math.trunc(n) : fallback;
  }

  function groupCatalogByCategory(items) {
    const buckets = new Map();
    (items || []).forEach((item) => {
      const key = item.categoryId || 'uncategorized';
      if (!buckets.has(key)) {
        buckets.set(key, { categoryId: key, categoryName: item.categoryName || 'Без категории', items: [] });
      }
      buckets.get(key).items.push(item);
    });
    return [...buckets.values()].sort((a, b) => a.categoryName.localeCompare(b.categoryName, 'ru'));
  }

  function orderTotals(order) {
    const items = order?.supplier_order_items || [];
    return items.reduce((acc, item) => {
      const confirmedBoxes = toInt(item.confirmed_boxes, toInt(item.requested_boxes, 0));
      const requestedBoxes = toInt(item.requested_boxes, 0);
      const price = Number(item.price_per_box_snapshot ?? item.box_price ?? 0);
      return {
        requestedBoxes: acc.requestedBoxes + requestedBoxes,
        confirmedBoxes: acc.confirmedBoxes + confirmedBoxes,
        amount: acc.amount + confirmedBoxes * price,
      };
    }, { requestedBoxes: 0, confirmedBoxes: 0, amount: 0 });
  }

  function normalizeOrder(row) {
    const items = (row?.supplier_order_items || []).map((item) => ({
      ...item,
      requested_boxes: toInt(item.requested_boxes, 0),
      confirmed_boxes: toInt(item.confirmed_boxes, toInt(item.requested_boxes, 0)),
      requested_units: toInt(item.requested_units, 0),
      confirmed_units: toInt(item.confirmed_units, 0),
      received_units_total: toInt(item.received_units_total, 0),
      damaged_units_total: toInt(item.damaged_units_total, 0),
      accepted_units_total: toInt(item.accepted_units_total, 0),
      units_per_box_snapshot: toInt(item.units_per_box_snapshot, 1),
      price_per_box_snapshot: Number(item.price_per_box_snapshot ?? item.box_price ?? 0),
    }));

    return { ...row, supplier_order_items: items, totals: orderTotals({ ...row, supplier_order_items: items }) };
  }

  async function loadWholesalerOrders(sb, wholesalerId) {
    const res = await sb
      .from('supplier_orders')
      .select(`
        id,status,order_total,currency,supplier_user_id,wholesaler_id,
        supplier_comment,wholesaler_comment,cancellation_reason,
        shipment_attachment,created_at,updated_at,placed_at,
        supplier_order_items(
          id,supplier_product_id,requested_boxes,confirmed_boxes,
          requested_units,confirmed_units,
          received_units_total,damaged_units_total,accepted_units_total,
          article_snapshot,title_snapshot,units_per_box_snapshot,price_per_box_snapshot
        )
      `)
      .eq('wholesaler_id', wholesalerId)
      .order('created_at', { ascending: false });
    if (res.error) throw new Error(res.error.message);
    return (res.data || []).map(normalizeOrder);
  }

  async function loadSupplierOrders(sb, supplierUserId) {
    const res = await sb
      .from('supplier_orders')
      .select(`
        id,status,order_total,currency,supplier_user_id,wholesaler_id,
        supplier_comment,wholesaler_comment,cancellation_reason,
        shipment_attachment,created_at,updated_at,placed_at,
        wholesaler:wholesalers!supplier_orders_wholesaler_id_fkey(id,display_name,legal_name),
        supplier_order_items(
          id,supplier_product_id,requested_boxes,confirmed_boxes,
          requested_units,confirmed_units,
          received_units_total,damaged_units_total,accepted_units_total,
          article_snapshot,title_snapshot,units_per_box_snapshot,price_per_box_snapshot
        )
      `)
      .eq('supplier_user_id', supplierUserId)
      .order('created_at', { ascending: false });
    if (res.error) throw new Error(res.error.message);
    return (res.data || []).map(normalizeOrder);
  }

  async function submitCart(sb, cartItems) {
    const payload = (cartItems || []).map((item) => ({
      supplier_product_id: item.supplier_product_id,
      requested_boxes: toInt(item.requested_boxes, 0),
    }));
    const res = await sb.rpc('pm_submit_procurement_cart', { p_items: payload });
    if (res.error) throw new Error(res.error.message);
    return res.data || [];
  }

  window.PM_PROCUREMENT = Object.freeze({
    STATUS_LABELS,
    toInt,
    groupCatalogByCategory,
    orderTotals,
    normalizeOrder,
    loadWholesalerOrders,
    loadSupplierOrders,
    submitCart,
  });
})();
