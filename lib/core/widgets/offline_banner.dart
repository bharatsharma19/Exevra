import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../accessibility/reduce_motion.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A banner telling the user they are offline. Slides in and out with
/// [visible] (instantly under reduced motion) and is announced to screen
/// readers when it appears.
class OfflineBanner extends StatelessWidget {
  /// Creates the banner.
  const OfflineBanner({this.visible = true, this.message, super.key});

  /// Whether the banner is shown.
  final bool visible;

  /// Supporting text. Defaults to "Some actions need an internet connection."
  final String? message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final banner = Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: palette.warningContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.wifi_off,
                    color: palette.onWarningContainer,
                    size: AppSizes.icon,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.offlineTitle,
                        style: textTheme.titleSmall?.copyWith(
                          color: palette.onWarningContainer,
                        ),
                      ),
                      Text(
                        message ?? l10n.offlineMessage,
                        style: textTheme.bodySmall?.copyWith(
                          color: palette.onWarningContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return AnimatedSize(
      duration: context.reduceMotion ? Duration.zero : AppDurations.medium,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: visible ? banner : const SizedBox(width: double.infinity),
    );
  }
}
