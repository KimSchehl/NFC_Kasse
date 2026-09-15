class ApiConfig {
  // Default used on the very first run, before any server has ever been
  // entered. After that, the user-entered URL is persisted (AppStorage) and
  // loaded at startup — this constant is never used again for that install.
  //
  // For local dev against the Android emulator, the backend is reachable at
  // http://10.0.2.2:8000 instead — pick that from the server-URL dropdown
  // (or type it once) on the login screen, it gets remembered from then on.
  static const defaultBaseUrl = 'http://nfc-kasse.lan:8000';

  /// Shown in the login screen's server-URL dropdown even before they've
  /// ever been used, alongside whatever the user has actually connected to
  /// before (see ServerHistoryService).
  static const predefinedServerUrls = [
    'http://nfc-kasse.lan:8000',
    'http://192.168.1.2:8000',
  ];
}
