import '../models/cart_item.dart';
import 'api_client.dart';

/// Calls the backend's /api/print/bon endpoint.
/// The backend handles booking to the BAR virtual chip AND printing.
class PrintService {
  final ApiClient _client;

  PrintService(this._client);

  /// Books [items] to the BAR chip and prints one ESC/POS bon per unit.
  /// Returns the number of bons printed.
  /// Throws [DioException] on network error, HTTP 503 if printer unreachable.
  Future<int> printBons(List<CartItem> items) async {
    final payload = {
      'items': items
          .map((i) => {'product_id': i.product.id, 'quantity': i.quantity})
          .toList(),
    };
    final response = await _client.dio.post('/api/print/bon', data: payload);
    final data = response.data as Map<String, dynamic>;
    return (data['bons_printed'] as num?)?.toInt() ?? 0;
  }
}
