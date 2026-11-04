import 'package:flutter/material.dart';
import '../../../core/theme/web_tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Shared dialogs — one radius (16), three widths (sm / md / lg), one header
// and button layout. Use these instead of building AlertDialog by hand.
// ═══════════════════════════════════════════════════════════════════════════

enum WebDialogSize { sm, md, lg }

double _width(WebDialogSize s) => switch (s) {
  WebDialogSize.sm => WebSize.dialogSm,
  WebDialogSize.md => WebSize.dialogMd,
  WebDialogSize.lg => WebSize.dialogLg,
};

final _dialogShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(WebRadius.dialog),
  side: const BorderSide(color: WebColors.border),
);

final _btnShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(WebRadius.button));

// ── Confirm ───────────────────────────────────────────────────────────────
class WebConfirmDialog {
  WebConfirmDialog._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel  = 'Cancel',
    IconData? icon,
    bool destructive = false,
  }) async {
    final color = destructive ? WebColors.error : WebColors.navy;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: WebColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: _dialogShape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: WebSize.dialogSm),
          child: Padding(
            padding: const EdgeInsets.all(WebSpace.xl),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.10)),
                  child: Icon(icon, size: 28, color: color),
                ),
                const SizedBox(height: WebSpace.lg),
              ],
              Text(title, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17,
                      fontWeight: FontWeight.w800, color: WebColors.text1)),
              const SizedBox(height: WebSpace.sm),
              Text(message, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5,
                      color: WebColors.text2, height: 1.45)),
              const SizedBox(height: WebSpace.xl),
              Row(children: [
                Expanded(child: SizedBox(height: 44, child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
                    foregroundColor: WebColors.text1,
                    side: const BorderSide(color: WebColors.border),
                    shape: _btnShape,
                  ),
                  child: Text(cancelLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ))),
                const SizedBox(width: WebSpace.md),
                Expanded(child: SizedBox(height: 44, child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
                      backgroundColor: color, shape: _btnShape),
                  child: Text(confirmLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ))),
              ]),
            ]),
          ),
        ),
      ),
    );
    return ok ?? false;
  }
}

// ── Form dialog shell ─────────────────────────────────────────────────────
class WebFormDialog extends StatelessWidget {
  const WebFormDialog({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.icon,
    this.size = WebDialogSize.md,
  });

  final String        title;
  final IconData?     icon;
  final Widget        child;
  final List<Widget>  actions;
  final WebDialogSize size;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: WebColors.surface,
    surfaceTintColor: Colors.transparent,
    shape: _dialogShape,
    child: SizedBox(
      width: _width(size),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(WebSpace.xl, 20, 12, 16),
          child: Row(children: [
            if (icon != null) ...[
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: WebColors.navySoft,
                  borderRadius: BorderRadius.circular(WebRadius.sm + 2),
                ),
                child: Icon(icon, size: 18, color: WebColors.navy),
              ),
              const SizedBox(width: WebSpace.md),
            ],
            Expanded(child: Text(title, style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800,
                color: WebColors.text1))),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 20,
                  color: WebColors.text2),
            ),
          ]),
        ),
        const Divider(height: 1, color: WebColors.border),
        Flexible(child: SingleChildScrollView(
          padding: const EdgeInsets.all(WebSpace.xl),
          child: child,
        )),
        const Divider(height: 1, color: WebColors.border),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: WebSpace.xl, vertical: WebSpace.lg),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: WebSpace.md),
              actions[i],
            ],
          ]),
        ),
      ]),
    ),
  );
}

// ── Buttons with the shared shape ─────────────────────────────────────────
class WebButton extends StatelessWidget {
  const WebButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = WebColors.navy,
    this.outlined = false,
  });
  final String       label;
  final VoidCallback? onPressed;
  final IconData?    icon;
  final Color        color;
  final bool         outlined;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: const TextStyle(
        fontSize: 13.5, fontWeight: FontWeight.w700));
    final pad = const EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    if (outlined) {
      final style = OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: color, padding: pad, shape: _btnShape,
        side: const BorderSide(color: WebColors.border),
      );
      return icon == null
          ? OutlinedButton(onPressed: onPressed, style: style, child: text)
          : OutlinedButton.icon(onPressed: onPressed, style: style,
              icon: Icon(icon, size: 18), label: text);
    }
    final style = FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: color, padding: pad, shape: _btnShape);
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: text)
        : FilledButton.icon(onPressed: onPressed, style: style,
            icon: Icon(icon, size: 18), label: text);
  }
}
