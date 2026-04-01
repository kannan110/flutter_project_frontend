class SupabaseConfig {
  static const url     = 'https://kgntismpoaxzkokuvrcl.supabase.co';
  static const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtnbnRpc21wb2F4emtva3V2cmNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ1MzM1NTQsImV4cCI6MjA5MDEwOTU1NH0.Fv2bRBemkjCWtvZuEqe1wF0iOLPqAqNS67Bq2NWomUs';

  static void assertConfigured() {
    assert(url.isNotEmpty,     'SUPABASE_URL not configured');
    assert(anonKey.isNotEmpty, 'SUPABASE_ANON_KEY not configured');
  }
}
