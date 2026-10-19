import 'dart:io';

class ServerAddress {
  final String interfaceName;
  final String ip;

  const ServerAddress(this.interfaceName, this.ip);
}

/// This PC's own LAN addresses — what a tablet would actually type into the
/// server field. HOST in config.env is usually 0.0.0.0 ("every interface"),
/// which isn't itself a reachable address, so this looks at the real network
/// interfaces instead.
class NetworkInfo {
  NetworkInfo._();

  // Virtual/irrelevant adapters (Hyper-V, VPN, VMware, container networking, …)
  // that would only confuse the admin if listed next to the real LAN address.
  static const _skipKeywords = [
    'virtual',
    'vethernet',
    'vmware',
    'virtualbox',
    'hyper-v',
    'loopback',
    'tunnel',
    'ppp',
    'bluetooth',
    'docker',
    'wsl',
  ];

  static Future<List<ServerAddress>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final result = <ServerAddress>[];
    for (final iface in interfaces) {
      final nameLower = iface.name.toLowerCase();
      if (_skipKeywords.any(nameLower.contains)) continue;
      for (final address in iface.addresses) {
        result.add(ServerAddress(iface.name, address.address));
      }
    }
    return result;
  }
}
