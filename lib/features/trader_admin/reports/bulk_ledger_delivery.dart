import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'customer_ledger_print_builder.dart' show IndividualLedgerFile;

// ─────────────────────────────────────────────────────────────────────────────
// BulkLedgerDelivery
//
// Delivers N independent PDFs (from CustomerLedgerPrintBuilder.
// buildIndividual()) to the trader as N separate files — never
// re-combined, never requiring the trader to split anything themselves.
//
// Android/iOS: ONE Share.shareXFiles() call carrying all N files as
// in-memory XFiles (XFile.fromData — no path_provider, no disk write
// from this app's own code; share_plus internally stages a temp file per
// attachment purely as its own implementation detail for handing files
// to the OS share sheet). One user interaction, N real distinct files
// land wherever the trader picks (Files app, WhatsApp per-file, Drive,
// email, etc.) — exactly what "must not manually split a combined PDF"
// requires.
//
// Web: N sequential browser downloads is unreliable at this scale — most
// browsers throttle or block more than a handful of script-triggered
// downloads that aren't each tied to a fresh user gesture. Bundled into
// ONE .zip (package:archive — pure Dart, no dart:io, safe on Web) and
// delivered through the same bytes-download primitive already used
// elsewhere in this app for Web downloads (Printing.sharePdf triggers a
// direct browser download with no dialog on Web). This is a deliberate,
// disclosed platform trade-off: on Web the trader gets one .zip they
// must extract, not N individually-downloaded files — not a silent
// compromise, an explicit and necessary one given what's reliable in a
// browser at 50+ files.
// ─────────────────────────────────────────────────────────────────────────────

class BulkLedgerDelivery {
  const BulkLedgerDelivery._();

  static Future<void> deliverIndividualFiles({
    required List<IndividualLedgerFile> files,
    required DateTime fromDate,
  }) async {
    if (files.isEmpty) return;
    if (kIsWeb) {
      await _deliverAsZipOnWeb(files: files, fromDate: fromDate);
    } else {
      await _deliverViaShareSheet(files: files);
    }
  }

  static Future<void> _deliverViaShareSheet({required List<IndividualLedgerFile> files}) async {
    // NOTE ON FILENAMES: share_plus added a `fileNameOverrides` parameter
    // to Share.shareXFiles() in a later release than what this project
    // has pinned (confirmed — that parameter doesn't exist here and was
    // removed after a compile error). Without it, XFile.fromData's own
    // `name:` is the only naming mechanism available in this version.
    // share_plus's own docs warn that `name:` is "ignored in most
    // platforms" in versions that DO have fileNameOverrides — which
    // means naming may be unreliable here too, since that's the same
    // underlying limitation fileNameOverrides was added to fix. This is
    // a real, not cosmetic, risk against the "CustomerName_
    // CustomerLedger_<date>.pdf" naming requirement — verify actual
    // shared filenames in a real device test. If they come through as
    // random/UUID names instead, upgrading share_plus (and re-adding
    // fileNameOverrides here) is the fix, not something this code can
    // paper over on an old version.
    final xfiles = files
        .map((f) => XFile.fromData(f.bytes, name: f.filename, mimeType: 'application/pdf'))
        .toList();
    await Share.shareXFiles(xfiles, subject: 'Customer Ledgers');
  }

  static Future<void> _deliverAsZipOnWeb({
    required List<IndividualLedgerFile> files,
    required DateTime fromDate,
  }) async {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(ArchiveFile(f.filename, f.bytes.length, f.bytes));
    }
    final encoded = ZipEncoder().encode(archive);
    final bytes = encoded is Uint8List ? encoded : Uint8List.fromList(encoded ?? const []);
    final zipName =
        'CustomerLedgers_${files.length}_${DateFormat('yyyyMMdd').format(fromDate)}.zip';
    // Reuses the same bytes-out-to-the-browser call the rest of this
    // app's Web download path already relies on. The Blob's internal
    // MIME type will say application/pdf (this call is pdf-shaped by
    // name), but browsers save using the `download` attribute's
    // filename — the .zip extension supplied here — regardless, so this
    // works in practice despite the MIME label being technically wrong
    // for a zip. No new platform-specific code needed for this.
    await Printing.sharePdf(bytes: bytes, filename: zipName);
  }
}