import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Finds NFC-Kasse backends on the LAN via DNS-SD/mDNS: the Windows service
/// advertises `_nfc-kasse._tcp` (backend/service_main.py `_advertise`).
/// Not on web — browsers can't do mDNS, and the web build already knows its
/// server (its own origin, see main.dart).
class ServerDiscoveryService {
  ServerDiscoveryService._();

  static const _type = '_nfc-kasse._tcp';

  /// Scans for [duration] and calls [onFound] with `http://<ipv4>:<port>`
  /// for every address a found server reports. Never throws — a failed scan
  /// just finds nothing, the dropdown history still works.
  static Future<void> scan(
    void Function(String url) onFound, {
    Duration duration = const Duration(seconds: 5),
  }) async {
    if (kIsWeb) return;
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? sub;
    try {
      final d = discovery = BonsoirDiscovery(type: _type);
      await d.initialize();
      sub = d.eventStream!.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            d.serviceResolver.resolveService(event.service);
          case BonsoirDiscoveryServiceResolvedEvent():
            // IPv4 only: IPv6 link-local addresses would need a zone id in the URL.
            for (final ip in event.service.hostAddresses.where((a) => !a.contains(':'))) {
              onFound(Uri(scheme: 'http', host: ip, port: event.service.port).toString());
            }
          default:
        }
      });
      await d.start();
      await Future<void>.delayed(duration);
    } catch (e, st) {
      AppLogger.warning('Server-Suche (mDNS) fehlgeschlagen', logger: 'discovery', error: e, stackTrace: st);
    } finally {
      await sub?.cancel();
      try {
        await discovery?.stop();
      } catch (_) {}
    }
  }
}
