/// UI display mode for the delivery agent app.
///
/// - [smart]: Full-featured ERP-style UI (default, existing).
/// - [simple]: Simplified elder-friendly workflow UI with larger text,
///             fewer data points, and bigger touch targets.
enum UiMode {
  smart('Smart Mode'),
  simple('Simple Mode');

  final String label;
  const UiMode(this.label);

  bool get isSmart  => this == UiMode.smart;
  bool get isSimple => this == UiMode.simple;

  static UiMode fromString(String? value) {
    return switch (value) {
      'simple' => UiMode.simple,
      _        => UiMode.smart,
    };
  }
}
