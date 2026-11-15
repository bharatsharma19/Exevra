import 'currency_info.dart';
import 'json_reader.dart';

/// Theme preference stored on the device and in `profiles.theme_mode`.
enum ThemePreference { system, light, dark }

/// The signed-in user's own profile row and preferences.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.avatarUrl,
    this.activeGroupId,
    this.currency = CurrencyInfo.fallbackCode,
    this.timezone = 'Asia/Kolkata',
    this.locale,
    this.themeMode = ThemePreference.system,
    this.hapticsEnabled = true,
    this.aiConsent = false,
    this.aiConsentAt,
  });

  static const String columns =
      'id,display_name,avatar_url,email,group_id,currency,timezone,locale,'
      'theme_mode,haptics_enabled,ai_consent,ai_consent_at,created_at,'
      'updated_at';

  final String id;
  final String displayName;
  final String? email;
  final String? avatarUrl;

  /// Active group (`profiles.group_id`). Null means personal mode. Changed
  /// only through `set_active_group`.
  final String? activeGroupId;

  final String currency;

  /// IANA time zone, for example `Asia/Kolkata`.
  final String timezone;

  /// BCP-47 tag such as `en-IN`; null until first set from the device.
  final String? locale;

  final ThemePreference themeMode;
  final bool hapticsEnabled;
  final bool aiConsent;
  final DateTime? aiConsentAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserProfile.fromJson(Object? data) {
    final r = JsonReader.of(data, 'UserProfile');
    final currency = r.optString('currency')?.trim().toUpperCase();
    return UserProfile(
      id: r.nonEmpty('id'),
      displayName: r.optString('display_name') ?? '',
      email: r.optString('email'),
      avatarUrl: r.optString('avatar_url'),
      activeGroupId: r.optString('group_id'),
      currency: CurrencyInfo.isSupported(currency)
          ? currency!
          : CurrencyInfo.fallbackCode,
      timezone: r.optString('timezone') ?? 'Asia/Kolkata',
      locale: r.optString('locale'),
      themeMode: r.enumValue(
        'theme_mode',
        ThemePreference.values,
        fallback: ThemePreference.system,
      ),
      hapticsEnabled: r.boolean('haptics_enabled', fallback: true),
      aiConsent: r.boolean('ai_consent', fallback: false),
      aiConsentAt: r.optInstant('ai_consent_at'),
      createdAt: r.instant('created_at'),
      updatedAt: r.instant('updated_at'),
    );
  }

  /// Applies the fields set in [update] (used for optimistic UI).
  UserProfile apply(ProfileUpdate update) {
    final f = update.fields;
    return copyWith(
      displayName: f['display_name'] as String?,
      avatarUrl: f.containsKey('avatar_url') ? f['avatar_url'] : unset,
      currency: f['currency'] as String?,
      timezone: f['timezone'] as String?,
      locale: f.containsKey('locale') ? f['locale'] : unset,
      themeMode: f.containsKey('theme_mode')
          ? ThemePreference.values.byName(f['theme_mode']! as String)
          : null,
      hapticsEnabled: f['haptics_enabled'] as bool?,
      aiConsent: f['ai_consent'] as bool?,
    );
  }

  UserProfile copyWith({
    String? displayName,
    Object? email = unset,
    Object? avatarUrl = unset,
    Object? activeGroupId = unset,
    String? currency,
    String? timezone,
    Object? locale = unset,
    ThemePreference? themeMode,
    bool? hapticsEnabled,
    bool? aiConsent,
    Object? aiConsentAt = unset,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      email: pick<String?>(email, this.email),
      avatarUrl: pick<String?>(avatarUrl, this.avatarUrl),
      activeGroupId: pick<String?>(activeGroupId, this.activeGroupId),
      currency: currency ?? this.currency,
      timezone: timezone ?? this.timezone,
      locale: pick<String?>(locale, this.locale),
      themeMode: themeMode ?? this.themeMode,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      aiConsent: aiConsent ?? this.aiConsent,
      aiConsentAt: pick<DateTime?>(aiConsentAt, this.aiConsentAt),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.id == id &&
      other.displayName == displayName &&
      other.email == email &&
      other.avatarUrl == avatarUrl &&
      other.activeGroupId == activeGroupId &&
      other.currency == currency &&
      other.timezone == timezone &&
      other.locale == locale &&
      other.themeMode == themeMode &&
      other.hapticsEnabled == hapticsEnabled &&
      other.aiConsent == aiConsent;

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    avatarUrl,
    activeGroupId,
    currency,
    themeMode,
    aiConsent,
  );
}

/// A partial profile update: only the columns that were set are written.
///
/// The client never writes `id`, `email`, `group_id` or timestamps; the
/// active group goes through `set_active_group`.
class ProfileUpdate {
  ProfileUpdate({
    String? displayName,
    Object? avatarUrl = unset,
    String? currency,
    String? timezone,
    Object? locale = unset,
    ThemePreference? themeMode,
    bool? hapticsEnabled,
    bool? aiConsent,
  }) : fields = {
         'display_name': ?displayName?.trim(),
         if (!identical(avatarUrl, unset)) 'avatar_url': avatarUrl as String?,
         'currency': ?currency,
         'timezone': ?timezone,
         if (!identical(locale, unset)) 'locale': locale as String?,
         'theme_mode': ?themeMode?.name,
         'haptics_enabled': ?hapticsEnabled,
         'ai_consent': ?aiConsent,
       };

  /// Column name to value, only for the fields being changed.
  final Map<String, Object?> fields;

  bool get isEmpty => fields.isEmpty;

  /// Client-side checks matching the database constraints. Returns a
  /// validation message key or null.
  String? validate() {
    final name = fields['display_name'];
    if (name is String && (name.isEmpty || name.length > 60)) {
      return 'invalid_display_name';
    }
    final avatar = fields['avatar_url'];
    if (avatar is String &&
        !(avatar.startsWith('https://') && avatar.length <= 2048)) {
      return 'invalid_avatar_url';
    }
    final currency = fields['currency'];
    if (currency is String && !CurrencyInfo.isSupported(currency)) {
      return 'invalid_currency';
    }
    return null;
  }
}
