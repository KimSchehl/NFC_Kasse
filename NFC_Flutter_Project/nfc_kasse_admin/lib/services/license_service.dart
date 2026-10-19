import 'backend_cli.dart';

/// Ergebnis der Prüfung eines Lizenzschlüssels (admin_cli.py license-check,
/// dieselbe Prüfung wie im Dienst).
class LicenseStatus {
  final String status;
  final String? validUntil;

  const LicenseStatus(this.status, this.validUntil);

  bool get valid => status == 'valid';

  String get label => switch (status) {
        'valid' => validUntil == null ? 'Gültig' : 'Gültig bis ${_date(validUntil!)}',
        'missing' => 'Kein Schlüssel eingetragen',
        'expired' => 'Abgelaufen am ${_date(validUntil ?? '')}',
        'wrong_installation' => 'Gehört zu einer anderen Installation',
        'wrong_feature' => 'Schlüssel für eine andere Funktion',
        _ => 'Ungültiger Schlüssel (falsch kopiert oder gefälscht)',
      };

  static String _date(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
  }
}

class LicenseService {
  LicenseService._();

  /// Prüft die übergebenen Schlüssel (auch noch nicht gespeicherte) gegen
  /// die Installations-ID dieser Installation. Funktion → Status.
  static Future<Map<String, LicenseStatus>> check(Map<String, String> keys) async {
    final json = await BackendCli.run([
      'license-check',
      for (final e in keys.entries) ...['--${e.key}', e.value],
    ]);
    final licenses = json['licenses'] as Map<String, dynamic>;
    return {
      for (final e in licenses.entries)
        e.key: LicenseStatus(
          (e.value as Map<String, dynamic>)['status'] as String,
          (e.value as Map<String, dynamic>)['valid_until'] as String?,
        ),
    };
  }
}
