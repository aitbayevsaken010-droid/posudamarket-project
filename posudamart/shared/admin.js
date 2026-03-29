const sb = window.sb;

let currentAdminUser = null;

// ══ THEME SYSTEM ══
const ADMIN_THEMES = {
  blue:   { label: 'Синий',    accent: '#4f6ef7', glow: 'rgba(79,110,247,0.18)',  bg: '#0f1117', surface: '#181c27', surface2: '#1e2334', border: '#2a3045', border2: '#374060' },
  violet: { label: 'Фиолет',   accent: '#7c3aed', glow: 'rgba(124,58,237,0.18)',  bg: '#0f0f17', surface: '#18172a', surface2: '#1e1c36', border: '#2d2a50', border2: '#3d3870' },
  green:  { label: 'Зелёный',  accent: '#059669', glow: 'rgba(5,150,105,0.18)',   bg: '#0a100e', surface: '#141f1b', surface2: '#182420', border: '#1e3429', border2: '#26453a' },
  red:    { label: 'Красный',  accent: '#dc2626', glow: 'rgba(220,38,38,0.18)',   bg: '#110e0e', surface: '#1f1515', surface2: '#261a1a', border: '#3a2020', border2: '#4d2828' },
  orange: { label: 'Оранжев.', accent: '#ea580c', glow: 'rgba(234,88,12,0.18)',   bg: '#110f0a', surface: '#1f1912', surface2: '#271f16', border: '#3a2e1e', border2: '#4d3d28' },
  cyan:   { label: 'Циан',     accent: '#0891b2', glow: 'rgba(8,145,178,0.18)',   bg: '#0a0f12', surface: '#141c20', surface2: '#182228', border: '#1e3040', border2: '#264055' },
  pink:   { label: 'Розовый',  accent: '#db2777', glow: 'rgba(219,39,119,0.18)',  bg: '#110a0f', surface: '#1f1219', surface2: '#261620', border: '#3a2032', border2: '#4d2844' },
  white:  { label: 'Светлый',  accent: '#4f6ef7', glow: 'rgba(79,110,247,0.15)',  bg: '#f0f2f8', surface: '#ffffff', surface2: '#e8ecf4', border: '#d0d8e8', border2: '#b8c4d8', text: '#1a2040', muted: '#6b7a9e' },
};
// Alias so profile page works with same name
const APP_THEMES = ADMIN_THEMES;

function applyTheme(themeKey) {
  const t = APP_THEMES[themeKey] || APP_THEMES.white;
  const r = document.documentElement;
  r.style.setProperty('--accent', t.accent);
  r.style.setProperty('--accent-glow', t.glow);
  r.style.setProperty('--bg', t.bg);
  r.style.setProperty('--surface', t.surface);
  r.style.setProperty('--surface2', t.surface2);
  r.style.setProperty('--border', t.border);
  r.style.setProperty('--border2', t.border2);
  // Topbar background — slightly darker/transparent version of bg
  r.style.setProperty('--topbar-bg', t.bg + 'f7'); // hex opacity ~97%
  if (t.text)  r.style.setProperty('--text', t.text);
  else         r.style.removeProperty('--text');
  if (t.muted) r.style.setProperty('--muted', t.muted);
  else         r.style.removeProperty('--muted');
}

function saveTheme(themeKey) {
  localStorage.setItem('adm_theme', themeKey);
  applyTheme(themeKey);
}

// Apply saved theme immediately on every page load
(function() {
  const saved = localStorage.getItem('adm_theme') || 'white';
  if (APP_THEMES[saved]) applyTheme(saved);
})();

function fmtMoney(n){return Number(n||0).toLocaleString('ru-RU',{minimumFractionDigits:2,maximumFractionDigits:2})+' ₸'}
function fmtNum(n){return Number(n||0).toLocaleString('ru-RU')}
function uid(){return crypto.randomUUID()}
function esc(s){const d=document.createElement('div');d.textContent=String(s||'');return d.innerHTML}
function sanitizeImageUrl(url){
  const raw=String(url||'').trim();
  if(!raw) return '';
  if(raw.startsWith('https://')) return raw;
  if(/^data:image\/(?:png|jpeg|jpg|webp|gif|bmp|svg\+xml);base64,[a-z0-9+/=\s]+$/i.test(raw)){
    return raw.replace(/\s+/g,'');
  }
  return '';
}
function statusBadge(s){
  if(s==='Оформлен')return`<span class="badge badge-done">Оформлен</span>`;
  if(s==='Закрыт')return`<span class="badge badge-closed">Закрыт</span>`;
  return`<span class="badge badge-draft">Черновик</span>`;
}

function showToast(msg,ok=true){
  let t=document.getElementById('toast');
  t.textContent=msg;
  t.style.background=ok?'var(--accent)':'var(--danger)';
  t.style.opacity='1';
  clearTimeout(t._t);
  t._t=setTimeout(()=>t.style.opacity='0',2800);
}

async function resizeImage(file,max=900){
  return new Promise((res,rej)=>{
    const r=new FileReader();
    r.onload=e=>{
      const img=new Image();
      img.onload=()=>{
        let{width:w,height:h}=img;
        if(w>max||h>max){const k=Math.min(max/w,max/h);w=Math.round(w*k);h=Math.round(h*k)}
        const c=document.createElement('canvas');c.width=w;c.height=h;
        c.getContext('2d').drawImage(img,0,0,w,h);
        res(c.toDataURL('image/jpeg',0.82));
      };
      img.onerror=rej;img.src=e.target.result;
    };
    r.onerror=rej;r.readAsDataURL(file);
  });
}

// ══ ADMIN AUTH GUARD ══
async function adminAuthGuard() {
  try {
    const cachedEmail = localStorage.getItem('adm_email') || '';
    if (cachedEmail) setAdminEmail(cachedEmail);

    const { data: { session } } = await sb.auth.getSession();
    if (!session) { redirectToCommonLogin(); return null; }

    const { data: profile } = await sb.from('profiles').select('role').eq('id', session.user.id).single();
    if (!profile || profile.role !== 'admin') {
      await sb.auth.signOut();
      localStorage.removeItem('adm_role');
      localStorage.removeItem('adm_id');
      localStorage.removeItem('adm_email');
      window.location.href = '../index.html';
      return null;
    }

    localStorage.setItem('adm_role', 'admin');
    localStorage.setItem('adm_id', session.user.id);
    localStorage.setItem('adm_email', session.user.email || '');
    currentAdminUser = session.user;
    setAdminEmail(session.user.email);
    showAdminShell();
    _validateSessionBackground(session.user.id);
    return session.user;
  } catch(e) {
    redirectToCommonLogin();
    return null;
  }
}

// Фоновая проверка сессии после успешной авторизации
async function _validateSessionBackground(authenticatedId) {
  if (!authenticatedId) return;
  try {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) {
      if (currentAdminUser && currentAdminUser.id === authenticatedId) {
        localStorage.removeItem('adm_role');
        localStorage.removeItem('adm_id');
        localStorage.removeItem('adm_email');
        await sb.auth.signOut();
        if (!window.location.pathname.endsWith('/index.html') && !window.location.pathname.endsWith('/')) {
          window.location.href = '../index.html';
        }
      }
      return;
    }
    if (session.user.id !== authenticatedId) return;
    // Обновляем реальные данные пользователя
    currentAdminUser = session.user;
    localStorage.setItem('adm_id', session.user.id);
    localStorage.setItem('adm_email', session.user.email || '');
    setAdminEmail(session.user.email);
  } catch(e) {
    // Сеть недоступна — не редиректим, сохранит текущую страницу
  }
}

function redirectToCommonLogin() {
  if (window.location.pathname.endsWith('/index.html') || window.location.pathname === '/') return;
  window.location.href = '../index.html';
}


async function adminSignOut() {
  localStorage.removeItem('adm_role');
  localStorage.removeItem('adm_id');
  await sb.auth.signOut();
  window.location.href = '../index.html';
}

function setAdminEmail(email){
  const el=document.getElementById('admin-email');
  if(!el) return;
  el.textContent=email||'—';
  if(email) el.title=email;
}

function showAdminShell(){
  const header=document.getElementById('main-header');
  const content=document.getElementById('main-content');
  const loading=document.getElementById('auth-loading');
  if(header) header.style.display='';
  if(content) content.style.display='';
  if(loading) loading.style.display='none';
}

function prefetchAdminLinks(){
  const links=[...document.querySelectorAll('a.nav-btn[href], a.btn[href], .nav a[href]')];
  const seen=new Set();
  for(const a of links){
    const href=a.getAttribute('href');
    if(!href||href.startsWith('#')||href.startsWith('http')||seen.has(href)) continue;
    seen.add(href);
    const l=document.createElement('link');
    l.rel='prefetch';
    l.href=href;
    document.head.appendChild(l);
    a.addEventListener('mouseenter',()=>{fetch(href,{credentials:'same-origin'}).catch(()=>{})},{once:true});
    a.addEventListener('touchstart',()=>{fetch(href,{credentials:'same-origin'}).catch(()=>{})},{once:true,passive:true});
  }
}

function initAdminInstantNav(){
  prefetchAdminLinks();
  const navLinks=[...document.querySelectorAll('a.nav-btn[href]')];
  for(const a of navLinks){
    a.addEventListener('click',()=>{
      try{sessionStorage.setItem('pm_admin_nav_ts', String(Date.now()));}catch(e){}
      const loading=document.getElementById('auth-loading');
      if(loading){
        loading.innerHTML='<div style="display:flex;align-items:center;gap:10px;color:var(--muted);font-weight:600"><div class="spinner"></div><span>Загрузка раздела…</span></div>'
        loading.style.display='flex';
        loading.style.zIndex='9997';
        loading.style.background='rgba(15,17,23,.55)';
        loading.style.backdropFilter='blur(2px)';
      }
    });
  }
}

(function(){
  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded', initAdminInstantNav, {once:true});
  }else{
    initAdminInstantNav();
  }
})();
