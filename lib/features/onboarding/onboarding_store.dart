import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';

/// Loads the [SharedPreferences] instance a store reads and writes.
typedef PreferencesLoader = Future<SharedPreferences> Function();

/// Device-level flags for the introduction and the first-expense tip.
///
/// The flags belong to the device, not to an account: they stay set after
/// sign-out, so a second account on the same phone does not see the
/// introduction again. Reads that fail count as "not done yet" (the worst
/// case is showing the introduction or the tip once more).
class OnboardingStore {
  /// Creates a store backed by [preferences] (the app's shared preferences by
  /// default).
  OnboardingStore({PreferencesLoader? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  /// Set once the introduction was finished or skipped.
  static const String completedKey = 'onboarding_completed_v1';

  /// Set once the first-expense tip was dismissed.
  static const String firstExpenseNudgeDismissedKey =
      'first_expense_nudge_dismissed_v1';

  final PreferencesLoader _preferences;

  /// Whether the introduction was finished or skipped on this device.
  Future<bool> isCompleted() => _read(completedKey);

  /// Records that the introduction was finished or skipped.
  Future<void> markCompleted() => _set(completedKey);

  /// Whether the first-expense tip was dismissed on this device.
  Future<bool> isFirstExpenseNudgeDismissed() =>
      _read(firstExpenseNudgeDismissedKey);

  /// Records that the first-expense tip was dismissed.
  Future<void> dismissFirstExpenseNudge() =>
      _set(firstExpenseNudgeDismissedKey);

  Future<bool> _read(String key) async {
    try {
      return (await _preferences()).getBool(key) ?? false;
    } on Object catch (error) {
      AppLogger.warn('Could not read the $key flag', error);
      return false;
    }
  }

  Future<void> _set(String key) async {
    final saved = await (await _preferences()).setBool(key, true);
    if (!saved) throw StateError('The $key flag was not saved.');
  }
}

/// The [OnboardingStore] of the app. Override it in tests.
final onboardingStoreProvider = Provider<OnboardingStore>(
  (ref) => OnboardingStore(),
);

/// Whether the introduction was finished or skipped on this device.
///
/// Loading until the flag is read. The router shows the introduction only
/// when this is `AsyncData(false)`.
final onboardingCompletedProvider =
    AsyncNotifierProvider<OnboardingCompletedNotifier, bool>(
      OnboardingCompletedNotifier.new,
    );

/// State of [onboardingCompletedProvider].
class OnboardingCompletedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(onboardingStoreProvider).isCompleted();

  /// Marks the introduction as done, at once for this session and then on
  /// disk. If saving fails it is logged; the introduction then shows again on
  /// the next launch only.
  Future<void> markCompleted() async {
    final store = ref.read(onboardingStoreProvider);
    state = const AsyncData(true);
    try {
      await store.markCompleted();
    } on Object catch (error) {
      AppLogger.warn('Could not save that onboarding was completed', error);
    }
  }
}

/// Whether the first-expense tip was dismissed on this device.
final firstExpenseNudgeDismissedProvider =
    AsyncNotifierProvider<FirstExpenseNudgeDismissedNotifier, bool>(
      FirstExpenseNudgeDismissedNotifier.new,
    );

/// State of [firstExpenseNudgeDismissedProvider].
class FirstExpenseNudgeDismissedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.watch(onboardingStoreProvider).isFirstExpenseNudgeDismissed();

  /// Hides the tip at once and remembers it on this device.
  Future<void> dismiss() async {
    final store = ref.read(onboardingStoreProvider);
    state = const AsyncData(true);
    try {
      await store.dismissFirstExpenseNudge();
    } on Object catch (error) {
      AppLogger.warn(
        'Could not save that the first-expense tip was hidden',
        error,
      );
    }
  }
}
