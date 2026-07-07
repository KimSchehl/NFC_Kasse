import '../models/kiosk_models.dart';
import 'api_client.dart';

class KioskService {
  final ApiClient _client;
  KioskService(this._client);

  Future<KioskChipInfo> getChipInfo(String nfcUid) async {
    final resp = await _client.dio.get('/api/kiosk/chip/$nfcUid');
    return KioskChipInfo.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> setChipName(String nfcUid, String name) async {
    await _client.dio.put('/api/kiosk/chip/$nfcUid/name', data: {'name': name});
  }
}
