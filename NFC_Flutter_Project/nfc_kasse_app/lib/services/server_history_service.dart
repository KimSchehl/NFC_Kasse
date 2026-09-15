import '../config/api_config.dart';
import 'app_storage.dart';

/// Recently-used server URLs, shown as suggestions in the login screen's
/// server-URL field so re-entering the same LAN address every time isn't
/// necessary. Most-recently-used first, capped at 5; [ApiConfig]'s
/// predefined addresses are always appended at the end too (even before
/// ever being used), so they're discoverable from the dropdown.
class ServerHistoryService {
  ServerHistoryService._();

  static const _key = 'recent_server_urls';
  static const _maxEntries = 5;

  /// Full list to show in the dropdown: actually-used history first (most
  /// recent first), then any predefined addresses not already in it.
  static Future<List<String>> load(AppStorage storage) async {
    final used = await storage.readList(key: _key) ?? const [];
    final result = [...used];
    for (final predefined in ApiConfig.predefinedServerUrls) {
      if (!result.contains(predefined)) result.add(predefined);
    }
    return result;
  }

  /// Call after a successful (or attempted) login with a non-empty URL —
  /// moves it to the front, dedupes, and trims to [_maxEntries].
  static Future<void> remember(AppStorage storage, String url) async {
    if (url.isEmpty) return;
    final used = await storage.readList(key: _key) ?? const [];
    final updated = [url, ...used.where((u) => u != url)];
    if (updated.length > _maxEntries) updated.removeRange(_maxEntries, updated.length);
    await storage.writeList(key: _key, value: updated);
  }
}
