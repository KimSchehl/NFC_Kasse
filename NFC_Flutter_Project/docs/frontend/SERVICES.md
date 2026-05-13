# Flutter Frontend — Services & Architecture

---

## File Structure

```
frontend/nfc_kasse_app/lib/
├── main.dart                   — App entry point, routing, theme
├── config.dart                 — Backend URL, constants
├── services/
│   ├── api_service.dart        — HTTP client (dio) + token interceptor
│   ├── auth_service.dart       — Login, logout, token management
│   ├── nfc_service.dart        — NFC scan (mobile) + HID input (desktop)
│   ├── sales_service.dart      — Bookings, balance, cancel
│   ├── topup_service.dart      — Balance top-up + payout
│   ├── products_service.dart   — Products + categories
│   └── stats_service.dart      — Statistics
├── models/
│   ├── user.dart
│   ├── product.dart
│   ├── category.dart
│   ├── sale.dart
│   └── topup.dart
├── screens/
│   ├── login_screen.dart
│   ├── pos_screen.dart
│   ├── topup_screen.dart
│   ├── stats_screen.dart
│   └── settings_screen.dart
└── widgets/
    ├── product_grid.dart       — Reusable product button grid
    ├── cart_panel.dart         — Shopping cart
    ├── nfc_input.dart          — Unified NFC input (mobile + HID)
    └── permission_tree.dart    — Checkbox tree for permission assignment
```

---

## api_service.dart — HTTP Client

```dart
// Dio with interceptor for automatic token refresh

class ApiService {
  final Dio _dio = Dio(BaseOptions(baseUrl: Config.backendUrl));

  ApiService() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await AuthService.getAccessToken();
        options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Access token expired — try refresh
          final refreshed = await AuthService.refreshToken();
          if (refreshed) {
            return handler.resolve(await _retry(error.requestOptions));
          }
          // Refresh token also expired — force logout
          AuthService.logout();
        }
        handler.next(error);
      },
    ));
  }
}
```

---

## auth_service.dart — Token Management

```dart
class AuthService {
  static const _storage = FlutterSecureStorage();

  static Future<LoginResult> login(String username, String password) async { ... }
  static Future<void> logout() async { ... }
  static Future<String?> getAccessToken() => _storage.read(key: 'access_token');
  static Future<bool> refreshToken() async { ... }
  static Future<User> getCurrentUser() async { ... }
  static Future<bool> hasPermission(String permissionId) async { ... }
}
```

---

## nfc_service.dart — NFC Input

```dart
// Mobile: nfc_manager package — native NFC on Android/iOS
// Desktop/Web: USB HID reader emulates keyboard input — no extra code needed
//   → TextField with onSubmitted / onChanged debounce handles it

class NfcService {
  static Stream<String> startMobileScan() { ... }  // nfc_manager

  // On desktop, HID input is treated as normal keyboard text.
  // The nfc_input.dart widget decides which path is active.
  static bool get isHidMode => kIsWeb || Platform.isWindows;
}
```

---

## config.dart — Backend URL

```dart
// Not hardcoded — configurable at build time or app start
class Config {
  static String backendUrl = const String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://192.168.1.1:8000',
  );
}
```

**Different build targets:**
```bash
flutter run --dart-define=BACKEND_URL=http://localhost:8000
flutter build apk --dart-define=BACKEND_URL=http://192.168.1.1:8000
```

---

## Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  dio: ^5.x                      # HTTP client
  flutter_secure_storage: ^9.x   # Keychain/Keystore for tokens
  nfc_manager: ^3.x              # NFC on Android/iOS
  provider: ^6.x                 # State management (or riverpod)
  intl: ^0.19.x                  # Number formatting (€ 3,50)
```
