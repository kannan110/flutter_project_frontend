import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_ledger_print_builder.dart' show RetailerLedgerJob, BatchLedgerFailure, BatchFailureStage;

// ─────────────────────────────────────────────────────────────────────────────
// BulkCustomerLedgerService
//
// Fetches get_retailer_statement() for many retailers — the exact same RPC,
// same params, same response shape the single-retailer Customer Ledger flow
// already uses (reports_hub_screen.dart's _load() / customer_ledger_print_
// builder.dart's build()). No new balance/ledger math, no duplicated
// calculation logic — this class only orchestrates *how many RPC calls run
// at once* and *what happens when one of them fails*.
//
// Bounded concurrency (a handful of requests in flight at a time) instead of
// fully sequential (too slow for 50-200+ retailers) or fully parallel (risks
// hammering Supabase / the device with 200 simultaneous requests). A single
// retailer's failure is caught, recorded, and never allowed to abort the
// rest of the batch or to be silently dropped.
// ─────────────────────────────────────────────────────────────────────────────

class BulkCustomerLedgerService {
  const BulkCustomerLedgerService._();

  static const int _concurrency = 6;
  static const Duration _perCallTimeout = Duration(seconds: 20);

  /// [retailers] — list of {id, shop_name} maps (exactly what the existing
  /// retailer picker/dropdown already loads — no new query shape).
  /// [isCancelled] is checked between concurrency chunks so a trader can
  /// abort a long batch (e.g. 200 retailers) partway through; requests
  /// already in flight for the current chunk are allowed to finish, but no
  /// further chunks are started.
  /// [onProgress] fires once per retailer as its fetch completes
  /// (success or failure) — `done` includes both.
  static Future<BulkFetchResult> fetchStatements({
    required List<Map<String, dynamic>> retailers,
    required DateTime fromDate,
    required DateTime toDate,
    String? agentId,
    bool Function()? isCancelled,
    void Function(int done, int total, String currentRetailerName)? onProgress,
  }) async {
    final client = Supabase.instance.client;
    final total = retailers.length;
    final jobs = <RetailerLedgerJob>[];
    final failures = <BatchLedgerFailure>[];
    var done = 0;
    var wasCancelled = false;

    for (var i = 0; i < retailers.length; i += _concurrency) {
      if (isCancelled?.call() == true) {
        wasCancelled = true;
        break;
      }
      final end = (i + _concurrency > total) ? total : i + _concurrency;
      final chunk = retailers.sublist(i, end);

      final outcomes = await Future.wait(chunk.map((r) async {
        final id = r['id'] as String;
        final name = r['shop_name'] as String? ?? '—';
        try {
          final res = await client.rpc('get_retailer_statement', params: {
            'p_retailer_id': id,
            'p_from_date': DateFormat('yyyy-MM-dd').format(fromDate),
            'p_to_date': DateFormat('yyyy-MM-dd').format(toDate),
            if (agentId != null) 'p_agent_id': agentId,
          }).timeout(_perCallTimeout);
          final data = (res as Map?)?.cast<String, dynamic>() ?? {};
          return _FetchOutcome.ok(RetailerLedgerJob(retailerId: id, retailerName: name, data: data));
        } catch (e) {
          return _FetchOutcome.fail(BatchLedgerFailure(
            retailerId: id,
            retailerName: name,
            stage: BatchFailureStage.fetch,
            reason: e.toString().replaceAll('Exception: ', ''),
          ));
        }
      }));

      for (final o in outcomes) {
        done++;
        if (o.job != null) jobs.add(o.job!);
        if (o.failure != null) failures.add(o.failure!);
        onProgress?.call(done, total, o.job?.retailerName ?? o.failure?.retailerName ?? '');
      }
    }

    return BulkFetchResult(jobs: jobs, failures: failures, cancelled: wasCancelled);
  }
}

class _FetchOutcome {
  _FetchOutcome.ok(this.job) : failure = null;
  _FetchOutcome.fail(this.failure) : job = null;
  final RetailerLedgerJob? job;
  final BatchLedgerFailure? failure;
}

class BulkFetchResult {
  const BulkFetchResult({required this.jobs, required this.failures, this.cancelled = false});
  final List<RetailerLedgerJob> jobs;
  final List<BatchLedgerFailure> failures;
  final bool cancelled;
}