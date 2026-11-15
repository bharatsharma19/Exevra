import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// A round avatar: the person's photo when [image] loads, otherwise their
/// initials on a tinted container colour picked from [name], so the same
/// person always gets the same colour. Every colour pair is a palette
/// container and its on-colour (at least 4.5:1).
///
/// Screen readers hear [semanticLabel] or [name], not the initials.
class AppAvatar extends StatelessWidget {
  /// Creates an avatar.
  const AppAvatar({
    required this.name,
    this.image,
    this.radius = 20,
    this.semanticLabel,
    super.key,
  });

  /// The person's display name.
  final String name;

  /// Optional photo.
  final ImageProvider? image;

  /// Circle radius.
  final double radius;

  /// Screen reader label. Defaults to [name].
  final String? semanticLabel;

  /// Up to two initials of [name] ("Priya Sharma" -> "PS"), or "?" when it is
  /// blank.
  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final last = parts.length > 1 ? parts.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  /// Index of the colour pair for [name], stable across runs.
  static int colorIndexOf(String name, int count) {
    var hash = 0;
    for (final unit in name.trim().toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % count;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pairs = [
      (p.accentContainer, p.onAccentContainer),
      (p.secondaryContainer, p.onSecondaryContainer),
      (p.successContainer, p.onSuccessContainer),
      (p.infoContainer, p.onInfoContainer),
      (p.warningContainer, p.onWarningContainer),
    ];
    final (background, foreground) = pairs[colorIndexOf(name, pairs.length)];
    return Semantics(
      label: semanticLabel ?? name,
      image: true,
      excludeSemantics: true,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: background,
        foregroundImage: image,
        onForegroundImageError: image == null ? null : (_, _) {},
        child: Padding(
          padding: EdgeInsets.all(radius * 0.25),
          // Initials are decorative (the name is the label), so they shrink
          // to fit the circle instead of overflowing at large text sizes.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              initialsOf(name),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
