import '../models/user_preferences_model.dart';
import 'api_client.dart';

class PreferencesService {
  final ApiClient _client;
  PreferencesService(this._client);

  Future<UserPreferences> fetchAll() async {
    final resp = await _client.dio.get('/api/preferences/');
    final items = (resp.data as List)
        .map((j) => PreferenceItem.fromJson(j as Map<String, dynamic>))
        .toList();
    return UserPreferences.fromList(items);
  }

  Future<void> upsert(String key, String profile, dynamic value) async {
    await _client.dio.put(
      '/api/preferences/${Uri.encodeComponent(key)}',
      data: {'profile': profile, 'value': value},
    );
  }

  Future<void> delete(String key, {String? profile}) async {
    await _client.dio.delete(
      '/api/preferences/${Uri.encodeComponent(key)}',
      queryParameters: profile != null ? {'profile': profile} : null,
    );
  }
}
