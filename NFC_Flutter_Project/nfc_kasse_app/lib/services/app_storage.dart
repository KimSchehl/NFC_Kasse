import 'package:shared_preferences/shared_preferences.dart';

/// Platform-agnostic key-value storage backed by SharedPreferences.
///
/// Replaces FlutterSecureStorage because the Web Crypto API (required for
/// encrypted storage) is only available in secure contexts (HTTPS/localhost).
/// This LAN app uses plain HTTP, so encrypted storage is not usable on web.
class AppStorage {
  final SharedPreferences _prefs;
  AppStorage(this._prefs);

  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }

  Future<String?> read({required String key}) async => _prefs.getString(key);

  Future<void> writeList({required String key, required List<String> value}) async =>
      _prefs.setStringList(key, value);

  Future<List<String>?> readList({required String key}) async => _prefs.getStringList(key);

  Future<void> delete({required String key}) async => _prefs.remove(key);

  Future<void> deleteAll() async => _prefs.clear();
}
