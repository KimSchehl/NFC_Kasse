import 'package:flutter/material.dart';

class PreferenceItem {
  final String key;
  final String profile;
  final dynamic value;

  const PreferenceItem({
    required this.key,
    required this.profile,
    required this.value,
  });

  factory PreferenceItem.fromJson(Map<String, dynamic> json) => PreferenceItem(
        key: json['key'] as String,
        profile: json['profile'] as String,
        value: json['value'],
      );
}

/// Immutable snapshot of all per-user preferences.
///
/// Layouts: key = 'layout.cat_{id}', profile = 'P' or 'L'
///   value = `List<int?>` where null is an intentional empty slot
///
/// Colors: key = 'product.color.{id}', profile = '*'
///   value = '#RRGGBB' hex string
class UserPreferences {
  final Map<String, Map<String, dynamic>> _store;

  const UserPreferences(this._store);

  static const empty = UserPreferences({});

  factory UserPreferences.fromList(List<PreferenceItem> items) {
    final store = <String, Map<String, dynamic>>{};
    for (final item in items) {
      store.putIfAbsent(item.key, () => {})[item.profile] = item.value;
    }
    return UserPreferences(store);
  }

  /// Returns the saved slot list for [categoryId] / [profile], or null if none.
  List<int?>? getLayout(int categoryId, String profile) {
    final raw = _store['layout.cat_$categoryId']?[profile];
    if (raw == null) return null;
    return (raw as List).map((e) => e as int?).toList();
  }

  /// Returns the per-user button color for [productId], or null for default.
  Color? getProductColor(int productId) {
    final raw = _store['product.color.$productId']?['*'];
    if (raw == null) return null;
    return _hexToColor(raw as String);
  }

  UserPreferences withLayout(int categoryId, String profile, List<int?> layout) {
    final key = 'layout.cat_$categoryId';
    final newStore = _deepCopy();
    newStore.putIfAbsent(key, () => {})[profile] = layout;
    return UserPreferences(newStore);
  }

  UserPreferences withProductColor(int productId, Color? color) {
    final key = 'product.color.$productId';
    final newStore = _deepCopy();
    if (color == null) {
      newStore.remove(key);
    } else {
      newStore[key] = {'*': _colorToHex(color)};
    }
    return UserPreferences(newStore);
  }

  Map<String, Map<String, dynamic>> _deepCopy() => Map.fromEntries(
        _store.entries.map((e) => MapEntry(e.key, Map<String, dynamic>.from(e.value))),
      );

  static Color? _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    final value = int.tryParse('FF$clean', radix: 16);
    return value != null ? Color(value) : null;
  }

  static String _colorToHex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
