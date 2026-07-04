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

  Future<ChipSummary> getSummary({String? periodIds}) async {
    final params = <String, dynamic>{};
    if (periodIds != null) params['period_ids'] = periodIds;
    final resp = await _client.dio.get('/api/customers/summary', queryParameters: params);
    return ChipSummary.fromJson(resp.data as Map<String, dynamic>);
  }
}
