import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure_messages.dart';
import '../../../core/platform/share_service.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/group.dart';
import '../../../models/invitation.dart';
import '../../../providers/group_detail_providers.dart';
import 'group_dialogs.dart';

/// Invites someone by email (admin only).
Future<void> showInviteByEmailDialog(
  BuildContext context,
  WidgetRef ref,
  Group group,
) {
  var emailText = '';
  var role = GroupRole.member;
  var busy = false;
  String? fieldError;
  String? error;

  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final l10n = ctx.l10n;
        Future<void> submit() async {
          final email = emailText.trim().toLowerCase();
          final invalid = Validators.validateEmail(email);
          if (invalid != null) {
            setState(() => fieldError = invalid);
            return;
          }
          setState(() {
            busy = true;
            fieldError = null;
            error = null;
          });
          final (sent, failure) = await ref
              .read(pendingInvitationsProvider(group.id).notifier)
              .send(email, role: role, report: false);
          if (!ctx.mounted) return;
          if (failure != null || sent == null) {
            setState(() {
              busy = false;
              error = failure == null ? null : friendlyMessage(failure);
            });
            return;
          }
          Navigator.of(ctx).pop();
          if (context.mounted) {
            await showInvitationResult(context, ref, email, sent);
          }
        }

        return AlertDialog(
          scrollable: true,
          title: Text(l10n.groupsInviteTitle),
          content: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.groupsInviteIntro(group.name)),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('invite-email'),
                  onChanged: (value) => emailText = value,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  // Done on the keyboard sends, like the Send button.
                  onSubmitted: (_) {
                    if (!busy) unawaited(submit());
                  },
                  decoration: InputDecoration(
                    labelText: l10n.groupsInviteEmailLabel,
                    hintText: l10n.authEmailHint,
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                    errorText: fieldError,
                    errorMaxLines: 3,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<GroupRole>(
                  isExpanded: true,
                  initialValue: role,
                  decoration: InputDecoration(
                    labelText: l10n.groupsInviteRoleLabel,
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: GroupRole.member,
                      child: Text(
                        l10n.groupsRoleMemberLong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: GroupRole.viewer,
                      child: Text(
                        l10n.groupsRoleViewerLong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => role = value);
                        },
                ),
                if (error != null) DialogError(error!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            LoadingButton(
              key: const Key('invite-send'),
              expand: false,
              isLoading: busy,
              label: l10n.groupsInviteSend,
              onPressed: submit,
            ),
          ],
        );
      },
    ),
  );
}

/// Says honestly what happened: "Email sent" only when the server sent
/// it. Otherwise the invitation exists but was not emailed, so the link is
/// offered to share by hand (share sheet, or copy).
Future<void> showInvitationResult(
  BuildContext context,
  WidgetRef ref,
  String email,
  SentInvitation sent,
) async {
  final l10n = context.l10n;
  if (sent.sent) {
    showMessage(
      context,
      l10n.groupsInviteEmailSent(email),
      kind: AppSnackbarKind.success,
    );
    return;
  }
  final link = sent.shareUrl;
  if (link == null) {
    // Not emailed and no link to share: never claim it was sent.
    showMessage(context, l10n.groupsInviteNotEmailed(email));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.link_rounded),
      title: Text(l10n.groupsInviteShareTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.groupsInviteShareMessage(email)),
          const SizedBox(height: AppSpacing.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: ctx.palette.surfaceVariant,
              borderRadius: AppRadius.smAll,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: SelectableText(
                link,
                key: const Key('invite-share-link'),
                style: TextStyle(color: ctx.palette.textPrimary),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            AppHaptics.selection();
            await Clipboard.setData(ClipboardData(text: link));
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (context.mounted) {
              showMessage(
                context,
                l10n.groupsInviteLinkCopied,
                kind: AppSnackbarKind.success,
              );
            }
          },
          child: Text(l10n.groupsCopyLink),
        ),
        FilledButton.icon(
          key: const Key('invite-share'),
          onPressed: () async {
            AppHaptics.selection();
            final shared = await ref
                .read(shareServiceProvider)
                .shareText(
                  l10n.groupsInviteShareText(link),
                  subject: l10n.groupsInviteShareSubject,
                );
            if (!shared) {
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) {
                showMessage(context, l10n.groupsShareFallbackCopied);
              }
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          icon: const Icon(Icons.share_rounded, size: AppSizes.iconSm),
          label: Text(l10n.groupsShare),
        ),
      ],
    ),
  );
}

/// Shares a fresh invite code (the old one no longer works).
Future<void> shareInviteCode(
  BuildContext context,
  WidgetRef ref,
  Group group,
  String displayCode,
) async {
  final l10n = context.l10n;
  final text = l10n.groupsInviteCodeShareText(group.name, displayCode);
  final shared = await ref
      .read(shareServiceProvider)
      .shareText(text, subject: l10n.groupsInviteCodeShareSubject(group.name));
  if (shared) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showMessage(context, l10n.groupsInviteCodeCopied);
}

/// Copies [text] and confirms it with [confirmation].
void copyToClipboard(BuildContext context, String text, String confirmation) {
  AppHaptics.selection();
  unawaited(Clipboard.setData(ClipboardData(text: text)));
  showMessage(context, confirmation, kind: AppSnackbarKind.success);
}
