import '../models/user_model.dart';
import 'api_client.dart';

/// Handles login, session restore, and logout against the auth API.
class AuthService {
  final ApiClient _client;
  AuthService(this._client);

  /// Authenticates and stores the returned token pair, then fetches the full
  /// user profile via [fetchMe]. Returns the [UserModel] on success.
  Future<UserModel> login(String username, String password) async {
    final resp = await _client.dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    await _client.storeTokens(
      resp.data['access_token'] as String,
      resp.data['refresh_token'] as String,
    );
    return fetchMe();
  }

  /// Fetches the current user's profile and permissions from `/api/auth/me`.
  Future<UserModel> fetchMe() async {
    final resp = await _client.dio.get('/api/auth/me');
    return UserModel.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Revokes the refresh token server-side and clears local storage.
  /// The server call is best-effort — local tokens are cleared even if it fails.
  Future<void> logout(String refreshToken) async {
    try {
      await _client.dio.post('/api/auth/logout', data: {'refresh_token': refreshToken});
    } catch (_) {}
    await _client.clearTokens();
  }
}
