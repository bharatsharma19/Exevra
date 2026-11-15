import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_failure.dart';
import '../core/logging/app_logger.dart';
import '../core/platform/device_time_zone.dart';
import '../core/storage/preferences.dart';
import '../core/utils/app_locale.dart';
import '../core/utils/haptics.dart';
import '../data/repositories/profile_repository.dart';
import '../models/currency_info.dart';
import '../models/json_reader.dart';
import '../models/profile.dart';
import 'auth_provider.dart';
import 'failure_reporter.dart';

/// The device locale as a BCP-47 tag (for example `en-IN`).
final deviceLocaleProvider = Provider<String>(
  (ref) => AppLocale.toBcp47(PlatformDispatcher.instance.locale),
);

/// Theme preference for this device. It survives sign-out; when a profile
/// loads, the server value wins and is copied here.
class ThemePreferenceNotifier extends Notifier<ThemePreference> {
  @override
  ThemePreference build() {
    final stored = ref
        .watch(sharedPreferencesProvider)
        .getString(AppConstants.keyThemeMode);
    return ThemePreference.values.asNameMap()[stored] ?? ThemePreference.system;
  }

  /// Stores [mode] on this device only.
  Future<void> setLocal(ThemePreference mode) async {
    state = mode;
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setString(AppConstants.keyThemeMode, mode.name);
    } on Object catch (e) {
      AppLogger.warn('Could not save the theme', e.runtimeType);
    }
  }
}

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, ThemePreference>(
      ThemePreferenceNotifier.new,
    );

/// The signed-in user's profile. Null when signed out. Rebuilt (and
/// refetched) whenever the user changes.
class ProfileNotifier extends AsyncNotifier<UserProfile?> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  Future<UserProfile?> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return null;

    final cachedHaptics = ref
        .read(sharedPreferencesProvider)
        .getBool(UserPrefs.key(userId, UserPrefs.haptics));
    if (cachedHaptics != null) AppHaptics.isEnabled = cachedHaptics;

    final profile = await ref.watch(profileRepositoryProvider).fetch(userId);
    // Side effects on other providers run after this build completes.
    unawaited(Future(() => _afterLoad(userId, profile)));
    return profile;
  }

  Future<void> _afterLoad(String userId, UserProfile profile) async {
    if (!_isFor(userId)) return;
    await _applyLocally(userId, profile);
    await _syncDeviceSettings(userId, profile);
  }

  /// Whether a result for [userId] may still be applied. The notifier is
  /// reused across sign-ins, so after an await the signed-in user (and the
  /// loaded profile) may be someone else's.
  bool _isFor(String userId) {
    if (!ref.mounted || ref.read(currentUserIdProvider) != userId) {
      return false;
    }
    final owner = state.value?.id;
    return owner == null || owner == userId;
  }

  /// Mirrors server preferences on the device (server wins).
  Future<void> _applyLocally(String userId, UserProfile profile) async {
    if (!_isFor(userId)) return;
    AppHaptics.isEnabled = profile.hapticsEnabled;
    final themes = ref.read(themePreferenceProvider.notifier);
    if (ref.read(themePreferenceProvider) != profile.themeMode) {
      await themes.setLocal(profile.themeMode);
    }
    // Signing out meanwhile clears this user's keys; do not write them back.
    if (!_isFor(userId)) return;
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setBool(
            UserPrefs.key(userId, UserPrefs.haptics),
            profile.hapticsEnabled,
          );
    } on Object catch (e) {
      AppLogger.warn('Could not cache a preference', e.runtimeType);
    }
  }

  /// Stores the device time zone, and on first use the device locale and
  /// its currency, on the profile. Failures are logged, not shown.
  Future<void> _syncDeviceSettings(String userId, UserProfile profile) async {
    try {
      final zone = await ref.read(deviceTimeZoneProvider.future);
      final locale = ref.read(deviceLocaleProvider);
      final firstRun = profile.locale == null;
      final deviceCurrency = AppLocale.currencyFor(locale);
      final update = ProfileUpdate(
        timezone: profile.timezone == zone ? null : zone,
        locale: firstRun ? locale : unset,
        currency:
            firstRun &&
                profile.currency == CurrencyInfo.fallbackCode &&
                deviceCurrency != profile.currency
            ? deviceCurrency
            : null,
      );
      if (update.isEmpty || !_isFor(userId)) return;
      final saved = await _repo.update(userId, update);
      if (_isFor(userId)) state = AsyncData(saved);
    } on AppFailure catch (failure) {
      AppLogger.warn('Device settings were not synced', failure);
    }
  }

  /// Writes [update] (only the fields it sets), showing it immediately and
  /// rolling back on failure. Returns the failure, or null on success.
  Future<AppFailure?> updateProfile(ProfileUpdate update) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return const AppFailure.sessionExpired();
    final before = state.value;
    if (before == null || before.id != userId) {
      // The profile has not loaded (or failed to): nothing to change yet.
      const failure = AppFailure.notFound(key: 'profile_not_found');
      if (ref.mounted) {
        ref.read(failureReporterProvider.notifier).report(failure);
      }
      return failure;
    }
    state = AsyncData(before.apply(update));
    try {
      final saved = await _repo.update(userId, update);
      if (_isFor(userId)) {
        state = AsyncData(saved);
        await _applyLocally(userId, saved);
      }
      return null;
    } on AppFailure catch (failure) {
      if (_isFor(userId)) {
        state = AsyncData(before);
        ref.read(failureReporterProvider.notifier).report(failure);
      }
      return failure;
    }
  }

  Future<AppFailure?> setCurrency(String currency) =>
      updateProfile(ProfileUpdate(currency: currency));

  Future<AppFailure?> setHapticsEnabled(bool enabled) {
    AppHaptics.isEnabled = enabled;
    return updateProfile(ProfileUpdate(hapticsEnabled: enabled));
  }

  Future<AppFailure?> setAiConsent(bool consent) =>
      updateProfile(ProfileUpdate(aiConsent: consent));

  Future<AppFailure?> updateIdentity({
    String? displayName,
    Object? avatarUrl = unset,
  }) => updateProfile(
    ProfileUpdate(displayName: displayName, avatarUrl: avatarUrl),
  );

  /// Applies the theme on the device right away and saves it to the
  /// profile when signed in.
  Future<AppFailure?> setThemeMode(ThemePreference mode) async {
    await ref.read(themePreferenceProvider.notifier).setLocal(mode);
    if (state.value == null) return null;
    return updateProfile(ProfileUpdate(themeMode: mode));
  }

  /// Records the active group after the server changed it (no write).
  void setActiveGroupLocally(String? groupId) {
    final current = state.value;
    if (current == null || current.activeGroupId == groupId) return;
    state = AsyncData(current.copyWith(activeGroupId: groupId));
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, UserProfile?>(
  ProfileNotifier.new,
);

/// The loaded profile of the signed-in user, or null while loading, on
/// error or when signed out. A profile left over from a previous user
/// (while the next one loads) is never returned.
final userProfileProvider = Provider<UserProfile?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final profile = ref.watch(profileProvider).value;
  return profile != null && profile.id == userId ? profile : null;
});

/// Currency for new personal expenses: the profile's, else the device's.
final preferredCurrencyProvider = Provider<String>((ref) {
  final profile = ref.watch(userProfileProvider);
  return profile?.currency ??
      AppLocale.currencyFor(ref.watch(deviceLocaleProvider));
});
