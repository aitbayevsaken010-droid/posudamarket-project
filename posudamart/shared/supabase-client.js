(function initPosudamartSupabaseClient(global) {
  if (!global.supabase || typeof global.supabase.createClient !== 'function') {
    throw new Error('[Posudamart Config Error] Supabase SDK is not loaded. Include the supabase-js CDN script before shared/supabase-client.js.');
  }

  const config = global.__POSUDAMART_CONFIG__ || {};
  const url = (config.supabaseUrl || '').trim();
  const key = (config.supabaseAnonKey || '').trim();
  const hasPlaceholders = url.includes('__POSUDAMART_') || key.includes('__POSUDAMART_');

  if (!url || !key || hasPlaceholders) {
    throw new Error('[Posudamart Config Error] Missing Supabase config. Inject __POSUDAMART_CONFIG__.supabaseUrl and __POSUDAMART_CONFIG__.supabaseAnonKey at build/deploy time.');
  }

  if (!global.__POSUDAMART_SUPABASE_CLIENT__) {
    global.__POSUDAMART_SUPABASE_CLIENT__ = global.supabase.createClient(url, key);
  }

  global.getSupabaseClient = function getSupabaseClient() {
    return global.__POSUDAMART_SUPABASE_CLIENT__;
  };
})(window);
