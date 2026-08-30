import '../models/pager_order_model.dart';
import 'api_client.dart';

/// CRUD for the operator's own pager orders (pager add-on).
class PagerService {
  final ApiClient _client;
  PagerService(this._client);

  Future<List<PagerOrderModel>> listOpen() async {
    final resp = await _client.dio.get('/api/pager/');
    return (resp.data as List)
        .map((j) => PagerOrderModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<PagerOrderModel> markDone(int id) async {
    final resp = await _client.dio.post('/api/pager/$id/done');
    return PagerOrderModel.fromJson(resp.data as Map<String, dynamic>);
  }
}
