import '../core/constants/app_constants.dart';

/// Model representing the user's profile and preferences
class UserProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final String? phone;
  final String? email;
  final String? groupId;
  final String currency;
  final String themeMode; // 'system', 'light', 'dark'
  final bool hapticsEnabled;
  final bool aiConsent;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.phone,
    this.email,
    this.groupId,
    this.currency = AppConstants.defaultCurrency,
    this.themeMode = 'system',
    this.hapticsEnabled = true,
    this.aiConsent = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String? ?? 'User',
      avatarUrl: json['avatar_url'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      groupId: json['group_id'] as String?,
      currency: json['currency'] as String? ?? AppConstants.defaultCurrency,
      themeMode: json['theme_mode'] as String? ?? 'system',
      hapticsEnabled: json['haptics_enabled'] as bool? ?? true,
      aiConsent: json['ai_consent'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'phone': phone,
      'email': email,
      'group_id': groupId,
      'currency': currency,
      'theme_mode': themeMode,
      'haptics_enabled': hapticsEnabled,
      'ai_consent': aiConsent,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? displayName,
    String? avatarUrl,
    String? phone,
    String? email,
    String? groupId,
    String? currency,
    String? themeMode,
    bool? hapticsEnabled,
    bool? aiConsent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      groupId: groupId ?? this.groupId,
      currency: currency ?? this.currency,
      themeMode: themeMode ?? this.themeMode,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      aiConsent: aiConsent ?? this.aiConsent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
