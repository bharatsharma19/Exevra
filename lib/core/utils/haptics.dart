import 'dart:async';

import 'package:flutter/services.dart';

/// Tactile Haptic Feedback Utility respecting user preferences
class AppHaptics {
  AppHaptics._();

  static bool isEnabled = true;

  static void light() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.lightImpact());
  }

  static void medium() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.mediumImpact());
  }

  static void heavy() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.heavyImpact());
  }

  static void selection() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.selectionClick());
  }

  static void success() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.mediumImpact());
  }

  static void error() {
    if (!isEnabled) return;
    unawaited(HapticFeedback.heavyImpact());
  }
}
