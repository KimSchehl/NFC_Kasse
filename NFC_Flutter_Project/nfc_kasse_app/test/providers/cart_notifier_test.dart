import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_kasse_app/models/product_model.dart';
import 'package:nfc_kasse_app/providers/providers.dart';

const _beer = ProductModel(id: 1, name: 'Bier', price: 2.50, categoryId: 1, sortOrder: 0, active: true);
const _water = ProductModel(id: 2, name: 'Wasser', price: 1.50, categoryId: 1, sortOrder: 1, active: true);
const _refund = ProductModel(id: 3, name: 'Pfand', price: -2.0, categoryId: 1, sortOrder: 2, active: true);

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  group('initial state', () {
    test('cart starts empty', () {
      final notifier = container.read(cartProvider.notifier);
      expect(container.read(cartProvider), isEmpty);
      expect(notifier.total, 0.0);
      expect(notifier.productIds, isEmpty);
    });
  });

  group('addProduct', () {
    test('creates a new item', () {
      container.read(cartProvider.notifier).addProduct(_beer);
      final items = container.read(cartProvider);
      expect(items.length, 1);
      expect(items.first.quantity, 1);
      expect(items.first.product.id, 1);
    });

    test('increments quantity when adding the same product twice', () {
      container.read(cartProvider.notifier).addProduct(_beer);
      container.read(cartProvider.notifier).addProduct(_beer);
      final items = container.read(cartProvider);
      expect(items.length, 1);
      expect(items.first.quantity, 2);
    });

    test('keeps different products as separate entries', () {
      container.read(cartProvider.notifier).addProduct(_beer);
      container.read(cartProvider.notifier).addProduct(_water);
      expect(container.read(cartProvider).length, 2);
    });

    test('works with refund products (negative price)', () {
      container.read(cartProvider.notifier).addProduct(_refund);
      expect(container.read(cartProvider).first.subtotal, closeTo(-2.0, 0.001));
    });
  });

  group('total', () {
    test('sums all subtotals', () {
      final n = container.read(cartProvider.notifier);
      n.addProduct(_beer);  // 2.50
      n.addProduct(_beer);  // 2.50 → 5.00
      n.addProduct(_water); // 1.50 → 6.50
      expect(n.total, closeTo(6.50, 0.001));
    });

    test('is zero when cart is empty', () {
      expect(container.read(cartProvider.notifier).total, 0.0);
    });

    test('reduces when a refund product is added', () {
      final n = container.read(cartProvider.notifier);
      n.addProduct(_beer);   // 2.50
      n.addProduct(_refund); // -2.00 → 0.50
      expect(n.total, closeTo(0.50, 0.001));
    });
  });

  group('productIds', () {
    test('expands quantity into repeated IDs', () {
      final n = container.read(cartProvider.notifier);
      n.addProduct(_beer);
      n.addProduct(_beer);
      n.addProduct(_water);
      expect(n.productIds, [1, 1, 2]);
    });

    test('is empty when cart is empty', () {
      expect(container.read(cartProvider.notifier).productIds, isEmpty);
    });
  });

  group('removeItem', () {
    test('removes item by product ID', () {
      final n = container.read(cartProvider.notifier);
      n.addProduct(_beer);
      n.addProduct(_water);
      n.removeItem(1);
      final items = container.read(cartProvider);
      expect(items.length, 1);
      expect(items.first.product.id, 2);
    });

    test('is a no-op for an unknown product ID', () {
      container.read(cartProvider.notifier).addProduct(_beer);
      container.read(cartProvider.notifier).removeItem(999);
      expect(container.read(cartProvider).length, 1);
    });
  });

  group('clear', () {
    test('empties the cart', () {
      final n = container.read(cartProvider.notifier);
      n.addProduct(_beer);
      n.addProduct(_water);
      n.clear();
      expect(container.read(cartProvider), isEmpty);
      expect(n.total, 0.0);
    });

    test('is safe to call on an empty cart', () {
      container.read(cartProvider.notifier).clear();
      expect(container.read(cartProvider), isEmpty);
    });
  });
}
