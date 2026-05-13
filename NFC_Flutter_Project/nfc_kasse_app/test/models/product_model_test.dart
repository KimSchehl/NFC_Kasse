import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_kasse_app/models/product_model.dart';

void main() {
  group('ProductModel.fromJson', () {
    test('parses all fields', () {
      final p = ProductModel.fromJson({
        'id': 1,
        'name': 'Bier',
        'price': 2.5,
        'category_id': 10,
        'sort_order': 3,
        'active': true,
        'color': null,
      });
      expect(p.id, 1);
      expect(p.name, 'Bier');
      expect(p.price, 2.5);
      expect(p.categoryId, 10);
      expect(p.sortOrder, 3);
      expect(p.active, true);
      expect(p.color, isNull);
    });

    test('parses hex color correctly', () {
      final p = ProductModel.fromJson({
        'id': 2, 'name': 'x', 'price': 1.0, 'category_id': 1,
        'sort_order': 0, 'active': true, 'color': '#A5D6A7',
      });
      expect(p.color, isNotNull);
      expect(p.colorHex, '#A5D6A7');
    });

    test('null color is preserved', () {
      final p = ProductModel.fromJson({
        'id': 3, 'name': 'x', 'price': 1.0, 'category_id': 1,
        'sort_order': 0, 'active': true, 'color': null,
      });
      expect(p.color, isNull);
      expect(p.colorHex, isNull);
    });

    test('sort_order defaults to 0 when missing', () {
      final p = ProductModel.fromJson({
        'id': 4, 'name': 'x', 'price': 1.0, 'category_id': 1,
        'active': true, 'color': null,
      });
      expect(p.sortOrder, 0);
    });

    test('active defaults to true when missing', () {
      final p = ProductModel.fromJson({
        'id': 5, 'name': 'x', 'price': 1.0, 'category_id': 1,
        'sort_order': 0, 'color': null,
      });
      expect(p.active, true);
    });
  });

  group('ProductModel.isRefund', () {
    test('negative price is a refund', () {
      const p = ProductModel(id: 1, name: 'Pfand', price: -2.0, categoryId: 1, sortOrder: 0, active: true);
      expect(p.isRefund, true);
    });

    test('positive price is not a refund', () {
      const p = ProductModel(id: 1, name: 'Bier', price: 2.5, categoryId: 1, sortOrder: 0, active: true);
      expect(p.isRefund, false);
    });

    test('zero price is not a refund', () {
      const p = ProductModel(id: 1, name: 'Gratis', price: 0.0, categoryId: 1, sortOrder: 0, active: true);
      expect(p.isRefund, false);
    });
  });

  group('ProductModel.copyWith', () {
    const base = ProductModel(id: 1, name: 'Bier', price: 2.5, categoryId: 1, sortOrder: 0, active: true);

    test('updates only the specified field', () {
      final copy = base.copyWith(name: 'Wasser');
      expect(copy.id, 1);
      expect(copy.name, 'Wasser');
      expect(copy.price, 2.5);
    });

    test('clears color when null is passed explicitly', () {
      final withColor = base.copyWith(color: const Color(0xFFA5D6A7));
      final cleared = withColor.copyWith(color: null);
      expect(cleared.color, isNull);
    });

    test('preserves color when color argument is omitted', () {
      final withColor = base.copyWith(color: const Color(0xFFA5D6A7));
      final copy = withColor.copyWith(name: 'Other');
      expect(copy.color, isNotNull);
    });
  });
}
