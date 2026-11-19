import 'api_client.dart';

class HelpService {
  final ApiClient _client;
  HelpService(this._client);

  Future<String> requestHelp() async {
    final resp = await _client.dio.post('/api/help/request');
    return resp.data['id'] as String;
  }

  Future<void> respond(String requestId, String response) async {
    await _client.dio.post(
      '/api/help/$requestId/respond',
      data: {'response': response},
    );
  }

  Future<void> resolve(String requestId) async {
    await _client.dio.delete('/api/help/$requestId');
  }
}
