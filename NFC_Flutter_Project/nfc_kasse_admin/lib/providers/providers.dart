import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backup_service.dart';
import '../services/bon_yaml_file.dart';
import '../services/config_env_file.dart';
import '../services/events_service.dart';
import '../services/network_info.dart';
import '../services/nfc_kasse_paths.dart';
import '../services/serial_ports.dart';
import '../services/service_control.dart';
import '../services/tenants_service.dart';

/// Polls the Windows service status every 3s so the Dashboard stays live
/// without the user having to manually refresh after clicking Start/Stop.
final serviceStatusProvider = StreamProvider<ServiceStatus>((ref) async* {
  while (true) {
    yield await ServiceControl.queryStatus();
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});

/// Bumped after a successful save to force configEnvProvider/bonLayoutProvider
/// to re-read from disk (e.g. after Start/Stop, which don't touch the files,
/// this isn't needed — only save actions bump it).
final configRefreshProvider = StateProvider<int>((ref) => 0);

final configEnvProvider = FutureProvider<ConfigEnvFile>((ref) {
  ref.watch(configRefreshProvider);
  return ConfigEnvFile.load(NfcKassePaths.configEnvPath);
});

final bonLayoutProvider = FutureProvider<BonLayout>((ref) {
  ref.watch(configRefreshProvider);
  return BonYamlFile.load(NfcKassePaths.bonYamlPath);
});

final serialPortsProvider = FutureProvider<List<SerialPortInfo>>((ref) => SerialPorts.list());

final serverAddressesProvider = FutureProvider<List<ServerAddress>>((ref) => NetworkInfo.localAddresses());

final backupRefreshProvider = StateProvider<int>((ref) => 0);

final backupsProvider = FutureProvider<List<BackupEntry>>((ref) {
  ref.watch(backupRefreshProvider);
  return BackupService.list();
});

final tenantsRefreshProvider = StateProvider<int>((ref) => 0);

final tenantsProvider = FutureProvider<List<TenantInfo>>((ref) {
  ref.watch(tenantsRefreshProvider);
  return TenantsService.list();
});

final eventsRefreshProvider = StateProvider<int>((ref) => 0);

final eventsOverviewProvider = FutureProvider<EventsOverview>((ref) {
  ref.watch(eventsRefreshProvider);
  return EventsService.overview();
});
