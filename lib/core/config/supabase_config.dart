class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://kgntismpoaxzkokuvrcl.supabase.co',
  );
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  // FIX Bug #5: Use throw instead of assert so it fails in ALL build modes (not just debug)
  static void assertConfigured() {
    if (url.isEmpty) {
      throw StateError(
        'SUPABASE_URL not configured.\n'
        'Run: flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co',
      );
    }
    if (anonKey.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY not set.\n'
        'Run: flutter run --dart-define=SUPABASE_ANON_KEY=your_key',
      );
    }
  }
}
