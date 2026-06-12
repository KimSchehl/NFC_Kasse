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
        'is_payout': false,
        'exclude_from_stats': false,
      });
      expect(p.id, 1);
      expect(p.name, 'Bier');
      expect(p.price, 2.5);
      expect(p.categoryId, 10);
      expect(p.sortOrder, 3);
      expect(p.active, true);
      expect(p.isPayout, false);
      expect(p.excludeFromStats, false);
    });

    test('sort_order defaults to 0 when missing', () {
      final p = ProductModel.fromJson({
        'id': 4, 'name': 'x', 'price': 1.0, 'category_id': 1, 'active': true,
      });
      expect(p.sortOrder, 0);
    });

    test('active defaults to true when missing', () {
      final p = ProductModel.fromJson({
        'id': 5, 'name': 'x', 'price': 1.0, 'category_id': 1, 'sort_order': 0,
      });
      expect(p.active, true);
    });

    test('isPayout defaults to false when missing', () {
      final p = ProductModel.fromJson({
        'id': 6, 'name': 'x', 'price': 1.0, 'category_id': 1,
      });
      expect(p.isPayout, false);
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
}
