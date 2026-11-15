import 'package:expense_manager/core/config/demo_mode.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests run without `--dart-define=DEMO=true`, which matches a normal
/// (non-demo) build: there is no fallback identity and no demo backend.
void main() {
  test('demo mode is off without the DEMO define', () {
    expect(kDemoMode, isFalse);
    expect(DemoBackend.active, isFalse);
    expect(DemoBackend.activate, throwsStateError);
    expect(DemoBackend.active, isFalse);
  });

  test('requireUserId has no fallback identity', () {
    expect(requireUserId('user-1'), 'user-1');
    expect(() => requireUserId(null), throwsStateError);
  });

  test('userIdForChecks fails closed when signed out', () {
    expect(userIdForChecks('user-1'), 'user-1');
    expect(userIdForChecks(null), isEmpty);
  });

  test('the demo account gets no permission shortcuts', () {
    expect(isDemoUser(kDemoUserId), isFalse);
    expect(isDemoUser(null), isFalse);
  });
}
