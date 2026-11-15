import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// The Exevra text logo: an accent monogram tile and the wordmark, with an
/// optional "Expense & Split Tracker" tagline. Read as one label by screen
/// readers.
class BrandMark extends StatelessWidget {
  /// Creates the logo.
  const BrandMark({this.size = 28, this.showTagline = false, super.key});

  /// Font size of the wordmark; the monogram scales with it.
  final double size;

  /// Whether to show the tagline under the wordmark.
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final tile = size * 1.4;
    return Semantics(
      label: showTagline ? '${l10n.appName}, ${l10n.appTagline}' : l10n.appName,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: tile,
            height: tile,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(tile * 0.28),
            ),
            child: Text(
              l10n.appName.characters.first,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: size * 0.9,
                height: 1,
                fontWeight: FontWeight.w800,
                color: palette.textOnAccent,
              ),
            ),
          ),
          SizedBox(width: size * 0.4),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.appName,
                  style: TextStyle(
                    fontSize: size,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: palette.textPrimary,
                  ),
                ),
                if (showTagline) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.appTagline,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
