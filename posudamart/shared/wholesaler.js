const sb = window.sb;
const PM_ENUMS = window.PM_ENUMS;
const PM_ACCESS = window.PM_ACCESS;

let currentWholesalerUser = null;
let currentWholesalerProfile = null;

async function wholesalerAuthGuard() {
  const access = await PM_ACCESS.loadAccessContext(sb);
  if (!access || !PM_ACCESS.hasRouteAccess(access, [PM_ENUMS.ROLES.WHOLESALER])) {
    window.location.href = '../index.html';
    return null;
  }

  const { data: wholesaler, error } = await sb
    .from('wholesalers')
    .select('*')
    .eq('user_id', access.user.id)
    .maybeSingle();

  if (error) {
    alert(error.message || 'Не удалось загрузить профиль оптовика.');
    window.location.href = '../index.html';
    return null;
  }

  if (!wholesaler || wholesaler.approval_status !== PM_ENUMS.APPROVAL_STATUSES.APPROVED) {
    window.location.href = '../index.html';
    return null;
  }

  currentWholesalerUser = access.user;
  currentWholesalerProfile = wholesaler;
  const nameEl = document.getElementById('user-name');
  if (nameEl) nameEl.textContent = access.user.email || 'Оптовик';
  return wholesaler;
}

async function wholesalerSignOut() {
  await sb.auth.signOut();
  window.location.href = '../index.html';
}
