import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/session_provider.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────
// Trader Profile — More → Settings → Profile.
//
// Company Logo upload/change/remove is the headline feature here: the
// logo is stored in the public `trader-logos` Storage bucket under
// `<trader_id>/logo.<ext>` and the resulting public URL is written to
// traders.logo_url — the SAME column every PDF generator already reads
// (get_retailer_statement's header.company_logo, and every report's
// `header:` block). No new column, no new API — this screen is the only
// thing that was missing.
//
// If no logo is uploaded, logo_url stays null and every PDF continues to
// fall back to the existing text-based company header exactly as before
// — this screen only ever ADDS a logo, never removes the text fallback.
// ─────────────────────────────────────────────────────────────────────────

const _allowedExt = {'jpg', 'jpeg', 'png', 'webp'};

class TraderProfileScreen extends ConsumerStatefulWidget {
  const TraderProfileScreen({super.key});
  @override
  ConsumerState<TraderProfileScreen> createState() => _S();
}

class _S extends ConsumerState<TraderProfileScreen> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _trader;
  bool _loading = true;
  bool _uploadingLogo = false;

  late TextEditingController _companyCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _gstCtrl;
  bool _editingDetails = false;
  bool _savingDetails = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _gstCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      final t = await _c.from('traders').select('*').eq('id', tid as Object).maybeSingle();
      _companyCtrl = TextEditingController(text: t?['company_name'] as String? ?? '');
      _phoneCtrl = TextEditingController(text: t?['phone'] as String? ?? '');
      _emailCtrl = TextEditingController(text: t?['email'] as String? ?? '');
      _addressCtrl = TextEditingController(text: t?['address'] as String? ?? '');
      _gstCtrl = TextEditingController(text: t?['gst_number'] as String? ?? '');
      if (mounted) setState(() { _trader = t; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Robust, multi-layered image-type detection. Never trusts a single
  // signal — file extension parsing is fragile across platforms (Flutter
  // Web's XFile.path is a blob: URL with no extension at all; some
  // Android content:// URIs are also extension-less), so this checks, in
  // order: (1) the picker-reported filename, (2) the picker-reported MIME
  // type, (3) the actual file bytes' magic number — and only rejects if
  // ALL THREE come back inconclusive. Returns (extension, contentType) or
  // null if the file genuinely isn't a supported image.
  ({String ext, String contentType})? _detectImageType({
    required String? fileName,
    required String? mimeType,
    required Uint8List bytes,
  }) {
    // 1) Filename extension — case-insensitive, works whenever the picker
    // plugin reports a real name (image_picker does on every platform
    // via XFile.name, even when .path is a blob: URL on Web).
    if (fileName != null && fileName.contains('.')) {
      final ext = fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase();
      if (ext == 'jpg' || ext == 'jpeg') return (ext: 'jpg', contentType: 'image/jpeg');
      if (ext == 'png') return (ext: 'png', contentType: 'image/png');
      if (ext == 'webp') return (ext: 'webp', contentType: 'image/webp');
    }
    // 2) MIME type — image_picker's XFile.mimeType is often populated
    // even when the filename/extension isn't (e.g. some Android
    // content:// URIs, some Web browser/picker combinations).
    if (mimeType != null) {
      final m = mimeType.toLowerCase();
      if (m == 'image/jpeg' || m == 'image/jpg') return (ext: 'jpg', contentType: 'image/jpeg');
      if (m == 'image/png') return (ext: 'png', contentType: 'image/png');
      if (m == 'image/webp') return (ext: 'webp', contentType: 'image/webp');
    }
    // 3) Magic-number sniffing of the actual bytes — the last-resort,
    // always-correct signal when both metadata sources are missing.
    // Never reject a genuinely valid image just because a platform
    // didn't report a filename or MIME type.
    if (bytes.length >= 12) {
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return (ext: 'jpg', contentType: 'image/jpeg');
      }
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return (ext: 'png', contentType: 'image/png');
      }
      if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
          bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
        return (ext: 'webp', contentType: 'image/webp');
      }
    }
    return null;
  }

  Future<void> _pickAndUploadLogo() async {
    final picked = await showModalBottomSheet<XFile?>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from Gallery'),
            onTap: () async {
              final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
              if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop(f);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take Photo'),
            onTap: () async {
              final f = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
              if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop(f);
            },
          ),
        ]),
      ),
    );
    if (picked == null) return;

    // XFile.readAsBytes() — cross-platform (Android/iOS/Web/Windows/macOS).
    // dart:io's File(picked.path) does NOT work on Flutter Web at all
    // (no real filesystem — .path is a blob: URL there), which was a
    // second latent bug beyond the extension-detection one.
    final bytes = await picked.readAsBytes();

    // Explicit client-side size check ahead of the storage bucket's own
    // 2MB server-side limit — fails fast with a clear message instead of
    // uploading a too-large file just to have Storage reject it.
    const maxBytes = 2 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      if (mounted) showError(context, 'Image must be 2MB or smaller.');
      return;
    }

    final detected = _detectImageType(
      fileName: picked.name,
      mimeType: picked.mimeType,
      bytes: bytes,
    );

    // Audit logging — selected file name, detected extension/MIME, size,
    // and (once resolved below) the upload path, exactly as requested.
    debugPrint('[LogoUpload] name=${picked.name} path=${picked.path} '
        'reportedMime=${picked.mimeType} sizeBytes=${bytes.length} '
        'detected=${detected == null ? "none" : "${detected.ext} (${detected.contentType})"}');

    if (detected == null) {
      if (mounted) showError(context, 'Please choose a JPG, PNG, or WebP image.');
      return;
    }
    final ext = detected.ext;
    final contentType = detected.contentType;

    setState(() => _uploadingLogo = true);
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      // Fixed filename per trader (not timestamped) — a re-upload cleanly
      // replaces the old logo via upsert rather than accumulating old
      // files, and every existing PDF that already cached the old
      // logo_url keeps working (same URL, refreshed content) once
      // regenerated.
      final storagePath = '$tid/logo.$ext';
      debugPrint('[LogoUpload] uploading to $storagePath (contentType=$contentType)');
      await _c.storage.from('trader-logos').uploadBinary(
        storagePath, bytes,
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );
      final publicUrl = _c.storage.from('trader-logos').getPublicUrl(storagePath);
      // Cache-bust so the new logo shows immediately everywhere it's
      // already been fetched once (PDF previews, this screen, etc.)
      // instead of serving a stale cached image at the same URL.
      final bustedUrl = '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      await _c.from('traders').update({'logo_url': bustedUrl}).eq('id', tid as Object);
      if (mounted) {
        showSuccess(context, 'Logo updated ✓');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    final ok = await confirmDialog(context,
        title: 'Remove Logo',
        message: 'Remove your company logo? PDF documents will fall back to the text-based header.',
        confirmText: 'Remove', confirmColor: Colors.red);
    if (!ok) return;

    setState(() => _uploadingLogo = true);
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      // Best-effort cleanup of all known extensions for this trader — the
      // logo_url update below is what actually controls fallback
      // behavior, so a failed/partial storage cleanup here is harmless.
      for (final ext in _allowedExt) {
        try { await _c.storage.from('trader-logos').remove(['$tid/logo.$ext']); } catch (_) {}
      }
      await _c.from('traders').update({'logo_url': null}).eq('id', tid as Object);
      if (mounted) {
        showSuccess(context, 'Logo removed');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _saveDetails() async {
    if (_companyCtrl.text.trim().isEmpty) {
      showError(context, 'Company name is required.');
      return;
    }
    setState(() => _savingDetails = true);
    try {
      final tid = ref.read(appUserProvider).valueOrNull?.traderId;
      await _c.from('traders').update({
        'company_name': _companyCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'gst_number': _gstCtrl.text.trim().isEmpty ? null : _gstCtrl.text.trim(),
      }).eq('id', tid as Object);
      if (mounted) {
        showSuccess(context, 'Profile updated ✓');
        setState(() => _editingDetails = false);
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _savingDetails = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingList());
    final logoUrl = _trader?['logo_url'] as String?;

    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Profile'),
        actions: [
          if (!_editingDetails)
            TextButton.icon(
              onPressed: () => setState(() => _editingDetails = true),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          // ── Company Logo ──────────────────────────────────────────────
          const SectionHeader('COMPANY LOGO'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight),
              boxShadow: kCardShadow,
            ),
            child: Row(children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: kBgPage,
                  borderRadius: BorderRadius.circular(kRadiusInner),
                  border: Border.all(color: kBorderLight),
                ),
                clipBehavior: Clip.antiAlias,
                child: _uploadingLogo
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : (logoUrl != null && logoUrl.isNotEmpty)
                    ? Image.network(logoUrl, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                    const Icon(Icons.storefront_outlined, size: 30, color: kTextHint))
                    : const Icon(Icons.storefront_outlined, size: 30, color: kTextHint),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(logoUrl != null && logoUrl.isNotEmpty ? 'Logo uploaded' : 'No logo uploaded',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextMain)),
                  const SizedBox(height: 2),
                  const Text('JPG, PNG, or WebP · used on every PDF document',
                      style: TextStyle(fontSize: 11, color: kTextHint)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                      icon: const Icon(Icons.upload_outlined, size: 15),
                      label: Text(logoUrl != null && logoUrl.isNotEmpty ? 'Change' : 'Upload',
                          style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)),
                    ),
                    if (logoUrl != null && logoUrl.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _uploadingLogo ? null : _removeLogo,
                        icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
                        label: const Text('Remove', style: TextStyle(fontSize: 12, color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 34), side: const BorderSide(color: Colors.red)),
                      ),
                  ]),
                ]),
              ),
            ]),
          ),

          const SizedBox(height: 20),
          const SectionHeader('COMPANY DETAILS'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kBorderLight),
              boxShadow: kCardShadow,
            ),
            child: _editingDetails
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: _companyCtrl,
                  decoration: const InputDecoration(labelText: 'Company Name *')),
              const SizedBox(height: 10),
              TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile Number')),
              const SizedBox(height: 10),
              TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 10),
              TextField(controller: _addressCtrl, maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Address')),
              const SizedBox(height: 10),
              TextField(controller: _gstCtrl,
                  decoration: const InputDecoration(labelText: 'GSTIN (optional)')),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(
                    onPressed: () => setState(() => _editingDetails = false),
                    child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(
                    onPressed: _savingDetails ? null : _saveDetails,
                    child: _savingDetails
                        ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save'))),
              ]),
            ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InfoRow('Company', _trader?['company_name'] as String? ?? '—'),
              InfoRow('Mobile', _trader?['phone'] as String? ?? '—'),
              InfoRow('Email', _trader?['email'] as String? ?? '—'),
              InfoRow('Address', _trader?['address'] as String? ?? '—'),
              InfoRow('GSTIN', _trader?['gst_number'] as String? ?? '—'),
            ]),
          ),
        ],
      ),
    );
  }
}