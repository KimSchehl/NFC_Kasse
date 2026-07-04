import 'api_client.dart';

class HelpService {
  final ApiClient _client;
  HelpService(this._client);

  Future<int> requestHelp() async {
    final resp = await _client.dio.post('/api/help/request');
    return resp.data['id'] as int;
  }

  Future<void> respond(int requestId, String response) async {
    await _client.dio.post(
      '/api/help/$requestId/respond',
      data: {'response': response},
    );
  }

  Future<void> resolve(int requestId) async {
    await _client.dio.delete('/api/help/$requestId');
  }
}
