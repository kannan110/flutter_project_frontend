class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://kgntismpoaxzkokuvrcl.supabase.co',
  );
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static void assertConfigured() {
    assert(url.isNotEmpty, 'SUPABASE_URL not configured');
    assert(anonKey.isNotEmpty,
        'SUPABASE_ANON_KEY not set.\nRun: flutter run --dart-define=SUPABASE_ANON_KEY=your_key');
  }
}
