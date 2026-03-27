// lib/core/config/supabase_config.dart
//
// NEVER hardcode credentials here.
// Pass via --dart-define at build time:
//
//   flutter run \
//     --dart-define=SUPABASE_URL=https://kgntismpoaxzkokuvrcl.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=eyJ...
//
// For CI/CD: store in GitHub Secrets, pass as build args.

class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String projectRef = 'kgntismpoaxzkokuvrcl';

  static void assertConfigured() {
    assert(
      url.isNotEmpty,
      'SUPABASE_URL not set.\n'
      'Run with: flutter run --dart-define=SUPABASE_URL=https://kgntismpoaxzkokuvrcl.supabase.co',
    );
    assert(
      anonKey.isNotEmpty,
      'SUPABASE_ANON_KEY not set.\n'
      'Run with: flutter run --dart-define=SUPABASE_ANON_KEY=eyJ...',
    );
  }
}
