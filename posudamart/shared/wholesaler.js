const sb = window.sb;
const PM_ENUMS = window.PM_ENUMS;
const PM_ACCESS = window.PM_ACCESS;

let currentWholesalerUser = null;
let currentWholesalerProfile = null;
let redirectIssued = false;

function redirectToIndex(reason) {
  if (redirectIssued) return;
  redirectIssued = true;
  console.info(`[PM_REDIRECT] ${window.location.pathname} -> ../index.html | reason=${reason}`);
  window.location.href = '../index.html';
}

async function wholesalerAuthGuard() {
  console.info('[PM_AUTH_BOOTSTRAP] wholesalerAuthGuard:start');
  const access = await PM_ACCESS.loadAccessContext(sb);
  if (!access || !PM_ACCESS.hasRouteAccess(access, [PM_ENUMS.ROLES.WHOLESALER])) {
    redirectToIndex('no route access for wholesaler');
    return null;
  }

  const { data: wholesaler, error } = await sb
    .from('wholesalers')
    .select('*')
    .eq('user_id', access.user.id)
    .maybeSingle();

  if (error) {
    alert(error.message || 'Не удалось загрузить профиль оптовика.');
    redirectToIndex('failed to load wholesalers profile');
    return null;
  }

  if (!wholesaler || wholesaler.approval_status !== PM_ENUMS.APPROVAL_STATUSES.APPROVED) {
    redirectToIndex('wholesaler approval is not approved');
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
  redirectToIndex('sign out');
}
