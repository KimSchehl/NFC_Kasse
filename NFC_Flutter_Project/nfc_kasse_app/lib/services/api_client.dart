import 'package:dio/dio.dart';

import '../utils/id_generator.dart';
import 'app_logger.dart';
import 'app_storage.dart';


/// Central HTTP client for all backend communication.
///
/// Wraps Dio with these interceptor behaviours:
/// 1. **Auth injection**: reads the stored access token and adds it as a
///    `Authorization: Bearer <token>` header on every request.
/// 2. **Auto-refresh**: on a 401 response, silently refreshes the token pair
///    and retries the original request once. Multiple simultaneous 401s all
///    share the same refresh attempt via [_refreshFuture], preventing the
///    refresh token from being consumed more than once.
/// 3. **Trace correlation**: every request gets a fresh `X-Trace-Id` (plus
///    `X-Device-Id` if this device has one yet) so the resulting server-side
///    log line can be found from the matching client-side entry, and vice
///    versa.
/// 4. **Request logging**: one buffered [AppLogger] entry per response —
///    `/health` (polled every 10s) is dropped to TRACE to avoid drowning the
///    buffer, mirroring the server's own middleware.
class ApiClient {
  final AppStorage _storage;
  final String _baseUrl;
  late final Dio dio;

  // Shared refresh future — concurrent 401s all await the same refresh attempt
  // instead of each spawning their own (which would burn the refresh token).
  Future<void>? _refreshFuture;

  ApiClient(this._storage, {required String baseUrl}) : _baseUrl = baseUrl {
    dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        final deviceId = await _storage.read(key: 'log_device_id');
        if (deviceId != null) {
          options.headers['X-Device-Id'] = deviceId;
        }
        final traceId = generateId('trc');
        options.headers['X-Trace-Id'] = traceId;
        options.extra['_traceId'] = traceId;
        handler.next(options);
      },
      onResponse: (response, handler) {
        final path = response.requestOptions.path;
        AppLogger.trace(
          '${response.requestOptions.method} $path -> ${response.statusCode}',
          logger: path == '/health' ? 'http.health' : 'http',
          traceId: response.requestOptions.extra['_traceId'] as String?,
        );
        handler.next(response);
      },
      onError: (error, handler) async {
        final status = error.response?.statusCode;
        final path = error.requestOptions.path;
        final traceId = error.requestOptions.extra['_traceId'] as String?;
        final message =
            '${error.requestOptions.method} $path -> ${status ?? error.type}';
        if (status != null && status < 500) {
          AppLogger.warning(message, logger: 'http', traceId: traceId);
        } else {
          AppLogger.error(message, logger: 'http', traceId: traceId, error: error);
        }

        // Only attempt refresh once per request (extra flag prevents retry loops).
        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra['_retried'] != true) {
          try {
            // If a refresh is already in flight, await it instead of starting another.
            _refreshFuture ??=
                _doRefresh().whenComplete(() => _refreshFuture = null);
            await _refreshFuture;

            final token = await _storage.read(key: 'access_token');
            final opts = error.requestOptions
              ..extra['_retried'] = true
              ..headers['Authorization'] = 'Bearer $token';
            final cloned = await dio.fetch(opts);
            handler.resolve(cloned);
          } catch (_) {
            await _storage.deleteAll();
            handler.next(error);
          }
        } else {
          handler.next(error);
        }
      },
    ));
  }

  Future<void> _doRefresh() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) throw Exception('No refresh token stored');

    // Use a plain Dio (no interceptor) to avoid recursion
    final plain = Dio(BaseOptions(baseUrl: _baseUrl));
    final response = await plain.post(
      '/api/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    await _storage.write(
        key: 'access_token', value: response.data['access_token'] as String);
    await _storage.write(
        key: 'refresh_token', value: response.data['refresh_token'] as String);
  }

  Future<void> storeTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.deleteAll();
  }

  Future<bool> hasStoredTokens() async {
    final token = await _storage.read(key: 'access_token');
    return token != null;
  }
}
