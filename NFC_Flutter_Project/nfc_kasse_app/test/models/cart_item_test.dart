import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_kasse_app/models/cart_item.dart';
import 'package:nfc_kasse_app/models/product_model.dart';

const _beer = ProductModel(id: 1, name: 'Bier', price: 2.50, categoryId: 1, sortOrder: 0, active: true);
const _refund = ProductModel(id: 2, name: 'Pfand', price: -2.0, categoryId: 1, sortOrder: 0, active: true);

void main() {
  group('CartItem.subtotal', () {
    test('single quantity equals product price', () {
      const item = CartItem(product: _beer, quantity: 1);
      expect(item.subtotal, closeTo(2.50, 0.001));
    });

    test('multiple quantity multiplies price', () {
      const item = CartItem(product: _beer, quantity: 3);
      expect(item.subtotal, closeTo(7.50, 0.001));
    });

    test('negative price product gives negative subtotal', () {
      const item = CartItem(product: _refund, quantity: 1);
      expect(item.subtotal, closeTo(-2.0, 0.001));
    });

    test('negative price with quantity', () {
      const item = CartItem(product: _refund, quantity: 2);
      expect(item.subtotal, closeTo(-4.0, 0.001));
    });
  });

  group('CartItem.withQuantity', () {
    test('returns new item with updated quantity', () {
      const item = CartItem(product: _beer, quantity: 1);
      final updated = item.withQuantity(5);
      expect(updated.quantity, 5);
      expect(updated.product, _beer);
    });

    test('does not mutate the original', () {
      const item = CartItem(product: _beer, quantity: 1);
      item.withQuantity(10);
      expect(item.quantity, 1);
    });
  });
}
