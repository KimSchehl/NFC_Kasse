import '../models/customer_model.dart';
import 'api_client.dart';

/// Handles NFC balance queries, bookings, and cancellations.
class SalesService {
  final ApiClient _client;
  SalesService(this._client);

  Future<CustomerModel> getBalance(String nfcUid) async {
    final resp = await _client.dio.get('/api/sales/balance/$nfcUid');
    return CustomerModel.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Creates a booking for [nfcUid] with the given list of product IDs.
  ///
  /// [productIds] may contain repeated IDs — each occurrence is a separate
  /// sale row (quantity 2 of the same product → `[id, id]`). The server
  /// de-duplicates for the DB lookup but processes the full list for pricing.
  Future<Map<String, dynamic>> book(String nfcUid, List<int> productIds) async {
    final resp = await _client.dio.post('/api/sales/', data: {
      'nfc_uid': nfcUid,
      'product_ids': productIds,
    });
    return resp.data as Map<String, dynamic>;
  }

  /// Cancels a single sale row by ID and refunds its price to the customer.
  /// The cancel dialog calls this once per sale_id in the booking.
  Future<Map<String, dynamic>> cancelSale(int saleId) async {
    final resp = await _client.dio.post('/api/sales/$saleId/cancel');
    return resp.data as Map<String, dynamic>;
  }
}
