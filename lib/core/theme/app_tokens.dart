import 'package:flutter/widgets.dart';

/// Spacing scale (logical pixels). Use these instead of ad-hoc numbers.
abstract final class AppSpacing {
  /// 2
  static const double xxs = 2;

  /// 4
  static const double xs = 4;

  /// 8
  static const double sm = 8;

  /// 12
  static const double md = 12;

  /// 16, also the horizontal page gutter.
  static const double lg = 16;

  /// 24
  static const double xl = 24;

  /// 32
  static const double xxl = 32;

  /// 48
  static const double xxxl = 48;

  /// Horizontal page gutter.
  static const double gutter = lg;

  /// Default padding inside cards.
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  /// Default page padding (horizontal gutter only).
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: gutter);
}

/// Corner radius scale.
abstract final class AppRadius {
  /// 8: chips, small badges, tooltips.
  static const double sm = 8;

  /// 12: buttons, inputs, list tiles, snackbars.
  static const double md = 12;

  /// 16: cards.
  static const double lg = 16;

  /// 20: dialogs and hero cards.
  static const double xl = 20;

  /// 28: top corners of bottom sheets.
  static const double xxl = 28;

  /// Fully rounded (pills).
  static const double pill = 999;

  /// [sm] on all corners.
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));

  /// [md] on all corners.
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));

  /// [lg] on all corners.
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));

  /// [xl] on all corners.
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));

  /// [pill] on all corners.
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));

  /// [xxl] on the top corners only (bottom sheets).
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(xxl),
  );
}

/// Elevation scale. Surfaces are mostly flat; shadows mark overlays.
abstract final class AppElevation {
  /// Flat surfaces (cards, app bar, navigation bar).
  static const double none = 0;

  /// Resting raised elements (FAB).
  static const double low = 2;

  /// Floating elements (snackbars, menus).
  static const double medium = 4;

  /// Modal surfaces (dialogs, sheets).
  static const double high = 8;
}

/// Animation durations. Animated widgets must skip or shorten motion when
/// `context.reduceMotion` is true.
abstract final class AppDurations {
  /// 150 ms: small state changes (press, toggle).
  static const Duration fast = Duration(milliseconds: 150);

  /// 250 ms: standard transitions.
  static const Duration medium = Duration(milliseconds: 250);

  /// 400 ms: large or entrance transitions.
  static const Duration slow = Duration(milliseconds: 400);

  /// One sweep of the skeleton shimmer.
  static const Duration shimmer = Duration(milliseconds: 1200);

  /// How long a regular snackbar stays on screen.
  static const Duration snackbar = Duration(seconds: 4);

  /// How long an undo snackbar stays on screen.
  static const Duration undoSnackbar = Duration(seconds: 6);
}

/// Component sizes.
abstract final class AppSizes {
  /// Minimum touch target (Material and WCAG 2.5.8 guidance).
  static const double minTapTarget = 48;

  /// Minimum touch target as a [Size].
  static const Size minTapTargetSize = Size.square(minTapTarget);

  /// Small icon.
  static const double iconSm = 18;

  /// Standard icon.
  static const double icon = 24;

  /// Large icon (empty and error states).
  static const double iconLg = 48;

  /// Minimum height of primary buttons.
  static const double buttonHeight = 52;

  /// Diameter of a spinner inside a button.
  static const double buttonSpinner = 20;
}
