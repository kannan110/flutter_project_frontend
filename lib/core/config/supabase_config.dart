class SupabaseConfig {
  //rooster Staging
 /* static const url     = 'https://kgntismpoaxzkokuvrcl.supabase.co';
  static const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtnbnRpc21wb2F4emtva3V2cmNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ1MzM1NTQsImV4cCI6MjA5MDEwOTU1NH0.Fv2bRBemkjCWtvZuEqe1wF0iOLPqAqNS67Bq2NWomUs';
  */
  //rooster Production
  /*static const url     = 'https://jgucjlggqpgprrlrzguq.supabase.co';
  static const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpndWNqbGdncXBncHJybHJ6Z3VxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2NDk2NDgsImV4cCI6MjA5NTIyNTY0OH0.58ci0vRMnghsGToFe-2bsl31oBDFghgx8gwhVS-q26M';
*/
  //Trade Staging
  static const url     = 'https://jhlraqsntgrpwctgpuzc.supabase.co';
  static const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpobHJhcXNudGdycHdjdGdwdXpjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NzAwNjgsImV4cCI6MjEwNzU0NjA2OH0.BVEw1hpOYds6XK-5ZvbwfWQW7qmdH3fGv_H5YrDsjfo';


  static void assertConfigured() {
    assert(url.isNotEmpty,     'SUPABASE_URL not configured');
    assert(anonKey.isNotEmpty, 'SUPABASE_ANON_KEY not configured');
  }
}
