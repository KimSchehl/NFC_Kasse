import 'package:dio/dio.dart';

import 'app_storage.dart';


/// Central HTTP client for all backend communication.
///
/// Wraps Dio with two interceptor behaviours:
/// 1. **Auth injection**: reads the stored access token and adds it as a
///    `Authorization: Bearer <token>` header on every request.
/// 2. **Auto-refresh**: on a 401 response, silently refreshes the token pair
///    and retries the original request once. Multiple simultaneous 401s all
///    share the same refresh attempt via [_refreshFuture], preventing the
///    refresh token from being consumed more than once.
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
        handler.next(options);
      },
      onError: (error, handler) async {
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
