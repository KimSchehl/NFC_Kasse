import '../models/cart_item.dart';
import 'api_client.dart';

class DisplayService {
  final ApiClient _client;
  DisplayService(this._client);

  /// Pushes the current cart state to the backend customer display.
  /// Fire-and-forget — errors are silently ignored so the cashier is never blocked.
  Future<void> pushState({
    required List<CartItem> items,
    String? chipUid,
    double? currentBalance,
    double? balanceAfter,
  }) async {
    try {
      final data = <String, dynamic>{
        'items': items
            .map((i) => {
                  'name': i.product.name,
                  'price': i.product.price,
                  'quantity': i.quantity,
                })
            .toList(),
      };
      if (chipUid != null) data['chip_uid'] = chipUid;
      if (currentBalance != null) data['current_balance'] = currentBalance;
      if (balanceAfter != null) data['balance_after'] = balanceAfter;
      await _client.dio.post('/api/display/update', data: data);
    } catch (_) {}
  }
}
