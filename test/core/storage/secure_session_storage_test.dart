import 'package:expense_manager/core/storage/secure_session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'sb-project-auth-token';
  const storage = FlutterSecureStorage();

  test('a reinstall does not restore the previous session', () async {
    // The Keychain kept the session; SharedPreferences was wiped.
    FlutterSecureStorage.setMockInitialValues({key: 'old-session'});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await SecureSessionStorage.clearAfterReinstall(prefs, storage: storage);

    expect(await storage.read(key: key), isNull);
    expect(prefs.getBool(SecureSessionStorage.installMarkerKey), isTrue);
  });

  test('later launches keep the session', () async {
    FlutterSecureStorage.setMockInitialValues({key: 'session'});
    SharedPreferences.setMockInitialValues({
      SecureSessionStorage.installMarkerKey: true,
    });
    final prefs = await SharedPreferences.getInstance();

    await SecureSessionStorage.clearAfterReinstall(prefs, storage: storage);

    expect(await storage.read(key: key), 'session');
  });
}
