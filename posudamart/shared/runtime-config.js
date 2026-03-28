(function initPosudamartRuntimeConfig(global) {
  if (global.__POSUDAMART_CONFIG__) return;

  // Replace placeholders at deploy time (e.g., sed/envsubst/CI token replacement)
  // or overwrite this file during build.
  global.__POSUDAMART_CONFIG__ = {
    supabaseUrl: '__POSUDAMART_SUPABASE_URL__',
    supabaseAnonKey: '__POSUDAMART_SUPABASE_ANON_KEY__'
  };
})(window);
