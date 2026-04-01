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

  async function getLatestRoleApproval(sb, userId, role) {
    const normalizedRole = normalizeRole(role);
    if (!requiresManualApproval(normalizedRole)) {
      return null;
    }

    const approvalRes = await sb
      .from('role_approvals')
      .select('id, user_id, requested_role, status, requested_at, reviewed_by, reviewed_at, rejection_reason')
      .eq('user_id', userId)
      .eq('requested_role', normalizedRole)
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (approvalRes.error) {
      return null;
    }

    return approvalRes.data || null;
  }

  async function getWholesalerModerationRecord(sb, userId) {
    const [approval, wholesalerRes] = await Promise.all([
      getLatestRoleApproval(sb, userId, PM_ENUMS.ROLES.WHOLESALER),
      sb
        .from('wholesalers')
        .select('id, user_id, display_name, approval_status, created_at, updated_at')
        .eq('user_id', userId)
        .maybeSingle(),
    ]);

    const wholesaler = wholesalerRes.error ? null : (wholesalerRes.data || null);
    const approvalStatus = (() => {
      const applicationStatus = String(approval?.status || '').toLowerCase();
      const wholesalerStatus = String(wholesaler?.approval_status || '').toLowerCase();

      if (applicationStatus === PM_ENUMS.APPROVAL_STATUSES.REJECTED || wholesalerStatus === PM_ENUMS.APPROVAL_STATUSES.REJECTED) {
        return PM_ENUMS.APPROVAL_STATUSES.REJECTED;
      }
      if (wholesalerStatus === PM_ENUMS.APPROVAL_STATUSES.APPROVED) {
        return PM_ENUMS.APPROVAL_STATUSES.APPROVED;
      }
      if (applicationStatus === PM_ENUMS.APPROVAL_STATUSES.APPROVED) {
        return PM_ENUMS.APPROVAL_STATUSES.PENDING;
      }
      if (applicationStatus === PM_ENUMS.APPROVAL_STATUSES.PENDING || wholesalerStatus === PM_ENUMS.APPROVAL_STATUSES.PENDING) {
        return PM_ENUMS.APPROVAL_STATUSES.PENDING;
      }
      return PM_ENUMS.APPROVAL_STATUSES.PENDING;
    })();

    return {
      application: approval,
      wholesaler,
      approvalStatus,
      rejectionReason: approval?.rejection_reason || null,
      displayName: wholesaler?.display_name || '',
    };
  }

  async function getApprovalStatus(sb, userId, role) {
    const normalizedRole = normalizeRole(role);
    if (!requiresManualApproval(normalizedRole)) {
      return PM_ENUMS.APPROVAL_STATUSES.NOT_REQUIRED;
    }

    const approval = await getLatestRoleApproval(sb, userId, normalizedRole);
    if (approval?.status) {
      if (normalizedRole === PM_ENUMS.ROLES.WHOLESALER && String(approval.status).toLowerCase() === PM_ENUMS.APPROVAL_STATUSES.APPROVED) {
        const moderation = await getWholesalerModerationRecord(sb, userId);
        return moderation.approvalStatus;
      }
      return String(approval.status || '').toLowerCase();
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

    // Backward compatibility for legacy wholesaler flow.
    if (normalizedRole === PM_ENUMS.ROLES.WHOLESALER) {
      const moderation = await getWholesalerModerationRecord(sb, userId);
      return moderation.approvalStatus;
    }

    return PM_ENUMS.APPROVAL_STATUSES.PENDING;
  }

  async function loadAccessContext(sb) {
    const sessionRes = await sb.auth.getSession();
    const session = sessionRes?.data?.session;
    if (!session) return null;

    const profileRes = await sb
      .from('profiles')
      .select('id, role')
      .eq('id', session.user.id)
      .single();

    if (profileRes.error || !profileRes.data) {
      throw new Error(profileRes.error?.message || 'Профиль пользователя не найден.');
    }

    const normalizedRole = normalizeRole(profileRes.data.role);
    const moderation = normalizedRole === PM_ENUMS.ROLES.WHOLESALER
      ? await getWholesalerModerationRecord(sb, session.user.id)
      : null;
    const approvalStatus = moderation?.approvalStatus || await getApprovalStatus(sb, session.user.id, normalizedRole);

    return {
      user: session.user,
      profile: profileRes.data,
      role: normalizedRole,
      approvalStatus,
      moderation,
      rejectionReason: moderation?.rejectionReason || null,
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
    getLatestRoleApproval,
    getWholesalerModerationRecord,
    getApprovalStatus,
    loadAccessContext,
    hasRouteAccess,
    canEnterBusinessSection,
  });
})();
