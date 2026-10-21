class SupabaseConfig {
 
 
  //Trade Staging
  static const url     = 'https://jhlraqsntgrpwctgpuzc.supabase.co';
  static const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpobHJhcXNudGdycHdjdGdwdXpjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NzAwNjgsImV4cCI6MjEwNzU0NjA2OH0.BVEw1hpOYds6XK-5ZvbwfWQW7qmdH3fGv_H5YrDsjfo';

 
 
  static void assertConfigured() {
    assert(url.isNotEmpty,     'SUPABASE_URL not configured');
    assert(anonKey.isNotEmpty, 'SUPABASE_ANON_KEY not configured');
  }
}