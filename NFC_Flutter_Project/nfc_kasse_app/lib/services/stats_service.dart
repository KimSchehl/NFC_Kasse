import '../models/stats_models.dart';
import 'api_client.dart';

/// Fetches revenue summaries, transaction lists, and export URLs.
class StatsService {
  final ApiClient _client;
  StatsService(this._client);

  Future<RevenueStats> getRevenue({String? from, String? to}) async {
    final params = <String, dynamic>{};
    if (from != null) params['period_start'] = from;
    if (to != null) params['period_end'] = to;
    final resp = await _client.dio.get('/api/stats/revenue', queryParameters: params);
    return RevenueStats.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<TransactionItem>> getTransactions({
    String? from,
    String? to,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (from != null) params['period_start'] = from;
    if (to != null) params['period_end'] = to;
    final resp = await _client.dio.get('/api/stats/transactions', queryParameters: params);
    return (resp.data['items'] as List)
        .map((j) => TransactionItem.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  String exportUrl() => '${_client.dio.options.baseUrl}/api/stats/export';
}
