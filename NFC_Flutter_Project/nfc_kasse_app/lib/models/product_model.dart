import 'package:flutter/material.dart';

/// Immutable product as returned by the API.
///
/// Products may have a negative [price] (e.g. "Pfand Rückgabe", "Aufladen").
/// The optional [color] is displayed as the tile background in [ProductGrid].
class ProductModel {
  final int id;
  final String name;
  final double price;
  final int categoryId;
  final int sortOrder;
  final bool active;
  final Color? color;
  final bool isPayout;
  final bool excludeFromStats;

  const ProductModel({
    required this.id,
    required this.name,
    required this.price,
    required this.categoryId,
    required this.sortOrder,
    required this.active,
    this.color,
    this.isPayout = false,
    this.excludeFromStats = false,
  });

  factory ProductModel.fromJson(Map<String, dynamic> j) => ProductModel(
        id: j['id'] as int,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        categoryId: j['category_id'] as int,
        sortOrder: j['sort_order'] as int? ?? 0,
        active: j['active'] as bool? ?? true,
        color: _hexToColor(j['color'] as String?),
        isPayout: j['is_payout'] as bool? ?? false,
        excludeFromStats: j['exclude_from_stats'] as bool? ?? false,
      );

  // Negative price = refund/topup (Pfand Rückgabe, Aufladen)
  bool get isRefund => price < 0;

  /// Converts [color] back to a `#RRGGBB` string for the API.
  /// Returns null when no custom color is set (backend stores NULL).
  String? get colorHex => color == null
      ? null
      : '#${(color!.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Creates a copy with selected fields overridden.
  ///
  /// [color] uses a sentinel default so callers can distinguish:
  ///   - omitting [color] → keep the existing color unchanged
  ///   - passing `color: null` → explicitly clear the color
  ProductModel copyWith({String? name, double? price, bool? active, bool? isPayout, bool? excludeFromStats, Object? color = _unset}) =>
      ProductModel(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        categoryId: categoryId,
        sortOrder: sortOrder,
        active: active ?? this.active,
        isPayout: isPayout ?? this.isPayout,
        excludeFromStats: excludeFromStats ?? this.excludeFromStats,
        color: color == _unset ? this.color : color as Color?,
      );

  // Sentinel used by copyWith to distinguish "not provided" from "set to null".
  static const _unset = Object();

  /// Parses a `#RRGGBB` hex string from the API into a Flutter [Color].
  /// Prefixes 0xFF for full opacity since the API never sends an alpha channel.
  static Color? _hexToColor(String? hex) {
    if (hex == null) return null;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}
