import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import '../services/app_storage.dart';
import '../models/cart_item.dart';
import '../models/category_model.dart';
import '../models/customer_model.dart';
import '../models/help_model.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';
import '../models/user_preferences_model.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/ble_nfc_service.dart';
import '../services/customer_service.dart';
import '../services/help_service.dart';
import '../services/notification_service.dart';
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
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

/// Polls /health every 10 seconds and emits true/false.
/// Restarts automatically when the server URL changes.
final connectionStatusProvider = StreamProvider<bool>((ref) {
  final client = ref.watch(apiClientProvider);
  final controller = StreamController<bool>.broadcast();

  Future<void> poll() async {
    while (!controller.isClosed) {
      bool ok;
      try {
        await client.dio.get(
          '/health',
          options: Options(
            sendTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 3),
          ),
        );
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
    _lastLivenessSignal = DateTime.now();
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final signal = _lastLivenessSignal;
      if (signal == null || DateTime.now().difference(signal) > const Duration(seconds: 90)) {
        _healthCheckTimer?.cancel();
        _handleDisconnected();
      }
    });
  }

  Future<void> _restoreSavedDevice() async {
    final storage = ref.read(storageProvider);
    final id = await storage.read(key: _bleDeviceIdKey);
    final name = await storage.read(key: _bleDeviceNameKey);
    if (id == null) return;
    state = state.copyWith(deviceId: () => id, deviceName: () => name);

    // Web Bluetooth only ever hands out a usable device handle through its
    // own requestDevice() picker - a remoteId alone (BluetoothDevice.fromId)
    // can never resolve on web, in this page load or any other, so
    // connecting here would just fail forever on a 5s retry loop. Show the
    // pairing as "disconnected" instead and let the user reconnect via the
    // picker (Settings -> NFC-Lesegerät -> Verbinden/Scan).
    if (kIsWeb) return;

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

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Future<void> connect(BluetoothDevice device) async {
    await stopScan();
    _shouldReconnect = true;
    await _connectToDevice(device);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    state = state.copyWith(status: BleReaderStatus.connecting);
    _device = device;

    try {
      // Nonprofit/personal use per FlutterBluePlus License v1.5 - see LICENSE.md
      // in the flutter_blue_plus package if this ever needs revisiting.
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
      );

      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _handleDisconnected();
        }
      });

      final services = await device.discoverServices();

      final nfcService = _findService(services, BleNfcService.nfcServiceUuid);
      final uidChar = nfcService == null
          ? null
          : _findCharacteristic(
              nfcService.characteristics, BleNfcService.uidCharUuid);
      if (uidChar != null) {
        await _uidSub?.cancel();
        _uidSub = uidChar.onValueReceived.listen((bytes) {
          if (bytes.isEmpty) return;
          state = state.copyWith(
            lastUid: bytesToUidHex(bytes),
            lastUidSeq: state.lastUidSeq + 1,
          );
        });
        await uidChar.setNotifyValue(true);
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
              state = state.copyWith(batteryPercent: () => bytes[0]);
            }
          });
          await batteryChar.setNotifyValue(true);
          final initial = await batteryChar.read();
          if (initial.isNotEmpty) {
            state = state.copyWith(batteryPercent: () => initial[0]);
          }
        }
      } catch (_) {
        // Battery is optional - leave batteryPercent unset, keep connecting.
      }

      final storage = ref.read(storageProvider);
      await storage.write(key: _bleDeviceIdKey, value: device.remoteId.str);
      await storage.write(key: _bleDeviceNameKey, value: device.platformName);

      state = state.copyWith(
        status: BleReaderStatus.connected,
        deviceId: () => device.remoteId.str,
        deviceName: () => device.platformName,
      );

      if (kIsWeb) _startWebHealthCheck();
    } catch (_) {
      state = state.copyWith(status: BleReaderStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _handleDisconnected() {
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
    _reconnectPending = true;
    Future.delayed(const Duration(seconds: 5), () {
      _reconnectPending = false;
      if (_shouldReconnect && _device != null) _connectToDevice(_device!);
    });
  }

  Future<void> disconnect() async {
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

enum AppScreen { pos, stats, users, settings, account }

final currentScreenProvider = StateProvider<AppScreen>((ref) => AppScreen.pos);

// ---------------------------------------------------------------------------
// Async data
// ---------------------------------------------------------------------------

/// Products for a given category, keyed by category ID.
///
/// Watches [productsRefreshProvider] so that incrementing it causes all
/// category-specific instances to refetch (used after create/edit/delete).
final productsProvider = FutureProvider.family<List<ProductModel>, int>(
  (ref, categoryId) async {
    ref.watch(productsRefreshProvider); // invalidate trigger
    return ref.read(productServiceProvider).getProducts(categoryId);
  },
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
