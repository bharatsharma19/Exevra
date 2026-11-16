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
    return AppCard(
      key: const Key('profile-header'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          AppAvatar(
            name: name,
            radius: 32,
            semanticLabel: l10n.profileAvatarLabel(name),
            image: url != null && url.startsWith('https://')
                ? NetworkImage(url)
                : null,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onEdit != null)
            AppIconButton(
              key: const Key('profile-edit'),
              icon: Icons.edit_outlined,
              tooltip: l10n.profileEditTooltip,
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}
