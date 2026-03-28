const SUPABASE_URL = 'https://dnpsufzgnudgrqbezioo.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRucHN1ZnpnbnVkZ3JxYmV6aW9vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ0NjYxNjAsImV4cCI6MjA5MDA0MjE2MH0.N8qP1DfkCmJ9uKMkowtmUYQc-F_ybEyPdfTo86PIGEk';
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// ══ THEME SYSTEM ══
const APP_THEMES = {
  blue:   { label: "Синий",    accent: "#4f6ef7", glow: "rgba(79,110,247,0.18)",  bg: "#0f1117", surface: "#181c27", surface2: "#1e2334", border: "#2a3045", border2: "#374060" },
  violet: { label: "Фиолет",   accent: "#7c3aed", glow: "rgba(124,58,237,0.18)",  bg: "#0f0f17", surface: "#18172a", surface2: "#1e1c36", border: "#2d2a50", border2: "#3d3870" },
  green:  { label: "Зелёный",  accent: "#059669", glow: "rgba(5,150,105,0.18)",   bg: "#0a100e", surface: "#141f1b", surface2: "#182420", border: "#1e3429", border2: "#26453a" },
  red:    { label: "Красный",  accent: "#dc2626", glow: "rgba(220,38,38,0.18)",   bg: "#110e0e", surface: "#1f1515", surface2: "#261a1a", border: "#3a2020", border2: "#4d2828" },
  orange: { label: "Оранжев.", accent: "#ea580c", glow: "rgba(234,88,12,0.18)",   bg: "#110f0a", surface: "#1f1912", surface2: "#271f16", border: "#3a2e1e", border2: "#4d3d28" },
  cyan:   { label: "Циан",     accent: "#0891b2", glow: "rgba(8,145,178,0.18)",   bg: "#0a0f12", surface: "#141c20", surface2: "#182228", border: "#1e3040", border2: "#264055" },
  pink:   { label: "Розовый",  accent: "#db2777", glow: "rgba(219,39,119,0.18)",  bg: "#110a0f", surface: "#1f1219", surface2: "#261620", border: "#3a2032", border2: "#4d2844" },
  white:  { label: "Светлый",  accent: "#4f6ef7", glow: "rgba(79,110,247,0.15)",  bg: "#f0f2f8", surface: "#ffffff", surface2: "#e8ecf4", border: "#d0d8e8", border2: "#b8c4d8", text: "#1a2040", muted: "#6b7a9e" },
};

function applyTheme(themeKey) {
  const t = APP_THEMES[themeKey] || APP_THEMES.blue;
  const r = document.documentElement;
  r.style.setProperty("--accent", t.accent);
  r.style.setProperty("--accent-glow", t.glow || t.accent + "30");
  r.style.setProperty("--bg", t.bg);
  r.style.setProperty("--surface", t.surface);
  r.style.setProperty("--surface2", t.surface2);
  r.style.setProperty("--border", t.border);
  r.style.setProperty("--border2", t.border2);
  if (t.text)  r.style.setProperty("--text", t.text);
  else         r.style.removeProperty("--text");
  if (t.muted) r.style.setProperty("--muted", t.muted);
  else         r.style.removeProperty("--muted");
}

function saveTheme(themeKey) {
  localStorage.setItem("clt_theme", themeKey);
  applyTheme(themeKey);
}

function renderThemePicker(containerId) {
  const current = localStorage.getItem("clt_theme") || "blue";
  const grid = document.getElementById(containerId);
  if (!grid) return;
  grid.innerHTML = Object.entries(APP_THEMES).map(([key, t]) => `
    <button onclick="pickTheme('${key}')" style="
      display:flex;flex-direction:column;align-items:center;gap:8px;
      padding:12px 8px;border-radius:12px;cursor:pointer;transition:all .15s;
      border:2px solid ${key===current?t.accent:"var(--border)"};
      background:${key===current?t.accent+"22":"var(--surface2)"};
    ">
      <div style="display:flex;gap:4px">
        <div style="width:16px;height:16px;border-radius:50%;background:${t.bg};border:1px solid ${t.border2}"></div>
        <div style="width:16px;height:16px;border-radius:50%;background:${t.accent}"></div>
        <div style="width:16px;height:16px;border-radius:50%;background:${t.surface}"></div>
      </div>
      <span style="font-size:11px;font-weight:700;color:${key===current?t.accent:"var(--muted)"}">
        ${key===current?"✓ ":""}${t.label}
      </span>
    </button>
  `).join("");
}

function pickTheme(key) {
  saveTheme(key);
  renderThemePicker("theme-grid");
  if (typeof showToast === "function") showToast("✓ Тема изменена");
}

// Применяем сохранённую тему сразу при загрузке
(function() {
  const saved = localStorage.getItem("clt_theme");
  if (saved && APP_THEMES[saved]) applyTheme(saved);
})();



let currentUser = null;
let currentClient = null; // profile row

function fmtMoney(n){return Number(n||0).toLocaleString('ru-RU',{minimumFractionDigits:2,maximumFractionDigits:2})+' ₸'}
function fmtNum(n){return Number(n||0).toLocaleString('ru-RU')}
function uid(){return crypto.randomUUID()}
function esc(s){const d=document.createElement('div');d.textContent=String(s||'');return d.innerHTML}

function showToast(msg,ok=true){
  let t=document.getElementById('toast');
  t.textContent=msg;
  t.style.background=ok?'var(--accent)':'var(--danger)';
  t.style.opacity='1';
  clearTimeout(t._t);
  t._t=setTimeout(()=>t.style.opacity='0',2800);
}

function statusBadge(s){
  if(s==='Новый')          return`<span class="badge badge-new">Новый</span>`;
  if(s==='Изменён')        return`<span class="badge badge-changed">⚠ Изменён поставщиком</span>`;
  if(s==='Подтверждён')    return`<span class="badge badge-confirmed">✓ Подтверждён</span>`;
  if(s==='Отменён')        return`<span class="badge badge-cancelled">Отменён</span>`;
  return`<span class="badge badge-new">${esc(s)}</span>`;
}

// Auth guard
async function authGuard(){
  const{data:{session}}=await sb.auth.getSession();
  if(!session){window.location.href='../index.html';return null}
  const{data:profile}=await sb.from('profiles').select('*').eq('id',session.user.id).single();
  if(!profile||profile.role!=='client'){window.location.href='../index.html';return null}
  currentUser=session.user;
  currentClient=profile;
  const nameEl=document.getElementById('user-name');
  if(nameEl) nameEl.textContent=profile.full_name||session.user.email;
  const loadingEl=document.getElementById('auth-loading');
  if(loadingEl) loadingEl.style.display='none';
  return profile;
}

async function signOut(){await sb.auth.signOut();window.location.href='../index.html'}
