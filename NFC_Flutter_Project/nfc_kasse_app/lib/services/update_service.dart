import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final String downloadPath;

  const UpdateInfo({required this.version, required this.downloadPath});
}

class UpdateService {
  final Dio _dio;

  UpdateService(this._dio);

  /// Returns [UpdateInfo] when a newer version is available, otherwise null.
  /// Network errors are swallowed — a failed check is non-fatal.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final response = await _dio.get('/update/latest');
      final serverVersion = response.data['version'] as String;
      if (_isNewer(serverVersion, info.version)) {
        return UpdateInfo(
          version: serverVersion,
          downloadPath: response.data['download_path'] as String,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads the APK and opens the system installer.
  Future<void> downloadAndInstall(
    String downloadPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/nfc_kasse_update.apk';

    await _dio.download(
      downloadPath,
      savePath,
      onReceiveProgress: onProgress,
    );

    await OpenFile.open(savePath);
  }

  bool _isNewer(String server, String current) {
    final s = _toTuple(server);
    final c = _toTuple(current);
    for (int i = 0; i < 3; i++) {
      if (s[i] > c[i]) return true;
      if (s[i] < c[i]) return false;
    }
    return false;
  }

  List<int> _toTuple(String v) {
    final parts = v.split('.');
    return List.generate(3, (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
  }
}
