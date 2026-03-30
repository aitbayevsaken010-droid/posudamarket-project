(function initPosudamartAccessControl() {
  if (window.PM_ACCESS) return;

  const { PM_ENUMS } = window;
  if (!PM_ENUMS) {
    throw new Error('PM_ENUMS is required before access-control.js');
  }

  const roleAliases = new Map([
    [PM_ENUMS.ROLES.CLIENT, PM_ENUMS.ROLES.CUSTOMER],
  ]);

  function normalizeRole(role) {
    const value = String(role || '').trim().toLowerCase();
    if (!value) return '';
    return roleAliases.get(value) || value;
  }

  function requiresManualApproval(role) {
    const normalized = normalizeRole(role);
    return normalized === PM_ENUMS.ROLES.SUPPLIER || normalized === PM_ENUMS.ROLES.WHOLESALER;
  }

  async function getApprovalStatus(sb, userId, role) {
    const normalizedRole = normalizeRole(role);
    if (!requiresManualApproval(normalizedRole)) {
      return PM_ENUMS.APPROVAL_STATUSES.NOT_REQUIRED;
    }

    const approvalRes = await sb
      .from('role_approvals')
      .select('status')
      .eq('user_id', userId)
      .eq('requested_role', normalizedRole)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!approvalRes.error && approvalRes.data?.status) {
      return approvalRes.data.status;
    }

    // Backward compatibility for legacy supplier flow.
    if (normalizedRole === PM_ENUMS.ROLES.SUPPLIER) {
      const supplierRes = await sb
        .from('suppliers')
        .select('status')
        .eq('user_id', userId)
        .maybeSingle();

      if (!supplierRes.error && supplierRes.data?.status) {
        const status = String(supplierRes.data.status || '').toLowerCase();
        if (status === 'active') return PM_ENUMS.APPROVAL_STATUSES.APPROVED;
        if (status === 'rejected') return PM_ENUMS.APPROVAL_STATUSES.REJECTED;
      }
    }

    return PM_ENUMS.APPROVAL_STATUSES.PENDING;
  }

  async function loadAccessContext(sb) {
    const sessionRes = await sb.auth.getSession();
    const session = sessionRes?.data?.session;
    if (!session) return null;

    const profileRes = await sb
      .from('profiles')
      .select('id, role, account_status')
      .eq('id', session.user.id)
      .single();

    if (profileRes.error || !profileRes.data) {
      throw new Error(profileRes.error?.message || 'Профиль пользователя не найден.');
    }

    const normalizedRole = normalizeRole(profileRes.data.role);
    const approvalStatus = await getApprovalStatus(sb, session.user.id, normalizedRole);

    return {
      user: session.user,
      profile: profileRes.data,
      role: normalizedRole,
      approvalStatus,
      isApproved: approvalStatus === PM_ENUMS.APPROVAL_STATUSES.APPROVED || approvalStatus === PM_ENUMS.APPROVAL_STATUSES.NOT_REQUIRED,
    };
  }

  function hasRouteAccess(context, allowedRoles) {
    if (!context) return false;
    const roleSet = new Set((allowedRoles || []).map(normalizeRole));
    return roleSet.has(context.role);
  }

  function canEnterBusinessSection(context) {
    if (!context) return false;
    if (!requiresManualApproval(context.role)) return true;
    return context.isApproved;
  }

  window.PM_ACCESS = Object.freeze({
    normalizeRole,
    requiresManualApproval,
    getApprovalStatus,
    loadAccessContext,
    hasRouteAccess,
    canEnterBusinessSection,
  });
})();
