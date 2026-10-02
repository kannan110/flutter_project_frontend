import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import 'bulk_custmoreledger_service.dart';
import 'bulk_ledger_delivery.dart';
import 'customer_ledger_print_builder.dart';
import 'report_dataset.dart' show ReportPrintStyle;

// ─────────────────────────────────────────────────────────────────────────────
// Bulk Customer Ledger Print / Download
//
// Two entry points — runBulkPrintOrSaveAllFlow (Print All / Download All)
// and runBulkSelectRetailersFlow (Select Retailers → Print/Download
// Selected) — called from reports_hub_screen.dart's Customer Ledger
// toolbar. Both resolve a retailer list + an isPrint flag, then hand off
// to one of two flows that deliberately produce DIFFERENT artifacts:
//
//   _executePrintFlow    — ONE combined pw.Document (CustomerLedgerPrint
//                          Builder.buildBatch), each customer its own
//                          page-section, sent to ONE native print dialog
//                          (printPreparedDocument). A trader printing 50
//                          ledgers gets 50 sections in one paper stack —
//                          a printer has no notion of "50 separate jobs"
//                          that would matter here, and 50 print dialogs
//                          in a row would be unusable. Unchanged from
//                          the original bulk-print implementation.
//
//   _executeDownloadFlow — N fully independent pw.Documents (Customer
//                          LedgerPrintBuilder.buildIndividual), one real
//                          PDF per customer, delivered as N separate
//                          files (BulkLedgerDelivery) — never combined,
//                          never requiring the trader to split anything
//                          themselves. This is the part that changed:
//                          Download used to produce one combined PDF via
//                          Printing.sharePdf; it now produces N files.
//
// Both flows share the same layout/style pickers, the same progress
// dialog, and the same fetch-with-retry logic (_fetchJobsWithRetry) —
// factored out below so the two flows can never quietly drift apart on
// failure handling, only on what happens once a clean job list exists.
// ─────────────────────────────────────────────────────────────────────────────

/// Entry point for the "Print All" / "Download All" toolbar buttons —
/// [allRetailers] is the trader's full active retailer list (id +
/// shop_name), the same shape/query the existing single-retailer dropdown
/// already uses, just without its old 50-row cap.
Future<void> runBulkPrintOrSaveAllFlow({
  required BuildContext context,
  required List<Map<String, dynamic>> allRetailers,
  required bool isPrint,
  required String companyName,
  required DateTime fromDate,
  required DateTime toDate,
  String? agentId,
}) async {
  if (allRetailers.isEmpty) {
    showError(context, 'No active retailers to include');
    return;
  }
  if (isPrint) {
    await _executePrintFlow(
      context: context, retailers: allRetailers, companyName: companyName,
      fromDate: fromDate, toDate: toDate, agentId: agentId,
    );
  } else {
    await _executeDownloadFlow(
      context: context, retailers: allRetailers, companyName: companyName,
      fromDate: fromDate, toDate: toDate, agentId: agentId,
    );
  }
}

/// Entry point for the "Select Retailers" toolbar button — opens the
/// multi-select sheet, which itself carries the "Print Selected" /
/// "Download Selected" choice on its two confirm buttons.
Future<void> runBulkSelectRetailersFlow({
  required BuildContext context,
  required List<Map<String, dynamic>> allRetailers,
  required String companyName,
  required DateTime fromDate,
  required DateTime toDate,
  String? agentId,
}) async {
  final picked = await showRetailerMultiSelectSheet(context, retailers: allRetailers);
  if (picked == null || picked.retailers.isEmpty || !context.mounted) return;
  if (picked.isPrint) {
    await _executePrintFlow(
      context: context, retailers: picked.retailers, companyName: companyName,
      fromDate: fromDate, toDate: toDate, agentId: agentId,
    );
  } else {
    await _executeDownloadFlow(
      context: context, retailers: picked.retailers, companyName: companyName,
      fromDate: fromDate, toDate: toDate, agentId: agentId,
    );
  }
}

/// Shared fetch (+ retry / continue-without-them) logic used by both the
/// Print flow and the Download flow below — the only difference between
/// them is what happens AFTER a clean job list is obtained. Returns null
/// if the trader cancelled or aborted at any point; the caller should
/// just return without further action in that case. Never returns an
/// empty, non-null list — that case already resolves to null internally.
Future<List<RetailerLedgerJob>?> _fetchJobsWithRetry({
  required BuildContext context,
  required List<Map<String, dynamic>> retailers,
  required DateTime fromDate,
  required DateTime toDate,
  String? agentId,
}) async {
  final progress = _BulkProgressController();
  var cancelled = false;
  final progressDialog = _showProgressDialog(
    context,
    controller: progress,
    onCancel: () {
      cancelled = true;
      progress.markCancelling();
    },
  );

  BulkFetchResult fetchResult;
  try {
    progress.update(phase: 'Fetching ledger data', done: 0, total: retailers.length, currentName: '');
    fetchResult = await BulkCustomerLedgerService.fetchStatements(
      retailers: retailers,
      fromDate: fromDate,
      toDate: toDate,
      agentId: agentId,
      isCancelled: () => cancelled,
      onProgress: (done, total, name) =>
          progress.update(phase: 'Fetching ledger data', done: done, total: total, currentName: name),
    );
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await progressDialog;
  }

  if (!context.mounted) return null;
  if (cancelled) {
    showError(context, 'Cancelled — nothing was generated');
    return null;
  }

  var jobs = fetchResult.jobs;
  var allFailures = List<BatchLedgerFailure>.from(fetchResult.failures);

  if (allFailures.isNotEmpty) {
    final decision = await showBatchFailureDialog(
      context,
      failures: allFailures,
      succeeded: jobs.length,
      total: retailers.length,
      canRetry: true,
    );
    if (decision == null || decision == _FailureDecision.cancel || !context.mounted) {
      return null;
    }
    if (decision == _FailureDecision.retry) {
      final failedRetailers = retailers
          .where((r) => allFailures.any((f) => f.retailerId == r['id']))
          .toList();
      final retryProgress = _BulkProgressController();
      final retryDialog = _showProgressDialog(context, controller: retryProgress, onCancel: null);
      BulkFetchResult retryResult;
      try {
        retryResult = await BulkCustomerLedgerService.fetchStatements(
          retailers: failedRetailers,
          fromDate: fromDate,
          toDate: toDate,
          agentId: agentId,
          onProgress: (done, total, name) => retryProgress.update(
              phase: 'Retrying failed retailers', done: done, total: total, currentName: name),
        );
      } finally {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        await retryDialog;
      }
      jobs = [...jobs, ...retryResult.jobs];
      allFailures = retryResult.failures; // only still-failing retailers remain
      if (allFailures.isNotEmpty && context.mounted) {
        final again = await showBatchFailureDialog(
          context,
          failures: allFailures,
          succeeded: jobs.length,
          total: retailers.length,
          canRetry: false, // avoid an unbounded retry loop on a persistent failure
        );
        if (again != _FailureDecision.continueWithout || !context.mounted) return null;
      }
    }
    // decision == continueWithout falls through with `jobs` as-is.
  }

  if (jobs.isEmpty) {
    if (context.mounted) showError(context, 'No ledgers could be generated');
    return null;
  }
  return jobs;
}

/// Print All / Print Selected — ONE combined document, ONE print dialog.
/// Unchanged in behavior from the original bulk-print implementation.
Future<void> _executePrintFlow({
  required BuildContext context,
  required List<Map<String, dynamic>> retailers,
  required String companyName,
  required DateTime fromDate,
  required DateTime toDate,
  String? agentId,
}) async {
  final size = await pickPrintSheetSize(context);
  if (size == null || !context.mounted) return;
  final style = await pickPrintStyleChoice(context);
  if (style == null || !context.mounted) return;

  final jobs = await _fetchJobsWithRetry(
    context: context, retailers: retailers, fromDate: fromDate, toDate: toDate, agentId: agentId,
  );
  if (jobs == null || !context.mounted) return;

  final buildProgress = _BulkProgressController();
  final buildDialog = _showProgressDialog(context, controller: buildProgress, onCancel: null);
  BatchLedgerResult result;
  try {
    result = await CustomerLedgerPrintBuilder.buildBatch(
      jobs: jobs,
      companyName: companyName,
      fromDate: fromDate,
      toDate: toDate,
      size: size,
      style: style,
      onProgress: (done, total, name) =>
          buildProgress.update(phase: 'Building combined PDF', done: done, total: total, currentName: name),
    );
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await buildDialog;
  }

  if (!context.mounted) return;

  if (result.failures.isNotEmpty) {
    final decision = await showBatchFailureDialog(
      context,
      failures: result.failures,
      succeeded: result.succeeded,
      total: result.totalRequested,
      canRetry: false, // a build failure on the same data will fail again identically
    );
    if (decision != _FailureDecision.continueWithout || !context.mounted) return;
  }

  final doc = result.document;
  if (doc == null) {
    if (context.mounted) showError(context, 'No ledger pages could be generated');
    return;
  }

  final sheetLabel = size.isHalf ? 'HalfSheet' : 'FullSheet';
  final filename = 'Ledgers_${result.succeeded}Retailers_${sheetLabel}_'
      '${DateFormat('yyyyMMdd').format(fromDate)}.pdf';

  try {
    await CustomerLedgerPrintBuilder.printPreparedDocument(
      doc: doc, pageFormat: size.pageFormat, filename: filename,
    );
    if (context.mounted) {
      showSuccess(
        context,
        result.succeeded == result.totalRequested
            ? '${result.succeeded} retailer ledgers sent to print'
            : '${result.succeeded} of ${result.totalRequested} retailer ledgers sent to print',
      );
    }
  } catch (e) {
    if (context.mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
  }
}

/// Download All / Download Selected — N fully independent PDFs, one per
/// customer, delivered as N separate files (BulkLedgerDelivery: multi-
/// file share sheet on mobile, ZIP on Web). Never re-combined.
Future<void> _executeDownloadFlow({
  required BuildContext context,
  required List<Map<String, dynamic>> retailers,
  required String companyName,
  required DateTime fromDate,
  required DateTime toDate,
  String? agentId,
}) async {
  final size = await pickPrintSheetSize(context);
  if (size == null || !context.mounted) return;
  final style = await pickPrintStyleChoice(context);
  if (style == null || !context.mounted) return;

  final jobs = await _fetchJobsWithRetry(
    context: context, retailers: retailers, fromDate: fromDate, toDate: toDate, agentId: agentId,
  );
  if (jobs == null || !context.mounted) return;

  final buildProgress = _BulkProgressController();
  final buildDialog = _showProgressDialog(context, controller: buildProgress, onCancel: null);
  IndividualBuildResult result;
  try {
    result = await CustomerLedgerPrintBuilder.buildIndividual(
      jobs: jobs,
      companyName: companyName,
      fromDate: fromDate,
      toDate: toDate,
      size: size,
      style: style,
      onProgress: (done, total, name) => buildProgress.update(
          phase: 'Preparing individual PDFs', done: done, total: total, currentName: name),
    );
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await buildDialog;
  }

  if (!context.mounted) return;

  if (result.failures.isNotEmpty) {
    final decision = await showBatchFailureDialog(
      context,
      failures: result.failures,
      succeeded: result.succeeded,
      total: result.totalRequested,
      canRetry: false, // a build failure on the same data will fail again identically
    );
    if (decision != _FailureDecision.continueWithout || !context.mounted) return;
  }

  if (result.files.isEmpty) {
    if (context.mounted) showError(context, 'No ledger files could be generated');
    return;
  }

  try {
    await BulkLedgerDelivery.deliverIndividualFiles(files: result.files, fromDate: fromDate);
    if (context.mounted) {
      final complete = result.succeeded == result.totalRequested;
      showSuccess(
        context,
        kIsWeb
            ? '${result.succeeded} ledgers zipped for download'
            : complete
            ? '${result.succeeded} individual ledger PDFs ready to share'
            : '${result.succeeded} of ${result.totalRequested} individual ledger PDFs ready to share',
      );
    }
  } catch (e) {
    if (context.mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
  }
}

// ── Progress dialog ─────────────────────────────────────────────────────────

class _BulkProgress {
  const _BulkProgress({
    required this.phase,
    required this.done,
    required this.total,
    required this.currentName,
    this.cancelling = false,
  });
  final String phase;
  final int done;
  final int total;
  final String currentName;
  final bool cancelling;
}

class _BulkProgressController extends ValueNotifier<_BulkProgress> {
  _BulkProgressController() : super(const _BulkProgress(phase: '', done: 0, total: 0, currentName: ''));
  void update({required String phase, required int done, required int total, required String currentName}) =>
      value = _BulkProgress(phase: phase, done: done, total: total, currentName: currentName);
  void markCancelling() => value = _BulkProgress(
      phase: value.phase, done: value.done, total: value.total, currentName: value.currentName, cancelling: true);
}

Future<void> _showProgressDialog(
    BuildContext context, {
      required _BulkProgressController controller,
      required VoidCallback? onCancel,
    }) {
  // Note: deliberately NOT wrapped in PopScope/WillPopScope — this project
  // has no confirmed minimum Flutter version in scope for this change, and
  // barrierDismissible: false already blocks the common tap-outside-to-
  // dismiss path. A hardware back-button press during progress is a minor
  // edge case left as-is rather than risking an API that may not exist on
  // whatever Flutter version this project is pinned to.
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
      content: ValueListenableBuilder<_BulkProgress>(
        valueListenable: controller,
        builder: (_, p, __) {
          final pct = p.total == 0 ? 0.0 : p.done / p.total;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.phase.isEmpty ? 'Preparing…' : p.phase,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: p.total == 0 ? null : pct, minHeight: 6),
            ),
            const SizedBox(height: 10),
            Text(
              p.total == 0
                  ? 'Starting…'
                  : '${p.done} of ${p.total}'
                  '${p.currentName.isEmpty ? '' : ' — ${p.currentName}'}',
              style: const TextStyle(fontSize: 13, color: kTextSub),
            ),
            if (onCancel != null) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                // Deliberately does NOT pop this dialog itself — only sets
                // the cancel flag. The dialog is closed exactly once, by
                // the caller's `finally` block once the in-flight fetch
                // chunk actually returns (isCancelled is checked between
                // chunks, so this is a short wait, not an indefinite one).
                // Popping here too would double-pop the navigator once the
                // finally block also pops it, closing an unrelated route.
                child: Builder(builder: (_) {
                  final cancel = onCancel;
                  return TextButton(
                    onPressed: p.cancelling ? null : cancel,
                    child: Text(
                      p.cancelling ? 'Cancelling…' : 'Cancel',
                      style: const TextStyle(color: kTextSub, fontWeight: FontWeight.w600),
                    ),
                  );
                }),
              ),
            ],
          ]);
        },
      ),
    ),
  );
}

// ── Failure dialog ──────────────────────────────────────────────────────────

enum _FailureDecision { retry, continueWithout, cancel }

Future<_FailureDecision?> showBatchFailureDialog(
    BuildContext context, {
      required List<BatchLedgerFailure> failures,
      required int succeeded,
      required int total,
      required bool canRetry,
    }) {
  return showDialog<_FailureDecision>(
    context: context,
    useRootNavigator: true,
    builder: (dCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
      title: Text('${failures.length} of $total failed',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$succeeded retailer${succeeded == 1 ? '' : 's'} succeeded. The PDF will never be generated '
              'incomplete without your choice — pick how to proceed:',
              style: const TextStyle(fontSize: 13, color: kTextSub, height: 1.4)),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: failures.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final f = failures[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(f.retailerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: Text(f.reason, style: const TextStyle(fontSize: 11, color: kTextHint)),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dCtx, rootNavigator: true).pop(_FailureDecision.cancel),
          child: const Text('Cancel', style: TextStyle(color: kTextSub, fontWeight: FontWeight.w600)),
        ),
        if (canRetry)
          TextButton(
            onPressed: () => Navigator.of(dCtx, rootNavigator: true).pop(_FailureDecision.retry),
            child: const Text('Retry Failed', style: TextStyle(color: kNavy, fontWeight: FontWeight.w700)),
          ),
        TextButton(
          onPressed: () => Navigator.of(dCtx, rootNavigator: true).pop(_FailureDecision.continueWithout),
          child: Text('Continue Without Them', style: TextStyle(color: kError, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
}

// ── Layout + style pickers — visually mirrors report_table.dart's private
//    _showPrintSheetMenu/_showPrintStyleMenu so the trader sees the exact
//    same two-step flow for bulk as for a single retailer. Kept as
//    standalone functions here since the originals are private to
//    _ReportTableBlockState and this flow starts outside that widget. ─────

Future<PrintSheetSize?> pickPrintSheetSize(BuildContext context) {
  Widget sizeOption(IconData icon, String label, String sub, PrintSheetSize size) => ListTile(
    leading: Icon(icon, color: kNavy),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(sub),
    onTap: () => Navigator.of(context, rootNavigator: true).pop(size),
  );

  return showModalBottomSheet<PrintSheetSize>(
    context: context,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Select Print Layout', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
        sizeOption(Icons.description_outlined, 'Full Sheet Print', 'A4 — one full page per customer', PrintSheetSize.full),
        sizeOption(Icons.crop_7_5_outlined, 'Half Sheet Print', 'A5 — compact, saves paper for batch printing', PrintSheetSize.half),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

Future<ReportPrintStyle?> pickPrintStyleChoice(BuildContext context) {
  Widget styleOption(IconData icon, Color iconColor, String label, ReportPrintStyle style) => ListTile(
    leading: Icon(icon, color: iconColor),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    onTap: () => Navigator.of(context, rootNavigator: true).pop(style),
  );

  return showModalBottomSheet<ReportPrintStyle>(
    context: context,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Select Print Style', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
        styleOption(Icons.palette_outlined, kPrimary, 'Color', ReportPrintStyle.color),
        styleOption(Icons.contrast_outlined, Colors.black87, 'Black & White', ReportPrintStyle.blackAndWhite),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

// ── Retailer multi-select sheet ─────────────────────────────────────────────

typedef RetailerSelection = ({List<Map<String, dynamic>> retailers, bool isPrint});

Future<RetailerSelection?> showRetailerMultiSelectSheet(
    BuildContext context, {
      required List<Map<String, dynamic>> retailers,
    }) {
  return showModalBottomSheet<RetailerSelection>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => _RetailerMultiSelectSheet(retailers: retailers),
  );
}

class _RetailerMultiSelectSheet extends StatefulWidget {
  const _RetailerMultiSelectSheet({required this.retailers});
  final List<Map<String, dynamic>> retailers;

  @override
  State<_RetailerMultiSelectSheet> createState() => _RetailerMultiSelectSheetState();
}

class _RetailerMultiSelectSheetState extends State<_RetailerMultiSelectSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selected = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.retailers;
    return widget.retailers
        .where((r) => (r['shop_name'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  bool get _allFilteredSelected =>
      _filtered.isNotEmpty && _filtered.every((r) => _selected.contains(r['id']));

  void _toggleSelectAllFiltered() {
    setState(() {
      if (_allFilteredSelected) {
        for (final r in _filtered) _selected.remove(r['id']);
      } else {
        for (final r in _filtered) _selected.add(r['id'] as String);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final selectedRetailers = widget.retailers.where((r) => _selected.contains(r['id'])).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('Select Retailers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Text('${_selected.length} selected',
                  style: const TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search retailers…',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: kBgPage,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorderLight)),
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: filtered.isEmpty ? null : _toggleSelectAllFiltered,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Icon(_allFilteredSelected ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18, color: kNavy),
                  const SizedBox(width: 8),
                  Text(
                    _allFilteredSelected
                        ? 'Clear all${_query.isEmpty ? '' : ' (filtered)'}'
                        : 'Select all${_query.isEmpty ? '' : ' (filtered)'} (${filtered.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kNavy),
                  ),
                ]),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No matches', style: TextStyle(color: kTextHint)))
                  : ListView.separated(
                controller: scrollCtrl,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final id = r['id'] as String;
                  final checked = _selected.contains(id);
                  return CheckboxListTile(
                    value: checked,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(r['shop_name'] as String? ?? '—',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: selectedRetailers.isEmpty
                      ? null
                      : () => Navigator.of(context, rootNavigator: true)
                      .pop((retailers: selectedRetailers, isPrint: true)),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: Text('Print Selected (${_selected.length})'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kNavy,
                    side: const BorderSide(color: kNavy),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: selectedRetailers.isEmpty
                      ? null
                      : () => Navigator.of(context, rootNavigator: true)
                      .pop((retailers: selectedRetailers, isPrint: false)),
                  icon: const Icon(Icons.download_outlined, size: 18, color: Colors.white),
                  label: Text('Download PDF (${_selected.length})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNavy,
                    disabledBackgroundColor: kBorder,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusCard)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}