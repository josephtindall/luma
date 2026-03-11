import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';

const _kStorageKey = 'luma_theme';

/// Possible theme preferences stored per-device.
enum ThemePreference { system, light, dark }

extension on ThemePreference {
  String get storageValue => switch (this) {
        ThemePreference.system => 'system',
        ThemePreference.light => 'light',
        ThemePreference.dark => 'dark',
      };

  ThemeMode get themeMode => switch (this) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      };
}

/// Manages per-device theme preference backed by localStorage.
/// Cycles: system → light → dark → system.
class ThemeNotifier extends ChangeNotifier {
  late ThemePreference _preference;

  ThemeNotifier() {
    _preference = _load();
  }

  ThemePreference get preference => _preference;
  ThemeMode get themeMode => _preference.themeMode;

  /// Cycles to the next preference and persists it.
  void cycle() {
    _preference = switch (_preference) {
      ThemePreference.system => ThemePreference.light,
      ThemePreference.light => ThemePreference.dark,
      ThemePreference.dark => ThemePreference.system,
    };
    _save(_preference);
    notifyListeners();
  }

  /// Sets a specific preference directly.
  void set(ThemePreference p) {
    if (_preference == p) return;
    _preference = p;
    _save(p);
    notifyListeners();
  }

  // ── localStorage helpers ────────────────────────────────────────────────

  static ThemePreference _load() {
    try {
      final storage = globalContext['localStorage'] as JSObject?;
      if (storage == null) return ThemePreference.system;
      final raw = (storage.callMethod<JSAny?>('getItem'.toJS, _kStorageKey.toJS)
              as JSString?)
          ?.toDart;
      return switch (raw) {
        'light' => ThemePreference.light,
        'dark' => ThemePreference.dark,
        _ => ThemePreference.system,
      };
    } catch (_) {
      return ThemePreference.system;
    }
  }

  static void _save(ThemePreference p) {
    try {
      final storage = globalContext['localStorage'] as JSObject?;
      if (storage == null) return;
      storage.callMethod<JSAny?>(
          'setItem'.toJS, _kStorageKey.toJS, p.storageValue.toJS);
    } catch (_) {}
  }
}
