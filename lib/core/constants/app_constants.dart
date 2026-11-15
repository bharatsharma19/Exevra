import 'package:flutter/material.dart';

/// Core Application Constants & Configuration
class AppConstants {
  AppConstants._();

  static const String appName = 'Exevra';
  static const String appVersion = '1.0.0';
  static const String defaultCurrency = 'INR';

  // Supported Currencies (Default: INR for Indian Launch)
  static const Map<String, String> currencies = {
    'INR': '₹',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'CAD': 'C\$',
    'AUD': 'A\$',
    'SGD': 'S\$',
  };

  // Supported Categories with Associated Icons
  static const List<ExpenseCategoryInfo> categories = [
    ExpenseCategoryInfo(name: 'Food', icon: Icons.restaurant_rounded),
    ExpenseCategoryInfo(name: 'Transport', icon: Icons.directions_car_rounded),
    ExpenseCategoryInfo(name: 'Housing', icon: Icons.home_rounded),
    ExpenseCategoryInfo(
      name: 'Entertainment',
      icon: Icons.movie_filter_rounded,
    ),
    ExpenseCategoryInfo(name: 'Healthcare', icon: Icons.local_hospital_rounded),
    ExpenseCategoryInfo(name: 'Utilities', icon: Icons.bolt_rounded),
    ExpenseCategoryInfo(name: 'Shopping', icon: Icons.shopping_bag_rounded),
    ExpenseCategoryInfo(name: 'Personal', icon: Icons.person_rounded),
    ExpenseCategoryInfo(name: 'Education', icon: Icons.school_rounded),
    ExpenseCategoryInfo(name: 'Other', icon: Icons.category_rounded),
  ];

  static IconData getCategoryIcon(String category) {
    for (final item in categories) {
      if (item.name.toLowerCase() == category.toLowerCase()) {
        return item.icon;
      }
    }
    return Icons.category_rounded;
  }

  // Animation Timers & Physics
  static const Duration animDurationFast = Duration(milliseconds: 200);
  static const Duration animDurationMedium = Duration(milliseconds: 350);
  static const Duration animDurationSlow = Duration(milliseconds: 600);
  static const Curve defaultSpringCurve = Curves.easeOutCubic;

  // Local Storage Preference Keys
  static const String keyThemeMode = 'app_theme_mode';
  static const String keyCurrency = 'app_currency';
  static const String keyHapticsEnabled = 'app_haptics_enabled';
  static const String keyAiConsent = 'app_ai_consent';
  static const String keyCachedProfile = 'app_cached_profile';
  static const String keySecureToken = 'app_secure_token';
  static const String keyBiometricsEnabled = 'app_biometrics_enabled';
  static const int lockTimeoutSeconds = 30;

  // AI Financial Assistant Quick Prompts
  static const List<String> aiQuickPrompts = [
    'Analyze my top spending categories this month',
    'Where am I overspending compared to last week?',
    'Give me 3 actionable tips to cut expenses by 15%',
    'Explain the 50/30/20 budgeting rule for my income',
    'How much did our group spend on Food recently?',
  ];
}

class ExpenseCategoryInfo {
  final String name;
  final IconData icon;

  const ExpenseCategoryInfo({required this.name, required this.icon});
}
