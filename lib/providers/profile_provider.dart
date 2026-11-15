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
import 'user_scoped.dart';

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

/// The signed-in user's profile. Null when signed out. Refetched whenever
/// the user changes, starting over at loading with no value (see
/// [UserScopedNotifier]).
///
/// Writes are optimistic. What is shown is the profile the server last
/// confirmed with every write still on its way applied in the order they
/// were made. Each column remembers the latest write confirmed for it, so
/// an older answer (success or failure) never undoes a newer write: a
/// failed write only drops its own change, and a column keeps the value of
/// the newest confirmed write.
///
/// A reload may have read the profile before a write was confirmed. Each
/// load is stamped with the confirmation count when it starts, and the
/// columns of writes confirmed after that keep their confirmed value when
/// the load lands; the other columns take the loaded value.
class ProfileNotifier extends UserScopedNotifier<UserProfile?> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  /// The profile as the server last confirmed it, per column.
  UserProfile? _confirmed;

  /// Writes on their way, by request number (oldest first).
  final Map<int, ProfileUpdate> _pending = {};
  int _requests = 0;

  /// Column to the number of the latest write confirmed for it.
  final Map<String, int> _confirmedWrites = {};

  /// Number of confirmed writes so far.
  int _confirmations = 0;

  /// Column to the value of [_confirmations] when a write of it was last
  /// confirmed.
  final Map<String, int> _columnConfirmedAt = {};

  /// [_confirmations] when the latest load started.
  int _loadStamp = 0;

  static const Set<String> _columns = {
    'display_name',
    'avatar_url',
    'currency',
    'timezone',
    'locale',
    'theme_mode',
    'haptics_enabled',
    'ai_consent',
  };

  @override
  AsyncValue<UserProfile?> whenSignedOut() => const AsyncData(null);

  @override
  String? ownerOf(UserProfile? value) => value?.id;

  @override
  Future<UserProfile?> fetch(String userId) {
    final cachedHaptics = ref
        .read(sharedPreferencesProvider)
        .getBool(UserPrefs.key(userId, UserPrefs.haptics));
    if (cachedHaptics != null) AppHaptics.isEnabled = cachedHaptics;
    if (owner != userId) {
      // Writes of another user are never applied to this profile.
      _confirmed = null;
      _pending.clear();
      _confirmedWrites.clear();
      _columnConfirmedAt.clear();
    }
    // Only the latest load is applied, so one stamp is enough.
    _loadStamp = _confirmations;
    return ref.watch(profileRepositoryProvider).fetch(userId);
  }

  @override
  void onLoaded(String userId, UserProfile? value) {
    if (value == null) return;
    final previous = _confirmed;
    // Columns written and confirmed after this load started: the loaded
    // row may predate those writes.
    final newer = {
      for (final MapEntry(key: column, value: at) in _columnConfirmedAt.entries)
        if (at > _loadStamp) column,
    };
    final merged = previous == null || newer.isEmpty
        ? value
        : _takeColumns(value, previous, newer).copyWith(
            updatedAt: previous.updatedAt.isAfter(value.updatedAt)
                ? previous.updatedAt
                : value.updatedAt,
          );
    _confirmed = merged;
    if (_pending.isNotEmpty || !identical(merged, value)) _show();
    final session = guard();
    if (session.userId != userId) return;
    unawaited(_afterLoad(session, merged));
  }

  /// Shows the confirmed profile with the writes on their way applied.
  void _show() {
    var profile = _confirmed;
    if (profile == null || !ref.mounted) return;
    for (final update in _pending.values) {
      profile = profile!.apply(update);
    }
    state = AsyncData(profile);
  }

  /// Takes the server's answer to write [request] ([update]): the columns
  /// it wrote, and the others, unless a newer write to that column was
  /// confirmed already.
  void _confirm(int request, ProfileUpdate update, UserProfile saved) {
    final base = _confirmed ?? saved;
    final take = {
      for (final column in _columns)
        if ((_confirmedWrites[column] ?? 0) <= request) column,
    };
    final confirmation = ++_confirmations;
    for (final column in update.fields.keys) {
      if ((_confirmedWrites[column] ?? 0) < request) {
        _confirmedWrites[column] = request;
      }
      _columnConfirmedAt[column] = confirmation;
    }
    _confirmed = _takeColumns(base, saved, take).copyWith(
      updatedAt: saved.updatedAt.isAfter(base.updatedAt)
          ? saved.updatedAt
          : base.updatedAt,
    );
  }

  /// [into] with the [columns] of [from].
  static UserProfile _takeColumns(
    UserProfile into,
    UserProfile from,
    Set<String> columns,
  ) => into.copyWith(
    displayName: columns.contains('display_name') ? from.displayName : null,
    avatarUrl: columns.contains('avatar_url') ? from.avatarUrl : unset,
    currency: columns.contains('currency') ? from.currency : null,
    timezone: columns.contains('timezone') ? from.timezone : null,
    locale: columns.contains('locale') ? from.locale : unset,
    themeMode: columns.contains('theme_mode') ? from.themeMode : null,
    hapticsEnabled: columns.contains('haptics_enabled')
        ? from.hapticsEnabled
        : null,
    aiConsent: columns.contains('ai_consent') ? from.aiConsent : null,
    aiConsentAt: columns.contains('ai_consent') ? from.aiConsentAt : unset,
  );

  /// Sends [update] for the user of [session], showing it right away.
  /// Returns the failure, or null once the server saved it. Only this
  /// write's own change is dropped when it fails. When the session ended
  /// meanwhile nothing is applied and [SessionGuard.dropped] is returned.
  Future<AppFailure?> _write(SessionGuard session, ProfileUpdate update) async {
    const action = 'a profile write';
    final userId = session.userId;
    if (userId == null || !_applies(session, action)) {
      return SessionGuard.dropped;
    }
    final request = ++_requests;
    _pending[request] = update;
    _show();
    try {
      final saved = await _repo.update(userId, update);
      if (!_applies(session, action)) return SessionGuard.dropped;
      _pending.remove(request);
      _confirm(request, update, saved);
      _show();
      return null;
    } on AppFailure catch (failure) {
      if (!_applies(session, action)) return SessionGuard.dropped;
      _pending.remove(request);
      _show();
      return failure;
    }
  }

  Future<void> _afterLoad(SessionGuard session, UserProfile profile) async {
    if (!_applies(session, 'a profile load')) return;
    await _applyLocally(session, profile);
    await _syncDeviceSettings(session, profile);
  }

  /// Whether a result of [action], started in [session], may still be
  /// applied: the session holds (see [SessionGuard]) and the loaded
  /// profile, if any, is that user's.
  bool _applies(SessionGuard session, String action) {
    if (!session.holds(action)) return false;
    final owner = state.value?.id;
    if (owner == null || owner == session.userId) return true;
    AppLogger.debug('Dropped the result of $action: another profile shows');
    return false;
  }

  /// Mirrors server preferences on the device (server wins).
  Future<void> _applyLocally(SessionGuard session, UserProfile profile) async {
    const action = 'a preference mirror';
    final userId = session.userId;
    if (userId == null || !_applies(session, action)) return;
    AppHaptics.isEnabled = profile.hapticsEnabled;
    final themes = ref.read(themePreferenceProvider.notifier);
    if (ref.read(themePreferenceProvider) != profile.themeMode) {
      await themes.setLocal(profile.themeMode);
    }
    // Signing out meanwhile clears this user's keys; do not write them back.
    if (!_applies(session, action)) return;
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
  Future<void> _syncDeviceSettings(
    SessionGuard session,
    UserProfile profile,
  ) async {
    const action = 'a device settings sync';
    try {
      if (!_applies(session, action)) return;
      final zone = await ref.read(deviceTimeZoneProvider.future);
      // The provider may be gone, or the session over, after the await.
      if (!_applies(session, action)) return;
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
      if (update.isEmpty) return;
      final failure = await _write(session, update);
      if (failure != null && session.isCurrent) {
        AppLogger.warn('Device settings were not synced', failure);
      }
    } on AppFailure catch (failure) {
      AppLogger.warn('Device settings were not synced', failure);
    }
  }

  /// Writes [update] (only the fields it sets), showing it immediately.
  /// On failure only this write's change is dropped (never a newer one).
  /// Returns the failure, or null on success.
  Future<AppFailure?> updateProfile(ProfileUpdate update) =>
      _update(guard(), update);

  Future<AppFailure?> _update(
    SessionGuard session,
    ProfileUpdate update,
  ) async {
    const action = 'a profile update';
    final userId = session.userId;
    if (userId == null) return const AppFailure.sessionExpired();
    if (!session.holds(action)) return SessionGuard.dropped;
    final before = state.value;
    if (before == null || before.id != userId) {
      // The profile has not loaded (or failed to): nothing to change yet.
      return session.fail(
        const AppFailure.notFound(key: 'profile_not_found'),
        action,
      );
    }
    _confirmed ??= before;
    final failure = await _write(session, update);
    if (!_applies(session, action)) return SessionGuard.dropped;
    if (failure != null) return session.fail(failure, action);
    final shown = state.value;
    if (shown != null) await _applyLocally(session, shown);
    return null;
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
    final session = guard();
    await ref.read(themePreferenceProvider.notifier).setLocal(mode);
    if (session.userId == null) return null;
    if (!session.holds('a theme change')) return SessionGuard.dropped;
    if (state.value == null) return null;
    return _update(session, ProfileUpdate(themeMode: mode));
  }

  /// Records the active group after the server changed it (no write).
  void setActiveGroupLocally(String? groupId) {
    final current = state.value;
    if (current == null || current.activeGroupId == groupId) return;
    _confirmed = _confirmed?.copyWith(activeGroupId: groupId);
    state = AsyncData(current.copyWith(activeGroupId: groupId));
  }
}

final profileProvider =
    NotifierProvider<ProfileNotifier, AsyncValue<UserProfile?>>(
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
