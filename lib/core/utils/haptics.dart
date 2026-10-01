import 'package:flutter/services.dart';

/// Tactile Haptic Feedback Utility respecting user preferences
class AppHaptics {
  AppHaptics._();

  static bool isEnabled = true;

  static void light() {
    if (!isEnabled) return;
    HapticFeedback.lightImpact();
  }

  static void medium() {
    if (!isEnabled) return;
    HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (!isEnabled) return;
    HapticFeedback.heavyImpact();
  }

  static void selection() {
    if (!isEnabled) return;
    HapticFeedback.selectionClick();
  }

  static void success() {
    if (!isEnabled) return;
    HapticFeedback.mediumImpact();
  }

  static void error() {
    if (!isEnabled) return;
    HapticFeedback.heavyImpact();
  }
}
