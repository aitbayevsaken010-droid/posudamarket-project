(function initPosudamartDomainConstants() {
  if (window.PM_ENUMS) return;

  const ROLES = Object.freeze({
    ADMIN: 'admin',
    SUPPLIER: 'supplier',
    WHOLESALER: 'wholesaler',
    CUSTOMER: 'customer',
    CLIENT: 'client', // backward compatibility with legacy client pages
  });

  const USER_STATUSES = Object.freeze({
    ACTIVE: 'active',
    INACTIVE: 'inactive',
    BLOCKED: 'blocked',
  });

  const APPROVAL_STATUSES = Object.freeze({
    NOT_REQUIRED: 'not_required',
    PENDING: 'pending',
    APPROVED: 'approved',
    REJECTED: 'rejected',
  });

  const CUSTOMER_ORDER_STATUSES = Object.freeze({
    NEW: 'new',
    CONFIRMED: 'confirmed',
    PROCESSING: 'processing',
    READY_FOR_PICKUP: 'ready_for_pickup',
    SHIPPED: 'shipped',
    CANCELLED: 'cancelled',
    COMPLETED: 'completed',
  });

  const SUPPLIER_ORDER_STATUSES = Object.freeze({
    NEW: 'new',
    ADJUSTED_BY_SUPPLIER: 'adjusted_by_supplier',
    CHANGED_BY_SUPPLIER: 'changed_by_supplier',
    AWAITING_WHOLESALER_CONFIRMATION: 'awaiting_wholesaler_confirmation',
    CONFIRMED: 'confirmed',
    PROCESSING: 'processing',
    SHIPMENT_PROOF_ATTACHED: 'shipment_proof_attached',
    SHIPPED: 'shipped',
    IN_TRANSIT: 'in_transit',
    RECEIVED: 'received',
    CANCELLED: 'cancelled',
    COMPLETED: 'completed',
  });

  const INVENTORY_MOVEMENT_TYPES = Object.freeze({
    RECEIPT_GOOD: 'receipt_good',
    RECEIPT_DEFECT: 'receipt_defect',
    PROCUREMENT_RECEIVED: 'procurement_received',
    DAMAGED_ON_RECEIVING: 'damaged_on_receiving',
    CUSTOMER_SALE: 'customer_sale',
    CUSTOMER_CANCEL_RESTOCK: 'customer_cancel_restock',
    MANUAL_ADJUSTMENT: 'manual_adjustment',
    RETURN_IN: 'return_in',
    RETURN_OUT: 'return_out',
    RESERVATION_HOLD: 'reservation_hold',
    RESERVATION_RELEASE: 'reservation_release',
  });

  const RETURN_STATUSES = Object.freeze({
    REQUESTED: 'requested',
    APPROVED: 'approved',
    REJECTED: 'rejected',
    IN_TRANSIT: 'in_transit',
    RECEIVED: 'received',
    CLOSED: 'closed',
  });

  const REPLENISHMENT_STATUSES = Object.freeze({
    OPEN: 'open',
    PARTIALLY_COVERED: 'partially_covered',
    COVERED: 'covered',
    ARCHIVED: 'archived',
  });

  window.PM_ENUMS = Object.freeze({
    ROLES,
    USER_STATUSES,
    APPROVAL_STATUSES,
    CUSTOMER_ORDER_STATUSES,
    SUPPLIER_ORDER_STATUSES,
    INVENTORY_MOVEMENT_TYPES,
    RETURN_STATUSES,
    REPLENISHMENT_STATUSES,
  });
})();
