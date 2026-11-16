import 'package:flutter/painting.dart';

/// Colours fixed by third-party branding guidelines. They are not part of
/// `AppPalette` because the brand owner, not the app theme, defines them.
///
/// Google's sign-in button guidelines define a light variant (white fill,
/// grey stroke, near-black label) and a dark variant (near-black fill, grey
/// stroke, light label); both keep their label above 4.5:1 and their stroke
/// above 3:1 against Exevra's pages.
abstract final class GoogleBrandColors {
  /// Red of the Google "G" logo.
  static const Color red = Color(0xFFEA4335);

  /// Blue of the Google "G" logo.
  static const Color blue = Color(0xFF4285F4);

  /// Yellow of the Google "G" logo.
  static const Color yellow = Color(0xFFFBBC05);

  /// Green of the Google "G" logo.
  static const Color green = Color(0xFF34A853);

  /// Fill of the light button.
  static const Color lightFill = Color(0xFFFFFFFF);

  /// Stroke of the light button.
  static const Color lightStroke = Color(0xFF747775);

  /// Label of the light button.
  static const Color lightLabel = Color(0xFF1F1F1F);

  /// Fill of the dark button.
  static const Color darkFill = Color(0xFF131314);

  /// Stroke of the dark button.
  static const Color darkStroke = Color(0xFF8E918F);

  /// Label of the dark button.
  static const Color darkLabel = Color(0xFFE3E3E3);
}
