import 'package:flutter/material.dart';
import 'package:rooster_trader/core/theme/app_theme.dart';

// ── AsyncStateView ─────────────────────────────────────────────────────────
class AsyncStateView extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.loading,
    required this.child,
    this.error,
    this.empty          = false,
    this.emptyIcon      = Icons.inbox_outlined,
    this.emptyMessage   = 'Nothing here yet',
    this.emptySub,
    this.onAction,
    this.actionLabel,
    this.onRetry,
    this.loadingMessage,
  });

  final bool      loading;
  final Widget    child;
  final String?   error;
  final bool      empty;
  final IconData  emptyIcon;
  final String    emptyMessage;
  final String?   emptySub;
  final VoidCallback? onAction;
  final String?   actionLabel;
  final VoidCallback? onRetry;
  final String?   loadingMessage;

  @override
  Widget build(BuildContext context) {
    if (loading) return _LoadingView(message: loadingMessage);
    if (error != null) return _ErrorView(error: error!, onRetry: onRetry);
    if (empty)  return _EmptyView(
      icon:        emptyIcon,
      message:     emptyMessage,
      sub:         emptySub,
      onAction:    onAction,
      actionLabel: actionLabel,
    );
    return child;
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(
          width: 36, height: 36,
          child: CircularProgressIndicator(color: kNavy, strokeWidth: 3),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(message!,
              style: const TextStyle(
                  fontSize: 15, color: kTextSub, fontWeight: FontWeight.w500)),
        ],
      ]),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, this.onRetry});
  final String       error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color:        kErrorBg,
            borderRadius: BorderRadius.circular(8),
            border:       Border.all(color: kError.withValues(alpha: 0.3)),
          ),
          child: const Center(
            child: Icon(Icons.error_outline_rounded, size: 32, color: kError),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Something went wrong',
            style: TextStyle(
                fontSize:   20,
                fontWeight: FontWeight.w700,
                color:      kTextMain)),
        const SizedBox(height: 8),
        Text(
          error
              .replaceAll('Exception: ', '')
              .replaceAll('PostgrestException(message: ', '')
              .replaceAll(')', ''),
          style: const TextStyle(
              fontSize: 15, color: kTextSub, height: 1.5),
          textAlign: TextAlign.center,
          maxLines:  4,
          overflow:  TextOverflow.ellipsis,
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon:      const Icon(Icons.refresh_rounded, size: 16),
            label:     const Text('Retry'),
          ),
        ],
      ]),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.message,
    this.sub,
    this.onAction,
    this.actionLabel,
  });
  final IconData     icon;
  final String       message;
  final String?      sub;
  final VoidCallback? onAction;
  final String?      actionLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color:        kNavy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border:       Border.all(color: kBorderLight),
          ),
          child: Center(
            child: Icon(icon, size: 36,
                color: kNavy.withValues(alpha: 0.35)),
          ),
        ),
        const SizedBox(height: 24),
        Text(message,
            style: const TextStyle(
                fontSize:   20,
                fontWeight: FontWeight.w700,
                color:      kTextSub),
            textAlign: TextAlign.center),
        if (sub != null) ...[
          const SizedBox(height: 8),
          Text(sub!,
              style: const TextStyle(
                  fontSize: 15, color: kTextHint, height: 1.5),
              textAlign: TextAlign.center),
        ],
        if (onAction != null) ...[
          const SizedBox(height: 28),
          ElevatedButton(
              onPressed: onAction,
              child:     Text(actionLabel ?? 'Add')),
        ],
      ]),
    ),
  );
}

// ── InlineLoader ────────────────────────────────────────────────────────────
class InlineLoader extends StatelessWidget {
  const InlineLoader({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width:  size, height: size,
    child:  CircularProgressIndicator(color: kNavy, strokeWidth: 2),
  );
}