import 'dart:convert';

import 'package:flutter/material.dart';

import 'category_model.dart';
import '../utils/color_hex.dart';

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
///   value = `List<String?>` where null is an intentional empty slot
///
/// Color overrides: key = 'product.color.{id}', profile = '*'
///   value = '#RRGGBB' hex string; absent = use the product's default color
///
/// Category order: key = 'category.order', profile = '*'
///   value = `List<int>` of category ids in the user's sidebar order
///
/// Category color overrides: key = 'category.color.{id}', profile = '*'
///   value = '#RRGGBB' hex string; absent = use the category's default color
class UserPreferences {
  final Map<String, Map<String, dynamic>> _store;

  const UserPreferences(this._store);

  static const empty = UserPreferences({});

  /// Stable fingerprint of the whole store (keys sorted), so a background
  /// refresh only replaces state — and rebuilds the grid — on a real change.
  String get signature {
    final keys = _store.keys.toList()..sort();
    return jsonEncode([
      for (final k in keys)
        [k, (Map.fromEntries(_store[k]!.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))],
    ]);
  }

  factory UserPreferences.fromList(List<PreferenceItem> items) {
    final store = <String, Map<String, dynamic>>{};
    for (final item in items) {
      store.putIfAbsent(item.key, () => {})[item.profile] = item.value;
    }
    return UserPreferences(store);
  }

  /// Returns the saved slot list for [categoryId] / [profile], or null if none.
  List<String?>? getLayout(String categoryId, String profile) {
    final raw = _store['layout.cat_$categoryId']?[profile];
    if (raw == null) return null;
    return (raw as List).map((e) => e as String?).toList();
  }

  /// Returns this user's color override for [productId], or null if none is set.
  Color? getProductColor(String productId) {
    final raw = _store['product.color.$productId']?['*'];
    if (raw == null) return null;
    return hexToColor(raw as String);
  }

  Color? getCategoryColor(String categoryId) {
    final raw = _store['category.color.$categoryId']?['*'];
    if (raw == null) return null;
    return hexToColor(raw as String);
  }

  /// [categories] (server sort order) in this user's saved order; categories
  /// missing from the saved order (new ones) keep their server order at the end.
  List<CategoryModel> applyCategoryOrder(List<CategoryModel> categories) {
    final raw = _store['category.order']?['*'];
    if (raw == null) return categories;
    final rank = {for (final (i, id) in (raw as List).indexed) id as String: i};
    final known = categories.where((c) => rank.containsKey(c.id)).toList()
      ..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    return [...known, ...categories.where((c) => !rank.containsKey(c.id))];
  }

  UserPreferences withLayout(String categoryId, String profile, List<String?> layout) {
    final key = 'layout.cat_$categoryId';
    final newStore = _deepCopy();
    newStore.putIfAbsent(key, () => {})[profile] = layout;
    return UserPreferences(newStore);
  }

  UserPreferences withCategoryOrder(List<String> order) {
    final newStore = _deepCopy();
    newStore['category.order'] = {'*': order};
    return UserPreferences(newStore);
  }

  UserPreferences withProductColor(String productId, Color? color) =>
      _withColor('product.color.$productId', color);

  UserPreferences withCategoryColor(String categoryId, Color? color) =>
      _withColor('category.color.$categoryId', color);

  UserPreferences _withColor(String key, Color? color) {
    final newStore = _deepCopy();
    if (color == null) {
      newStore.remove(key);
    } else {
      newStore[key] = {'*': colorToHex(color)};
    }
    return UserPreferences(newStore);
  }

  Map<String, Map<String, dynamic>> _deepCopy() => Map.fromEntries(
        _store.entries.map((e) => MapEntry(e.key, Map<String, dynamic>.from(e.value))),
      );
}
