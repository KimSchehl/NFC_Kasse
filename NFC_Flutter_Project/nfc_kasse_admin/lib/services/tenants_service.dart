import 'backend_cli.dart';

/// Ein Veranstalter: eine komplett eigene Kasse mit eigenen Benutzern,
/// Rechten, Warengruppen, Artikeln, Chips und Festen.
class TenantInfo {
  final int id;
  final String name;
  final bool active;
  final int users;
  final int categories;
  final int fests;

  /// Was gerade läuft: Festname, „Intern“ oder null.
  final String? running;

  const TenantInfo({
    required this.id,
    required this.name,
    required this.active,
    required this.users,
    required this.categories,
    required this.fests,
    this.running,
  });

  factory TenantInfo.fromJson(Map<String, dynamic> j) => TenantInfo(
        id: j['id'] as int,
        name: j['name'] as String,
        active: j['active'] as bool,
        users: j['users'] as int? ?? 0,
        categories: j['categories'] as int? ?? 0,
        fests: j['fests'] as int? ?? 0,
        running: j['running'] as String?,
      );
}

/// Veranstalter anlegen, umbenennen und wechseln — über admin_cli.py in
/// NfcKasseBackend.exe. Gewechselt wird nur ohne laufendes Fest, vorher
/// wird gesichert, danach sind alle Kassen abgemeldet.
class TenantsService {
  TenantsService._();

  static Future<List<TenantInfo>> list() async {
    final json = await BackendCli.run(['tenants']);
    return [for (final t in json['tenants'] as List) TenantInfo.fromJson(t as Map<String, dynamic>)];
  }

  static Future<TenantInfo> create({
    required String name,
    required String adminUser,
    required String adminPassword,
  }) async {
    final json = await BackendCli.run(
      ['tenant-create', '--name', name, '--admin-user', adminUser],
      stdin: adminPassword,
    );
    return TenantInfo.fromJson(json['tenant'] as Map<String, dynamic>);
  }

  static Future<void> activate(int id) => BackendCli.run(['tenant-activate', '$id']);

  static Future<void> rename(int id, String name) => BackendCli.run(['tenant-rename', '$id', '--name', name]);
}
