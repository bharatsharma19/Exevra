import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';

/// Keeps the Supabase session (access and refresh tokens) in the platform
/// keystore instead of plain SharedPreferences.
///
/// A session saved by an older build in SharedPreferences is moved here
/// once and removed from SharedPreferences.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({
    required this.persistSessionKey,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? secureStorage;

  /// Android: encrypted with a Keystore key; iOS: this device only.
  static const FlutterSecureStorage secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final String persistSessionKey;
  final FlutterSecureStorage _storage;

  /// SharedPreferences flag set on the first run of this installation.
  static const String installMarkerKey = 'install_marker';

  /// On the first run of an installation, removes anything a previous
  /// installation left in the keystore. The iOS Keychain survives an
  /// uninstall while SharedPreferences (with the per-user App Lock flag)
  /// does not, so without this a reinstall would sign the previous user
  /// back in with App Lock off. Runs before Supabase reads the session.
  static Future<void> clearAfterReinstall(
    SharedPreferences prefs, {
    FlutterSecureStorage? storage,
  }) async {
    if (prefs.getBool(installMarkerKey) ?? false) return;
    try {
      await (storage ?? secureStorage).deleteAll();
    } on Object catch (e) {
      AppLogger.warn('Could not clear the keystore', e.runtimeType);
    }
    try {
      await prefs.setBool(installMarkerKey, true);
    } on Object catch (e) {
      AppLogger.warn('Could not mark the installation', e.runtimeType);
    }
  }

  /// The key supabase_flutter uses for a project URL.
  static String keyFor(String supabaseUrl) =>
      'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy == null) return;
      if (!await _storage.containsKey(key: persistSessionKey)) {
        await _storage.write(key: persistSessionKey, value: legacy);
      }
      await prefs.remove(persistSessionKey);
    } on Object catch (e) {
      AppLogger.warn('Session storage migration skipped', e.runtimeType);
    }
  }

  @override
  Future<bool> hasAccessToken() => _guard(
    () => _storage.containsKey(key: persistSessionKey),
    fallback: false,
  );

  @override
  Future<String?> accessToken() =>
      _guard(() => _storage.read(key: persistSessionKey), fallback: null);

  @override
  Future<void> removePersistedSession() =>
      _guard(() => _storage.delete(key: persistSessionKey), fallback: null);

  @override
  Future<void> persistSession(String persistSessionString) => _guard(
    () => _storage.write(key: persistSessionKey, value: persistSessionString),
    fallback: null,
  );

  /// A keystore failure (for example after a restore to another device)
  /// signs the user out instead of crashing.
  static Future<T> _guard<T>(
    Future<T> Function() action, {
    required T fallback,
  }) async {
    try {
      return await action();
    } on Object catch (e) {
      AppLogger.warn('Secure session storage failed', e.runtimeType);
      return fallback;
    }
  }
}

/// Keeps the PKCE code verifier in the keystore as well.
class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage([this._storage = SecureSessionStorage.secureStorage]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem({required String key}) => SecureSessionStorage._guard(
    () => _storage.read(key: key),
    fallback: null,
  );

  @override
  Future<void> removeItem({required String key}) => SecureSessionStorage._guard(
    () => _storage.delete(key: key),
    fallback: null,
  );

  @override
  Future<void> setItem({required String key, required String value}) =>
      SecureSessionStorage._guard(
        () => _storage.write(key: key, value: value),
        fallback: null,
      );
}
