import 'package:flutter/material.dart';

import '../utils/color_hex.dart';

/// Immutable product as returned by the API.
///
/// Products may have a negative [price] (e.g. "Pfand -", "Aufladen").
/// [defaultColor] is the button color every cashier sees; a cashier can
/// override it on their own device, see [UserPreferences].
class ProductModel {
  final int id;
  final String name;
  final double price;
  final int categoryId;
  final int sortOrder;
  final bool active;
  final bool isPayout;
  final bool isPfand;
  final bool excludeFromStats;
  final int points;
  final int? stock;
  final bool requiresPager;
  final int? groupId;
  final String? color;

  const ProductModel({
    required this.id,
    required this.name,
    required this.price,
    required this.categoryId,
    required this.sortOrder,
    required this.active,
    this.isPayout = false,
    this.isPfand = false,
    this.excludeFromStats = false,
    this.points = 0,
    this.stock,
    this.requiresPager = false,
    this.groupId,
    this.color,
  });

  factory ProductModel.fromJson(Map<String, dynamic> j) => ProductModel(
        id: j['id'] as int,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        categoryId: j['category_id'] as int,
        sortOrder: j['sort_order'] as int? ?? 0,
        active: j['active'] as bool? ?? true,
        isPayout: j['is_payout'] as bool? ?? false,
        isPfand: j['is_pfand'] as bool? ?? false,
        excludeFromStats: j['exclude_from_stats'] as bool? ?? false,
        points: j['points'] as int? ?? 0,
        stock: j['stock'] as int?,
        requiresPager: j['requires_pager'] as bool? ?? false,
        groupId: j['group_id'] as int?,
        color: j['color'] as String?,
      );

  Color? get defaultColor => hexToColor(color);

  // Negative price = refund/topup. Pfand articles are the exception: "Pfand -"
  // is a refund that needs no guthaben.topup right, see the backend's sales.py.
  bool get isRefund => price < 0;

  bool get isTopup => price < 0 && !isPayout && !isPfand;

  // null = not stock-tracked (unlimited)
  bool get isOutOfStock => stock != null && stock! <= 0;
}
