// Shared string extensions — import this instead of defining locally
extension StringEx on String {
  String capitalize() => isEmpty ? this : this[0].toUpperCase() + substring(1);
  String titleCase() => split('_').map((w) => w.capitalize()).join(' ');
}
