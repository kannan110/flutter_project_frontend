import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/ui_mode.dart';

/// Key used to persist the UI mode preference.
const _kPrefKey = 'ui_mode';

/// StateNotifier that manages the current [UiMode] and persists it
/// to [SharedPreferences] so it survives app restarts.
///
/// Initial state is [UiMode.smart] until the persisted value loads
/// asynchronously — this happens fast enough that the splash screen
/// (shown while auth loads) hides the transition.
final uiModeProvider = StateNotifierProvider<UiModeNotifier, UiMode>((_) {
  return UiModeNotifier();
});

class UiModeNotifier extends StateNotifier<UiMode> {
  UiModeNotifier() : super(UiMode.smart) {
    _load();
  }

  SharedPreferences? _prefs;

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs!.getString(_kPrefKey);
    if (saved != null && mounted) {
      state = UiMode.fromString(saved);
    }
  }

  /// Persist and switch to [mode]. Widgets watching [uiModeProvider]
  /// will rebuild automatically — no app restart needed.
  Future<void> setMode(UiMode mode) async {
    state = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kPrefKey, mode.name);
  }
}
