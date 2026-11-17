import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Finds NFC-Kasse backends on the LAN via DNS-SD/mDNS: the Windows service
/// advertises `_nfc-kasse._tcp` (backend/service_main.py `_advertise`), plus
/// a `/health` sweep of the device's own subnet where multicast is blocked.
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
    await Future.wait([_scanMdns(onFound, duration), _probeSubnet(onFound)]);
  }

  static Future<void> _scanMdns(void Function(String url) onFound, Duration duration) async {
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

  /// Fallback for networks that drop multicast (guest Wi-Fi, some hotspots):
  /// asks every host of this device's own /24 for `/health` on port 8000.
  // shortcut: default port and /24 only; a server on another port or a wider
  // subnet is still found via mDNS or typed in.
  static Future<void> _probeSubnet(void Function(String url) onFound) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1500);
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final prefixes = {
        for (final iface in interfaces)
          for (final a in iface.addresses)
            if (_isPrivateLan(a.address)) a.address.substring(0, a.address.lastIndexOf('.')),
      };
      await Future.wait([
        for (final prefix in prefixes)
          for (var host = 1; host < 255; host++) _probe(client, 'http://$prefix.$host:8000', onFound),
      ]);
    } catch (e, st) {
      AppLogger.warning('Server-Suche (Subnetz) fehlgeschlagen', logger: 'discovery', error: e, stackTrace: st);
    } finally {
      client.close(force: true);
    }
  }

  // Private ranges only, so a mobile-data interface isn't swept.
  static bool _isPrivateLan(String ip) {
    final p = ip.split('.').map(int.parse).toList();
    return p[0] == 10 || (p[0] == 172 && p[1] >= 16 && p[1] < 32) || (p[0] == 192 && p[1] == 168);
  }

  static Future<void> _probe(HttpClient client, String base, void Function(String url) onFound) async {
    try {
      final request = await client.getUrl(Uri.parse('$base/health'));
      final response = await request.close().timeout(const Duration(seconds: 2));
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 2));
      // `catalog_rev` tells an NFC-Kasse apart from any other server on :8000.
      if (response.statusCode == 200 && body.contains('"catalog_rev"')) onFound(base);
    } catch (_) {
      // nobody there
    }
  }
}
