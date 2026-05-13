import 'product_model.dart';

/// An immutable line item in the cart: one product and how many of it.
///
/// All mutations return a new instance — never modify an existing [CartItem].
class CartItem {
  final ProductModel product;
  final int quantity;

  const CartItem({required this.product, required this.quantity});

  double get subtotal => product.price * quantity;

  /// Returns a copy with [quantity] updated, leaving [product] unchanged.
  CartItem withQuantity(int q) => CartItem(product: product, quantity: q);
}
