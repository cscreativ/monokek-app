/// Build-time configuration. Mirrors the NEXT_PUBLIC_* variables of mono-kep-tauri/.env.local;
/// pass them with `--dart-define=POS_CLIENT_SECRET=...` rather than committing them.
class AppConfig {
  static const posClientId = String.fromEnvironment('POS_CLIENT_ID', defaultValue: 'monokek-pos');
  static const posClientSecret = String.fromEnvironment('POS_CLIENT_SECRET');
  static const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080');
}
