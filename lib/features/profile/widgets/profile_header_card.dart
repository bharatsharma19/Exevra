import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';

/// The signed-in user's photo (or initials), name and email, with an edit
/// button.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({
    super.key,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.onEdit,
  });

  final String name;
  final String email;

  /// Only https links are loaded; anything else shows the initials.
  final String? avatarUrl;

  /// Opens the edit dialog; null hides the button (profile not loaded).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final url = avatarUrl;
    final avatar = AppAvatar(
      name: name,
      radius: 32,
      semanticLabel: l10n.profileAvatarLabel(name),
      image: url != null && url.startsWith('https://')
          ? NetworkImage(url)
          : null,
    );
    final edit = onEdit == null
        ? null
        : AppIconButton(
            key: const Key('profile-edit'),
            icon: Icons.edit_outlined,
            tooltip: l10n.profileEditTooltip,
            onPressed: onEdit,
          );
    return AppCard(
      key: const Key('profile-header'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // When the space beside the photo is short for the text size
          // (narrow screens, large text), the name and email get the full
          // width under it, so they wrap instead of being cut to a few
          // letters.
          final beside =
              constraints.maxWidth -
              64 -
              AppSpacing.lg -
              (edit == null ? 0 : AppSizes.minTapTarget);
          final stacked = beside < MediaQuery.textScalerOf(context).scale(120);
          final lines = stacked ? 4 : 2;
          final identity = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                key: const Key('profile-name'),
                maxLines: lines,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  email,
                  key: const Key('profile-email'),
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ],
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [avatar, const Spacer(), ?edit],
                ),
                const SizedBox(height: AppSpacing.md),
                identity,
              ],
            );
          }
          return Row(
            children: [
              avatar,
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: identity),
              ?edit,
            ],
          );
        },
      ),
    );
  }
}
