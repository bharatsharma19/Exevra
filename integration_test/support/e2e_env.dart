/// Settings of the end-to-end run, all passed with --dart-define on the
/// command line (never committed). See integration_test/app_flow_test.dart.
library;

abstract final class E2eEnv {
  /// The app's Supabase URL as seen from the device (config/local.json).
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The local stack's anon key (config/local.json).
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// The LOCAL stack's service role key, for test setup only (creating
  /// and removing the second user). Never used by the app.
  static const serviceKey = String.fromEnvironment('E2E_SERVICE_KEY');

  /// The local mail catcher (Mailpit) as seen from the device.
  static const mailUrl = String.fromEnvironment(
    'E2E_MAIL_URL',
    defaultValue: 'http://10.0.2.2:54324',
  );

  /// integration_test/screenshot_server.py as seen from the device. Empty
  /// turns screenshots off.
  static const shotUrl = String.fromEnvironment(
    'E2E_SHOT_URL',
    defaultValue: 'http://10.0.2.2:8765',
  );

  /// Problems that stop the run before it starts.
  static List<String> get problems => [
    if (supabaseUrl.isEmpty) 'SUPABASE_URL is missing.',
    if (anonKey.isEmpty) 'SUPABASE_ANON_KEY is missing.',
    if (serviceKey.isEmpty) 'E2E_SERVICE_KEY is missing.',
    if (!_isLocal(supabaseUrl))
      'SUPABASE_URL must point at a local stack (10.0.2.2 or localhost).',
  ];

  static bool _isLocal(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host == '10.0.2.2' || host == 'localhost' || host == '127.0.0.1';
  }
}
