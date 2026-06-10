import '../models/chip_models.dart';
import 'api_client.dart';

class CustomerService {
  final ApiClient _client;
  CustomerService(this._client);

  Future<List<ChipModel>> getChips() async {
    final resp = await _client.dio.get('/api/customers/');
    return (resp.data as List)
        .map((j) => ChipModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ChipSummary> getSummary() async {
    final resp = await _client.dio.get('/api/customers/summary');
    return ChipSummary.fromJson(resp.data as Map<String, dynamic>);
  }
}
