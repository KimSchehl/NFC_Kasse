class ApiConfig {
  // Default used on the very first run (Android emulator → host machine).
  // After that, the user-entered URL from the login screen is persisted in
  // secure storage and loaded at startup — this constant is never used again.
  static const defaultBaseUrl = 'http://10.0.2.2:8000';
}
