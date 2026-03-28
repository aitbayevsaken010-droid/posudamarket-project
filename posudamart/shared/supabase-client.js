(function initSharedSupabaseClient() {
  if (window.sb) return;

  const cfg = window.__POSUDAMART_RUNTIME_CONFIG__ || {};
  const supabaseUrl = (cfg.supabaseUrl || '').trim();
  const supabaseAnonKey = (cfg.supabaseAnonKey || '').trim();

  const placeholderPattern = /POSUDAMART|__|\*\*/i;
  const isInvalid =
    !supabaseUrl ||
    !supabaseAnonKey ||
    placeholderPattern.test(supabaseUrl) ||
    placeholderPattern.test(supabaseAnonKey);

  if (isInvalid) {
    throw new Error(
      'Supabase runtime config is missing or invalid. Please verify public URL and anon key values in shared/runtime-config.js.'
    );
  }

  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    throw new Error('Supabase SDK is not loaded. Include supabase.min.js before shared/supabase-client.js.');
  }

  window.sb = window.supabase.createClient(supabaseUrl, supabaseAnonKey);
})();
