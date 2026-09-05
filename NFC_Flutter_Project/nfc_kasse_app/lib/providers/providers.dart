import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide LogLevel;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import '../services/app_storage.dart';
import '../models/admin_category_products.dart';
import '../models/cart_item.dart';
import '../models/category_model.dart';
import '../models/customer_model.dart';
import '../models/help_model.dart';
import '../models/pager_order_model.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';
import '../models/user_preferences_model.dart';
import '../services/api_client.dart';
import '../services/app_logger.dart';
import '../services/auth_service.dart';
import '../services/ble_nfc_service.dart';
import '../services/customer_service.dart';
import '../services/help_service.dart';
import '../services/logs_service.dart';
import '../services/notification_service.dart';
import '../services/pager_service.dart';
import '../services/preferences_service.dart';
import '../services/display_service.dart';
import '../services/kiosk_service.dart';
import '../services/print_service.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';
import '../services/stats_service.dart';
import '../services/update_service.dart';
import '../services/users_service.dart';
import '../utils/formatters.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

// Overridden in main() with a SharedPreferences-backed AppStorage instance.
final storageProvider = Provider<AppStorage>(
  (_) => throw StateError('storageProvider must be overridden in main()'),
);

/// The backend URL the user configured on the login screen.
/// Initialised from secure storage in main() so it survives app restarts.
final serverUrlProvider = StateProvider<String>(
  (ref) => ApiConfig.defaultBaseUrl,
);

/// Recreated automatically whenever [serverUrlProvider] changes, so a URL
/// update on the login screen takes effect for all subsequent requests.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(storageProvider),
    baseUrl: ref.watch(serverUrlProvider),
  );
});

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final authServiceProvider = Provider(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);
final salesServiceProvider = Provider(
  (ref) => SalesService(ref.watch(apiClientProvider)),
);
final productServiceProvider = Provider(
  (ref) => ProductService(ref.watch(apiClientProvider)),
);
final statsServiceProvider = Provider(
  (ref) => StatsService(ref.watch(apiClientProvider)),
);
final usersServiceProvider = Provider(
  (ref) => UsersService(ref.watch(apiClientProvider)),
);
final updateServiceProvider = Provider(
  (ref) => UpdateService(ref.watch(apiClientProvider).dio),
);
final customerServiceProvider = Provider(
  (ref) => CustomerService(ref.watch(apiClientProvider)),
);
final printServiceProvider = Provider(
  (ref) => PrintService(ref.watch(apiClientProvider)),
);
final pagerServiceProvider = Provider(
  (ref) => PagerService(ref.watch(apiClientProvider)),
);
final displayServiceProvider = Provider(
  (ref) => DisplayService(ref.watch(apiClientProvider)),
);
final kioskServiceProvider = Provider(
  (ref) => KioskService(ref.watch(apiClientProvider)),
);
final preferencesServiceProvider = Provider(
  (ref) => PreferencesService(ref.watch(apiClientProvider)),
);
final helpServiceProvider = Provider(
  (ref) => HelpService(ref.watch(apiClientProvider)),
);
final logsServiceProvider = Provider(
  (ref) => LogsService(ref.watch(apiClientProvider)),
);
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

/// Polls /health every 10 seconds and emits true/false.
/// Restarts automatically when the server URL changes.
///
/// Piggybacks the device's log-level pickup on the same poll: every response
/// carries the server's current forced level for this device_id (or null),
/// which is handed to [LoggingNotifier.applyRemoteLevel]. No separate polling
/// mechanism needed — this one was already running every 10s for every
/// logged-in and logged-out client alike.
final connectionStatusProvider = StreamProvider<bool>((ref) {
  final client = ref.watch(apiClientProvider);
  final controller = StreamController<bool>.broadcast();

  Future<void> poll() async {
    while (!controller.isClosed) {
      bool ok;
      try {
        final response = await client.dio.get(
          '/health',
          queryParameters: {
            'device_id': ref.read(deviceIdProvider),
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
            'label': ?ref.read(deviceLabelProvider),
          },
          options: Options(
            sendTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 3),
          ),
        );
        ref
            .read(loggingProvider.notifier)
            .applyRemoteLevel(response.data['log_level'] as String?);
        // Fire-and-forget: piggybacks the product-catalog change check on
        // the same 10s cadence without blocking this stream on its result.
        unawaited(ref.read(productSyncProvider.notifier).checkForChanges());
        // Same piggyback for the pager add-on's own small list — gated so a
        // deployment with the feature off never calls the (unregistered,
        // 404ing) route.
        if (ref.read(authProvider).valueOrNull?.pagerEnabled ?? false) {
          unawaited(ref.read(pagerListProvider.notifier).refresh());
        }
        ok = true;
      } catch (_) {
        ok = false;
      }
      if (!controller.isClosed) controller.add(ok);
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  poll();
  ref.onDispose(controller.close);
  return controller.stream;
});

/// Current app version string (e.g. "1.0.0"), read from the device at runtime.
final appVersionProvider = FutureProvider<String>(
  (_) async => (await PackageInfo.fromPlatform()).version,
);

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// Manages the authentication state for the whole app.
///
/// `build()` runs on app start: if a token is found in secure storage, it
/// silently restores the session by calling `/api/auth/me`. On failure (expired
/// token, network error) it clears storage and returns null → [LoginScreen] is shown.
class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    final client = ref.read(apiClientProvider);
    if (!await client.hasStoredTokens()) return null;
    try {
      final user = await ref.read(authServiceProvider).fetchMe();
      unawaited(ref.read(userPrefsProvider.notifier).load());
      unawaited(ref.read(helpProvider.notifier).connect());
      return user;
    } catch (_) {
      await client.clearTokens();
      return null;
    }
  }

  Future<void> login(String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).login(username, password),
    );
    if (state.hasValue && state.value != null) {
      unawaited(ref.read(userPrefsProvider.notifier).load());
      unawaited(ref.read(helpProvider.notifier).connect());
      ref.invalidate(categoriesProvider);
      ref.invalidate(productsProvider);
    }
  }

  /// Re-fetches `/me` and applies it to state, without going through the
  /// login flow — used after an action that changes the current user's own
  /// server-side permissions/categories (e.g. creating a category as a
  /// manager), so UI derived from it (like `canManageAnyArticles`, which
  /// otherwise only updates on next login/cold start) reflects it right away.
  Future<void> refreshFromServer() async {
    try {
      final user = await ref.read(authServiceProvider).fetchMe();
      state = AsyncData(user);
    } catch (_) {
      // Not critical — keep the current (stale) state; next login/cold
      // start will pick up the correct value anyway.
    }
  }

  Future<void> logout() async {
    final token = await ref.read(storageProvider).read(key: 'refresh_token') ?? '';
    await ref.read(authServiceProvider).logout(token);
    ref.read(userPrefsProvider.notifier).reset();
    ref.read(helpProvider.notifier).disconnect();
    ref.invalidate(categoriesProvider);
    ref.invalidate(productsProvider);
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(
  AuthNotifier.new,
);

// ---------------------------------------------------------------------------
// User Preferences
// ---------------------------------------------------------------------------

class UserPrefsNotifier extends Notifier<UserPreferences> {
  @override
  UserPreferences build() => UserPreferences.empty;

  Future<void> load() async {
    try {
      state = await ref.read(preferencesServiceProvider).fetchAll();
    } catch (_) {
      // Non-fatal: keep empty prefs, grid falls back to server order.
    }
  }

  void reset() => state = UserPreferences.empty;

  Future<void> setLayout(int categoryId, String profile, List<int?> layout) async {
    state = state.withLayout(categoryId, profile, layout);
    unawaited(ref
        .read(preferencesServiceProvider)
        .upsert('layout.cat_$categoryId', profile, layout));
  }

  Future<void> setProductColor(int productId, Color? color) async {
    state = state.withProductColor(productId, color);
    if (color == null) {
      unawaited(ref
          .read(preferencesServiceProvider)
          .delete('product.color.$productId', profile: '*'));
    } else {
      final hex =
          '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      unawaited(ref
          .read(preferencesServiceProvider)
          .upsert('product.color.$productId', '*', hex));
    }
  }
}

final userPrefsProvider = NotifierProvider<UserPrefsNotifier, UserPreferences>(
  UserPrefsNotifier.new,
);

// ---------------------------------------------------------------------------
// Help / Notfall
// ---------------------------------------------------------------------------

@immutable
class HelpState {
  final HelpRequest? myRequest;
  final List<HelpRequest> allRequests;
  final bool wsConnected;

  const HelpState({
    this.myRequest,
    this.allRequests = const [],
    this.wsConnected = false,
  });

  HelpState copyWith({
    HelpRequest? Function()? myRequest,
    List<HelpRequest>? allRequests,
    bool? wsConnected,
  }) =>
      HelpState(
        myRequest: myRequest != null ? myRequest() : this.myRequest,
        allRequests: allRequests ?? this.allRequests,
        wsConnected: wsConnected ?? this.wsConnected,
      );
}

class HelpNotifier extends Notifier<HelpState> {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;
  bool _shouldReconnect = false;

  @override
  HelpState build() => const HelpState();

  Future<void> connect() async {
    _shouldReconnect = true;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    final storage = ref.read(storageProvider);
    final serverUrl = ref.read(serverUrlProvider);
    final token = await storage.read(key: 'access_token');
    if (token == null || !_shouldReconnect) return;

    final wsBase = serverUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final wsUrl = '$wsBase/api/help/ws?token=${Uri.encodeComponent(token)}';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      // WebSocketChannel.connect() returns synchronously before the
      // connection is actually established; a failure only ever surfaces
      // via this `ready` future. Without awaiting it here, a failed
      // connection attempt becomes an unhandled Future rejection instead of
      // being caught by this try/catch.
      await _channel!.ready;
      state = state.copyWith(wsConnected: true);

      _sub = _channel!.stream.listen(
        _handleMessage,
        onDone: () { if (_shouldReconnect) _scheduleReconnect(); },
        onError: (_) { if (_shouldReconnect) _scheduleReconnect(); },
        cancelOnError: true,
      );

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
    } catch (_) {
      state = state.copyWith(wsConnected: false);
      if (_shouldReconnect) _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    state = state.copyWith(wsConnected: false);
    Future.delayed(const Duration(seconds: 5), () {
      if (_shouldReconnect) _doConnect();
    });
  }

  void _handleMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String;

      switch (type) {
        case 'pong':
          break;

        case 'init':
          final requests = (msg['requests'] as List)
              .map((j) => HelpRequest.fromJson(j as Map<String, dynamic>))
              .toList();
          final myId = ref.read(authProvider).valueOrNull?.id;
          final mine = requests.where((r) => r.requesterId == myId).firstOrNull;
          state = HelpState(
            allRequests: requests,
            myRequest: mine,
            wsConnected: true,
          );

        case 'new_request':
          final req = HelpRequest.fromJson(
              msg['request'] as Map<String, dynamic>);
          final user = ref.read(authProvider).valueOrNull;
          // Skip if already added via optimistic update in requestHelp().
          final alreadyKnown = state.allRequests.any((r) => r.id == req.id);
          if (!alreadyKnown) {
            HelpState next = state.copyWith(
                allRequests: [...state.allRequests, req]);
            if (req.requesterId == user?.id) {
              next = next.copyWith(myRequest: () => req);
            }
            state = next;
          }
          if (user != null && user.hasPermission('help.receive')) {
            unawaited(ref
                .read(notificationServiceProvider)
                .showHelpAlert(req.id, req.requesterName));
          }

        case 'new_response':
          final requestId = msg['request_id'] as int;
          final resp =
              HelpResponse.fromJson(msg['response'] as Map<String, dynamic>);
          final updated = state.allRequests.map((r) {
            if (r.id != requestId) return r;
            final list = [...r.responses];
            final idx = list.indexWhere((x) => x.responderId == resp.responderId);
            if (idx >= 0) {
              list[idx] = resp;
            } else {
              list.add(resp);
            }
            return r.copyWith(responses: list);
          }).toList();
          HelpRequest? mine = state.myRequest;
          if (mine != null && mine.id == requestId) {
            final list = [...mine.responses];
            final idx = list.indexWhere((x) => x.responderId == resp.responderId);
            if (idx >= 0) {
              list[idx] = resp;
            } else {
              list.add(resp);
            }
            mine = mine.copyWith(responses: list);
          }
          state = state.copyWith(allRequests: updated, myRequest: () => mine);

        case 'resolved':
          final requestId = msg['request_id'] as int;
          final remaining =
              state.allRequests.where((r) => r.id != requestId).toList();
          HelpRequest? mine = state.myRequest;
          if (mine?.id == requestId) mine = null;
          state = state.copyWith(
              allRequests: remaining, myRequest: () => mine);
          unawaited(ref
              .read(notificationServiceProvider)
              .cancelAlert(requestId));
      }
    } catch (_) {}
  }

  void disconnect() {
    _shouldReconnect = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    state = const HelpState();
  }

  Future<void> requestHelp() async {
    final id = await ref.read(helpServiceProvider).requestHelp();
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final req = HelpRequest(
      id: id,
      requesterId: user.id,
      requesterName: user.displayLabel,
    );
    state = state.copyWith(
      allRequests: [...state.allRequests, req],
      myRequest: () => req,
    );
  }

  Future<void> respond(int requestId, String response) async {
    await ref.read(helpServiceProvider).respond(requestId, response);
  }

  Future<void> resolve(int requestId) async {
    await ref.read(helpServiceProvider).resolve(requestId);
    final remaining =
        state.allRequests.where((r) => r.id != requestId).toList();
    HelpRequest? mine = state.myRequest;
    if (mine?.id == requestId) mine = null;
    state = state.copyWith(allRequests: remaining, myRequest: () => mine);
    unawaited(ref.read(notificationServiceProvider).cancelAlert(requestId));
  }
}

final helpProvider = NotifierProvider<HelpNotifier, HelpState>(
  HelpNotifier.new,
);

// ---------------------------------------------------------------------------
// BLE NFC Reader
// ---------------------------------------------------------------------------

enum BleReaderStatus { disconnected, connecting, connected }

const _bleDeviceIdKey = 'ble_reader_device_id';
const _bleDeviceNameKey = 'ble_reader_device_name';

@immutable
class BleReaderState {
  final BleReaderStatus status;
  final String? deviceId;
  final String? deviceName;
  final int? batteryPercent;
  // UID of the last scan + a monotonic counter so NfcInputField's ref.listen
  // fires even if the same wristband is tapped twice in a row.
  final String? lastUid;
  final int lastUidSeq;

  const BleReaderState({
    this.status = BleReaderStatus.disconnected,
    this.deviceId,
    this.deviceName,
    this.batteryPercent,
    this.lastUid,
    this.lastUidSeq = 0,
  });

  bool get isConnected => status == BleReaderStatus.connected;
  bool get isPaired => deviceId != null;

  BleReaderState copyWith({
    BleReaderStatus? status,
    String? Function()? deviceId,
    String? Function()? deviceName,
    int? Function()? batteryPercent,
    String? lastUid,
    int? lastUidSeq,
  }) =>
      BleReaderState(
        status: status ?? this.status,
        deviceId: deviceId != null ? deviceId() : this.deviceId,
        deviceName: deviceName != null ? deviceName() : this.deviceName,
        batteryPercent:
            batteryPercent != null ? batteryPercent() : this.batteryPercent,
        lastUid: lastUid ?? this.lastUid,
        lastUidSeq: lastUidSeq ?? this.lastUidSeq,
      );
}

BluetoothService? _findService(List<BluetoothService> services, Guid uuid) {
  for (final s in services) {
    if (s.uuid == uuid) return s;
  }
  return null;
}

BluetoothCharacteristic? _findCharacteristic(
    List<BluetoothCharacteristic> chars, Guid uuid) {
  for (final c in chars) {
    if (c.uuid == uuid) return c;
  }
  return null;
}

/// Manages the paired nfc-ble-reader: scanning, connect/reconnect, GATT
/// subscriptions (UID notify, battery notify), and persisting the last
/// paired device so it's restored automatically on app start.
class BleReaderNotifier extends Notifier<BleReaderState> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _batteryChar;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _uidSub;
  StreamSubscription<List<int>>? _batterySub;
  Timer? _healthCheckTimer;
  DateTime? _lastLivenessSignal;
  bool _shouldReconnect = false;
  bool _reconnectPending = false;

  @override
  BleReaderState build() {
    ref.onDispose(() {
      _connSub?.cancel();
      _uidSub?.cancel();
      _batterySub?.cancel();
      _healthCheckTimer?.cancel();
    });
    Future.microtask(_restoreSavedDevice);
    return const BleReaderState();
  }

  /// Web Bluetooth never reports an *external* disconnect (device powered
  /// off, out of range) - flutter_blue_plus_web only pushes a
  /// connectionState event for disconnects this app itself triggers (see
  /// _connectToDevice's comment). Without this, the UI would show "Verbunden"
  /// forever and the 5s auto-reconnect would never even fire, since both
  /// depend on that event.
  ///
  /// This is a *passive* check, not an active GATT probe: every
  /// flutter_blue_plus operation (read/write/connect/discoverServices)
  /// shares one per-device mutex that's only released once the underlying
  /// browser call actually settles. If that browser call hangs instead of
  /// rejecting promptly - which happens on web when the link dies quietly -
  /// an active probe here would hold that mutex forever and permanently
  /// deadlock every future operation on this device, including the
  /// auto-reconnect's own connect() call (this happened - a wrapping
  /// `.timeout()` only makes *this* code stop waiting, it doesn't cancel the
  /// stuck browser call or free the mutex it's still holding).
  ///
  /// Instead: the firmware already pushes a battery notify every ~60s while
  /// connected (see nfc-ble-reader/src/main.cpp), tracked in
  /// [_lastLivenessSignal]. If none arrived recently, the link is dead.
  void _startWebHealthCheck() {
    if (_batteryChar == null) return;
    AppLogger.trace('Web-Healthcheck gestartet', logger: 'ble');
    _lastLivenessSignal = DateTime.now();
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final signal = _lastLivenessSignal;
      if (signal == null || DateTime.now().difference(signal) > const Duration(seconds: 90)) {
        AppLogger.warning(
          'Web-Healthcheck: keine Lebenszeichen seit ${signal == null ? '?' : DateTime.now().difference(signal).inSeconds}s — gilt als getrennt',
          logger: 'ble',
        );
        _healthCheckTimer?.cancel();
        _handleDisconnected();
      }
    });
  }

  Future<void> _restoreSavedDevice() async {
    final storage = ref.read(storageProvider);
    final id = await storage.read(key: _bleDeviceIdKey);
    final name = await storage.read(key: _bleDeviceNameKey);
    if (id == null) {
      AppLogger.trace('Kein gespeichertes BLE-Gerät gefunden', logger: 'ble');
      return;
    }
    AppLogger.trace('Gespeichertes BLE-Gerät gefunden: $id ($name)', logger: 'ble');
    state = state.copyWith(deviceId: () => id, deviceName: () => name);

    // Web Bluetooth only ever hands out a usable device handle through its
    // own requestDevice() picker - a remoteId alone (BluetoothDevice.fromId)
    // can never resolve on web, in this page load or any other, so
    // connecting here would just fail forever on a 5s retry loop. Show the
    // pairing as "disconnected" instead and let the user reconnect via the
    // picker (Settings -> NFC-Lesegerät -> Verbinden/Scan).
    if (kIsWeb) {
      AppLogger.trace('Web: Auto-Reconnect übersprungen (kein direkter Reconnect möglich)', logger: 'ble');
      return;
    }

    _shouldReconnect = true;
    await _connectToDevice(BluetoothDevice.fromId(id));
  }

  /// Requests the runtime BLE permissions Android needs before scanning.
  Future<void> _ensurePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  /// Kicks off a scan; results arrive on the always-available
  /// [FlutterBluePlus.scanResults] stream. Caller stops it via [stopScan]
  /// (e.g. once the user picks a device, or leaves the screen).
  Future<void> startScan() async {
    AppLogger.info('BLE-Scan gestartet', logger: 'ble');
    // permission_handler has no web implementation for these Android runtime
    // permissions - it throws there. On web, the browser's own
    // navigator.bluetooth.requestDevice() prompt handles permissioning.
    if (!kIsWeb) {
      await _ensurePermissions();
    }
    await FlutterBluePlus.startScan(
      withServices: [BleNfcService.nfcServiceUuid],
      // Web Bluetooth only allows discoverServices() to see services
      // declared at requestDevice() time. The custom NFC service is covered
      // via the scan filter (withServices) above; the standard Battery
      // Service isn't part of that filter, so it needs to be listed here
      // explicitly or it's silently invisible post-connect (no error, just
      // an empty result - cost real debugging time to track down).
      webOptionalServices: [BleNfcService.batteryServiceUuid],
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> stopScan() {
    AppLogger.trace('BLE-Scan gestoppt', logger: 'ble');
    return FlutterBluePlus.stopScan();
  }

  Future<void> connect(BluetoothDevice device) async {
    AppLogger.trace(
      'Verbindung angefordert von UI: ${device.remoteId.str} (${device.platformName})',
      logger: 'ble',
    );
    await stopScan();
    _shouldReconnect = true;
    await _connectToDevice(device);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    AppLogger.info('BLE-Verbindungsversuch: ${device.remoteId.str} (${device.platformName})', logger: 'ble');
    state = state.copyWith(status: BleReaderStatus.connecting);
    _device = device;

    try {
      // Nonprofit/personal use per FlutterBluePlus License v1.5 - see LICENSE.md
      // in the flutter_blue_plus package if this ever needs revisiting.
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
      );
      AppLogger.trace('GATT verbunden: ${device.remoteId.str}', logger: 'ble');

      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          AppLogger.warning('BLE: connectionState-Stream meldet Disconnect', logger: 'ble');
          _handleDisconnected();
        }
      });

      final services = await device.discoverServices();
      AppLogger.trace('Services entdeckt: ${services.length}', logger: 'ble');

      final nfcService = _findService(services, BleNfcService.nfcServiceUuid);
      final uidChar = nfcService == null
          ? null
          : _findCharacteristic(
              nfcService.characteristics, BleNfcService.uidCharUuid);
      if (uidChar != null) {
        await _uidSub?.cancel();
        _uidSub = uidChar.onValueReceived.listen((bytes) {
          if (bytes.isEmpty) return;
          final uid = bytesToUidHex(bytes);
          AppLogger.trace('UID empfangen: $uid', logger: 'ble');
          state = state.copyWith(
            lastUid: uid,
            lastUidSeq: state.lastUidSeq + 1,
          );
        });
        await uidChar.setNotifyValue(true);
        AppLogger.trace('UID-Characteristic abonniert', logger: 'ble');
      } else {
        AppLogger.warning('BLE: keine UID-Characteristic gefunden', logger: 'ble');
      }

      // Isolated from the outer try/catch on purpose: battery is a nice-to-have.
      // A failure here (e.g. a real read() error) must not undo the UID
      // notify subscription that's already working, or misreport the whole
      // connection as failed.
      try {
        final batteryService =
            _findService(services, BleNfcService.batteryServiceUuid);
        final batteryChar = batteryService == null
            ? null
            : _findCharacteristic(
                batteryService.characteristics, BleNfcService.batteryLevelCharUuid);
        _batteryChar = batteryChar;
        if (batteryChar != null) {
          await _batterySub?.cancel();
          _batterySub = batteryChar.onValueReceived.listen((bytes) {
            _lastLivenessSignal = DateTime.now();
            if (bytes.isNotEmpty) {
              AppLogger.trace('Akku-Update: ${bytes[0]}%', logger: 'ble');
              state = state.copyWith(batteryPercent: () => bytes[0]);
            }
          });
          await batteryChar.setNotifyValue(true);
          AppLogger.trace('Battery-Characteristic abonniert', logger: 'ble');
          final initial = await batteryChar.read();
          if (initial.isNotEmpty) {
            state = state.copyWith(batteryPercent: () => initial[0]);
          }
        } else {
          AppLogger.trace('BLE: keine Battery-Characteristic gefunden', logger: 'ble');
        }
      } catch (e) {
        // Battery is optional - leave batteryPercent unset, keep connecting.
        AppLogger.trace('BLE: Battery-Setup fehlgeschlagen (nicht kritisch): $e', logger: 'ble');
      }

      final storage = ref.read(storageProvider);
      await storage.write(key: _bleDeviceIdKey, value: device.remoteId.str);
      await storage.write(key: _bleDeviceNameKey, value: device.platformName);

      state = state.copyWith(
        status: BleReaderStatus.connected,
        deviceId: () => device.remoteId.str,
        deviceName: () => device.platformName,
      );
      AppLogger.info('BLE verbunden: ${device.remoteId.str} (${device.platformName})', logger: 'ble');

      if (kIsWeb) _startWebHealthCheck();
    } catch (e, st) {
      AppLogger.warning(
        'BLE-Verbindungsversuch fehlgeschlagen: ${device.remoteId.str}',
        logger: 'ble',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(status: BleReaderStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _handleDisconnected() {
    AppLogger.warning('BLE-Verbindung getrennt: ${_device?.remoteId.str}', logger: 'ble');
    _uidSub?.cancel();
    _batterySub?.cancel();
    _healthCheckTimer?.cancel();
    state = state.copyWith(
      status: BleReaderStatus.disconnected,
      batteryPercent: () => null,
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectPending || !_shouldReconnect || _device == null) return;
    AppLogger.trace('BLE-Reconnect in 5s geplant: ${_device?.remoteId.str}', logger: 'ble');
    _reconnectPending = true;
    Future.delayed(const Duration(seconds: 5), () {
      _reconnectPending = false;
      if (_shouldReconnect && _device != null) _connectToDevice(_device!);
    });
  }

  Future<void> disconnect() async {
    AppLogger.info('BLE: manuell getrennt: ${_device?.remoteId.str}', logger: 'ble');
    _shouldReconnect = false;
    await _connSub?.cancel();
    await _uidSub?.cancel();
    await _batterySub?.cancel();
    _healthCheckTimer?.cancel();
    await _device?.disconnect();
    state = state.copyWith(
      status: BleReaderStatus.disconnected,
      batteryPercent: () => null,
    );
  }

  Future<void> forget() async {
    AppLogger.info('BLE: Gerät entkoppelt: ${_device?.remoteId.str ?? state.deviceId}', logger: 'ble');
    await disconnect();
    _device = null;
    final storage = ref.read(storageProvider);
    await storage.delete(key: _bleDeviceIdKey);
    await storage.delete(key: _bleDeviceNameKey);
    state = const BleReaderState();
  }
}

final bleReaderProvider = NotifierProvider<BleReaderNotifier, BleReaderState>(
  BleReaderNotifier.new,
);

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

/// This device's stable ID for log correlation and remote level targeting.
/// Restored (or generated once and persisted) in main().
final deviceIdProvider = StateProvider<String>(
  (ref) => throw StateError('deviceIdProvider must be overridden in main()'),
);

/// The user's own locally-chosen log level. A remote override (set via
/// [LoggingNotifier.applyRemoteLevel]) takes priority over this while active
/// — this stays the fallback for once that override is lifted.
final localLogLevelProvider = StateProvider<LogLevel>((ref) => LogLevel.info);

/// Optional human-readable label for this device (e.g. "Kasse 1"), shown in
/// the server's device list. Purely cosmetic.
final deviceLabelProvider = StateProvider<String?>((ref) => null);

@immutable
class LoggingState {
  final LogLevel? remoteOverride;
  final int pendingCount;
  final DateTime? lastShipAt;
  final bool lastShipFailed;

  const LoggingState({
    this.remoteOverride,
    this.pendingCount = 0,
    this.lastShipAt,
    this.lastShipFailed = false,
  });

  LoggingState copyWith({
    LogLevel? Function()? remoteOverride,
    int? pendingCount,
    DateTime? Function()? lastShipAt,
    bool? lastShipFailed,
  }) =>
      LoggingState(
        remoteOverride: remoteOverride != null ? remoteOverride() : this.remoteOverride,
        pendingCount: pendingCount ?? this.pendingCount,
        lastShipAt: lastShipAt != null ? lastShipAt() : this.lastShipAt,
        lastShipFailed: lastShipFailed ?? this.lastShipFailed,
      );
}

/// Owns the local->server log shipping pipeline: a periodic rotation timer
/// (hourly native / 45s web — a browser tab can vanish without warning, so
/// unshipped logs are kept to a small time window instead of relying on an
/// unload event), a debounced eager flush on severe (ERROR/FATAL) entries,
/// and the effective level (`remoteOverride ?? localLevel`) that
/// [AppLogger.currentLevel] is kept in sync with.
class LoggingNotifier extends Notifier<LoggingState> {
  Timer? _shipTimer;
  Timer? _severeDebounce;

  @override
  LoggingState build() {
    AppLogger.onSevereLog = _onSevereLog;
    // Can't call _syncEffectiveLevel() here: `state` isn't assigned yet until
    // build() returns, and reading it early throws ("Bad state: Tried to read
    // the state of an uninitialized provider"). remoteOverride is always null
    // at construction time anyway, so just use the local level directly.
    AppLogger.currentLevel = ref.read(localLogLevelProvider);
    ref.listen(localLogLevelProvider, (_, _) => _syncEffectiveLevel());
    _restartShipTimer();
    ref.onDispose(() {
      _shipTimer?.cancel();
      _severeDebounce?.cancel();
      AppLogger.onSevereLog = null;
    });
    return const LoggingState();
  }

  void _syncEffectiveLevel() {
    AppLogger.currentLevel = state.remoteOverride ?? ref.read(localLogLevelProvider);
  }

  void _restartShipTimer() {
    _shipTimer?.cancel();
    _shipTimer = Timer.periodic(
      kIsWeb ? const Duration(seconds: 45) : const Duration(hours: 1),
      (_) => ship(),
    );
  }

  void _onSevereLog() {
    _severeDebounce?.cancel();
    _severeDebounce = Timer(const Duration(seconds: 2), ship);
  }

  /// Sends up to one batch (server caps at 200/request) of buffered entries.
  /// Safe to call anytime — a no-op when nothing is pending, and a failed
  /// attempt simply leaves the buffer intact for the next scheduled try.
  Future<void> ship() async {
    if (AppLogger.pendingCount == 0) return;
    final deviceId = ref.read(deviceIdProvider);
    final batch = AppLogger.pendingBatch(200);
    try {
      final accepted =
          await ref.read(logsServiceProvider).ingest(deviceId, batch);
      AppLogger.clearShipped(accepted);
      state = state.copyWith(
        pendingCount: AppLogger.pendingCount,
        lastShipAt: () => DateTime.now(),
        lastShipFailed: false,
      );
    } catch (_) {
      state = state.copyWith(
        pendingCount: AppLogger.pendingCount,
        lastShipFailed: true,
      );
    }
  }

  /// Called by [connectionStatusProvider]'s health poll whenever the server
  /// reports a forced level for this device (or null to clear it).
  void applyRemoteLevel(String? levelName) {
    final next = levelName == null ? null : LogLevel.fromLabel(levelName);
    if (next?.value == state.remoteOverride?.value) return;
    state = state.copyWith(remoteOverride: () => next);
    _syncEffectiveLevel();
  }
}

final loggingProvider = NotifierProvider<LoggingNotifier, LoggingState>(
  LoggingNotifier.new,
);

// ---------------------------------------------------------------------------
// Cart
// ---------------------------------------------------------------------------

/// In-memory shopping cart. State is a list of [CartItem]s (one per product).
/// Multiple units of the same product are represented by [CartItem.quantity],
/// not by duplicate list entries.
class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  /// Adds [product] to the cart. If it is already present, increments the
  /// quantity instead of creating a second entry.
  void addProduct(ProductModel product) {
    final idx = state.indexWhere((i) => i.product.id == product.id);
    if (idx >= 0) {
      final list = [...state];
      list[idx] = list[idx].withQuantity(list[idx].quantity + 1);
      state = list;
    } else {
      state = [...state, CartItem(product: product, quantity: 1)];
    }
  }

  void removeItem(int productId) {
    state = state.where((i) => i.product.id != productId).toList();
  }

  void clear() => state = [];

  double get total => state.fold(0.0, (s, i) => s + i.subtotal);

  /// Expands each [CartItem] into [CartItem.quantity] repeated product IDs.
  ///
  /// The booking API expects one ID per purchased unit so it can create
  /// individual sale rows (enabling per-item cancellation). For example,
  /// 2 units of product 5 → `[5, 5]`.
  ///
  /// Note: the server de-duplicates IDs only for the product lookup (to avoid
  /// SQL `IN` de-duplication returning fewer rows). The full repeated list is
  /// used for pricing and sale row creation.
  List<int> get productIds =>
      state.expand((i) => List.filled(i.quantity, i.product.id)).toList();
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

final customerProvider = StateProvider<CustomerModel?>((ref) => null);

// Last successful booking for storno: {sale_ids, product_names, total}
final lastBookingProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

final selectedCategoryProvider = StateProvider<CategoryModel?>((ref) => null);

final editModeProvider = StateProvider<bool>((ref) => false);

// Display settings — persisted in secure storage, loaded in main().
final textScaleProvider = StateProvider<double>((ref) => 1.0);
final gridColumnsProvider = StateProvider<int>((ref) => 3);
final cartTextScaleProvider = StateProvider<double>((ref) => 1.0);
final buttonMaxLinesProvider = StateProvider<int>((ref) => 2);

/// Whether the persistent sidebar rail (tablet/wide layout only — the phone
/// layout's Drawer is unaffected) is collapsed to reclaim screen width.
/// Per-device preference, not per-user, so it lives alongside the other
/// display settings above rather than in the server-synced [UserPreferences].
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// Sets [sidebarCollapsedProvider] and persists it, matching the read side in
/// `main.dart`. Shared by the collapse button in `AppSidebar` and the expand
/// button in `MainShell`'s AppBar so the storage key lives in one place.
void setSidebarCollapsed(WidgetRef ref, bool collapsed) {
  ref.read(sidebarCollapsedProvider.notifier).state = collapsed;
  ref.read(storageProvider).write(key: 'display_sidebarCollapsed', value: collapsed.toString());
}

/// Widths of the two resizable side panels on the wide POS layout (see
/// `pos_screen.dart`'s `_WidePosLayout`) — the cart on the right (always
/// present) and the pager list on the left (only when the pager add-on is
/// enabled). Same persistence pattern as [sidebarCollapsedProvider].
final cartWidthProvider = StateProvider<double>((ref) => 300.0);
final pagerWidthProvider = StateProvider<double>((ref) => 260.0);

void setCartWidth(WidgetRef ref, double width) {
  ref.read(cartWidthProvider.notifier).state = width;
  ref.read(storageProvider).write(key: 'display_cartWidth', value: width.toString());
}

void setPagerWidth(WidgetRef ref, double width) {
  ref.read(pagerWidthProvider.notifier).state = width;
  ref.read(storageProvider).write(key: 'display_pagerWidth', value: width.toString());
}

enum AppScreen { pos, stats, users, settings, account, logs, articleAdmin }

final currentScreenProvider = StateProvider<AppScreen>((ref) => AppScreen.pos);

// ---------------------------------------------------------------------------
// Async data
// ---------------------------------------------------------------------------

/// Products for a given category, keyed by category ID.
///
/// Watches [productsRefreshProvider] so that incrementing it causes all
/// category-specific instances to refetch (used after create/edit/delete).
///
/// An `AsyncNotifierProvider`, not a plain `FutureProvider` — [ProductSyncNotifier]
/// needs to patch specific products into the cached list via
/// `ref.read(productsProvider(id).notifier).state = ...` without a full
/// refetch, which only a Notifier-backed provider exposes in this Riverpod
/// version (plain `FutureProvider` has no externally-settable `.notifier.state`).
class ProductsNotifier extends FamilyAsyncNotifier<List<ProductModel>, int> {
  @override
  Future<List<ProductModel>> build(int categoryId) async {
    ref.watch(productsRefreshProvider); // invalidate trigger
    return ref.read(productServiceProvider).getProducts(categoryId);
  }

  /// Called by [ProductSyncNotifier] to patch specific products in place —
  /// updates/inserts from [changed], removals by ID in [removedIds] — without
  /// a full refetch. No-op if this category's data isn't loaded yet (e.g. the
  /// initial fetch is still in flight).
  void applyChanges(List<ProductModel> changed, List<int> removedIds) {
    final current = state.valueOrNull;
    if (current == null) return;
    final changedById = {for (final p in changed) p.id: p};
    final patched = [
      for (final p in current)
        if (!removedIds.contains(p.id)) (changedById[p.id] ?? p),
      for (final p in changed)
        if (!current.any((c) => c.id == p.id)) p,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    state = AsyncData(patched);
  }
}

final productsProvider =
    AsyncNotifierProvider.family<ProductsNotifier, List<ProductModel>, int>(
  ProductsNotifier.new,
);

/// Incrementing this integer invalidates all [productsProvider] instances.
/// Pattern: `ref.read(productsRefreshProvider.notifier).state++`
final productsRefreshProvider = StateProvider<int>((ref) => 0);

// Incrementing this integer invalidates [categoriesProvider].
final categoriesRefreshProvider = StateProvider<int>((ref) => 0);

/// All categories visible to the logged-in user (filtered server-side by
/// their `user_category_access` rows or their manager status).
final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) {
  ref.watch(categoriesRefreshProvider);
  return ref.read(productServiceProvider).getCategories();
});

// Incrementing this integer invalidates [adminCategoriesProvider].
final adminCategoriesRefreshProvider = StateProvider<int>((ref) => 0);

/// Every article (incl. inactive, incl. options) across every category the
/// logged-in user can manage articles in — the article admin screen's data
/// source. Plain refetch-on-demand (bump the refresh provider), matching
/// how every other create/edit/delete flow in this app already works,
/// rather than the timestamp-diff sync built for the much larger POS grid.
final adminCategoriesProvider = FutureProvider<List<AdminCategoryProducts>>((ref) {
  ref.watch(adminCategoriesRefreshProvider);
  // Also watched so a category created/renamed/deleted from the sidebar
  // (which only bumps categoriesRefreshProvider, not this screen's own
  // refresh provider) shows up here immediately too.
  ref.watch(categoriesRefreshProvider);
  return ref.read(productServiceProvider).getAdminCategories();
});

// ---------------------------------------------------------------------------
// Product catalog sync — cross-device price/stock updates
// ---------------------------------------------------------------------------

typedef ProductSyncState = ({int? categoryId, DateTime? lastSyncedAt});

/// Owns the "did any product in my currently-viewed category change since I
/// last checked" poll. Deliberately per-product (via `GET
/// /api/products/changed`'s `since` timestamp), not a blunt "reload the whole
/// category" signal — see docs/plan discussion for why a simpler global
/// revision counter was rejected in favor of this.
///
/// Called from two places: [connectionStatusProvider]'s existing 10s poll
/// loop (fire-and-forget), and directly before booking in `cart_panel.dart`
/// (awaited, so a very recent change is caught before the booking is sent —
/// the server rejects an out-of-stock booking regardless, this just avoids
/// the round trip and gives the cashier an up-to-date grid first).
class ProductSyncNotifier extends Notifier<ProductSyncState> {
  @override
  ProductSyncState build() => (categoryId: null, lastSyncedAt: null);

  Future<void> checkForChanges() async {
    final category = ref.read(selectedCategoryProvider);
    if (category == null) return;

    // Category just switched (or this is the very first call ever): the
    // normal productsProvider fetch for this category is already fresh —
    // nothing to reconcile yet, just establish the baseline for next time.
    if (state.categoryId != category.id) {
      state = (categoryId: category.id, lastSyncedAt: DateTime.now().toUtc());
      return;
    }

    try {
      final result = await ref
          .read(productServiceProvider)
          .getChangedProducts(category.id, state.lastSyncedAt!);
      if (result.products.isNotEmpty || result.removedIds.isNotEmpty) {
        ref
            .read(productsProvider(category.id).notifier)
            .applyChanges(result.products, result.removedIds);
      }
      state = (categoryId: category.id, lastSyncedAt: result.checkedAt);
    } catch (_) {
      // Not critical — the next check (poll or booking click) retries with
      // the same `since` baseline, this just delays visibility briefly.
    }
  }
}

final productSyncProvider = NotifierProvider<ProductSyncNotifier, ProductSyncState>(
  ProductSyncNotifier.new,
);

// ---------------------------------------------------------------------------
// Pager add-on — the operator's own open pager orders
// ---------------------------------------------------------------------------

/// The logged-in operator's own open pager orders (pager add-on). Unlike
/// [ProductSyncNotifier], this doesn't need timestamp-diffing sync: the list
/// is small (one operator's own open orders, not the whole catalog), so a
/// plain refetch on every trigger (10s poll, after creating/closing an
/// entry) is simple and sufficient — there's no cross-device sharing to
/// reconcile in this version (see the plan's Context section).
class PagerListNotifier extends AsyncNotifier<List<PagerOrderModel>> {
  @override
  Future<List<PagerOrderModel>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null || !user.pagerEnabled) return [];
    return ref.read(pagerServiceProvider).listOpen();
  }

  /// Re-fetches, keeping the previous list on failure rather than clearing
  /// it — matches [ProductSyncNotifier.checkForChanges]'s "not critical, the
  /// next trigger retries" tolerance for a background refresh.
  Future<void> refresh() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null || !user.pagerEnabled) return;
    try {
      state = AsyncData(await ref.read(pagerServiceProvider).listOpen());
    } catch (_) {
      // Ignored — next poll/trigger retries.
    }
  }
}

final pagerListProvider = AsyncNotifierProvider<PagerListNotifier, List<PagerOrderModel>>(
  PagerListNotifier.new,
);
