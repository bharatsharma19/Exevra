import 'package:flutter/material.dart';

import '../accessibility/focus_outline.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A list row with at least a 48 dp touch target, merged semantics and text
/// that wraps instead of overflowing.
///
/// Screen readers read the whole row as one item ("Groceries, Today, ₹250");
/// pass [semanticLabel] to replace that with a custom sentence.
///
/// At large text sizes (150% and up) the [trailing] widget moves under the
/// text, so a wide amount or badge cannot squeeze the title into a sliver.
///
/// A [selected] row gets an accent outline on top of the pale selected fill,
/// so selection does not depend on a low-contrast fill alone, and a focused
/// row draws a focus ring.
class AppListTile extends StatelessWidget {
  /// Creates a list row.
  const AppListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.selected = false,
    this.semanticLabel,
    this.titleMaxLines = 2,
    this.subtitleMaxLines = 2,
    super.key,
  });

  /// Main text.
  final String title;

  /// Secondary text under [title].
  final String? subtitle;

  /// Leading widget (icon or avatar).
  final Widget? leading;

  /// Trailing widget (amount, chevron, switch).
  final Widget? trailing;

  /// Tap handler.
  final VoidCallback? onTap;

  /// Long-press handler.
  final VoidCallback? onLongPress;

  /// Whether the row is interactive.
  final bool enabled;

  /// Whether the row is shown as selected.
  final bool selected;

  /// Replaces the merged screen reader label.
  final String? semanticLabel;

  /// Maximum lines for [title] before ellipsis.
  final int titleMaxLines;

  /// Maximum lines for [subtitle] before ellipsis.
  final int subtitleMaxLines;

  /// Text scale from which [trailing] is placed under the text.
  static const double largeTextScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stackTrailing =
        trailing != null &&
        MediaQuery.textScalerOf(context).scale(1) >= largeTextScale;
    final subtitleText = subtitle == null
        ? null
        : Text(
            subtitle!,
            maxLines: subtitleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: enabled ? palette.textSecondary : palette.textTertiary,
            ),
          );
    Widget tile = ListTile(
      minTileHeight: AppSizes.minTapTarget,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: AppRadius.mdAll,
              side: BorderSide(color: palette.accent, width: 2),
            )
          : null,
      enabled: enabled,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: leading,
      trailing: stackTrailing ? null : trailing,
      title: Text(
        title,
        maxLines: titleMaxLines,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: stackTrailing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?subtitleText,
                const SizedBox(height: AppSpacing.xs),
                trailing!,
              ],
            )
          : subtitleText,
    );
    if (enabled && (onTap != null || onLongPress != null)) {
      tile = FocusOutline(borderRadius: AppRadius.mdAll, child: tile);
    }
    if (semanticLabel != null) {
      return Semantics(
        label: semanticLabel,
        button: onTap != null,
        enabled: enabled,
        selected: selected,
        excludeSemantics: true,
        onTap: enabled ? onTap : null,
        child: tile,
      );
    }
    return MergeSemantics(child: tile);
  }
}
