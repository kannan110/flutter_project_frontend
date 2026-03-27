class SupabaseConfig {
  static const String url =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static void assertConfigured() {
    assert(url.isNotEmpty,
        'SUPABASE_URL not set. Use --dart-define=SUPABASE_URL=...');
    assert(anonKey.isNotEmpty,
        'SUPABASE_ANON_KEY not set. Use --dart-define=SUPABASE_ANON_KEY=...');
  }
}
