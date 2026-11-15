import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure_messages.dart';
import '../../../core/platform/share_service.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/validators.dart';
import '../../../models/currency_info.dart';
import '../../../models/group.dart';
import '../../../models/invitation.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/profile_provider.dart';

/// Asks to confirm [title]. Completes with true only when confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: destructive
                ? ElevatedButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

void showMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// Inline error text for dialogs (errors are never shown under a modal).
class DialogError extends StatelessWidget {
  const DialogError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: TextStyle(color: scheme.error)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A primary dialog button that shows progress while [busy].
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool busy;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

/// Creates a group with a name and a fixed currency; it becomes active.
Future<void> showCreateGroupDialog(BuildContext context, WidgetRef ref) {
  // Plain values instead of controllers: nothing to dispose while the
  // dialog animates out.
  var nameText = '';
  var currency = ref.read(preferredCurrencyProvider);
  var busy = false;
  String? nameError;
  String? error;

  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> submit() async {
          final name = nameText.trim();
          if (name.isEmpty || name.length > 60) {
            setState(
              () => nameError = friendlyMessageForKey('invalid_group_name'),
            );
            return;
          }
          setState(() {
            busy = true;
            nameError = null;
            error = null;
          });
          final failure = await ref
              .read(groupsProvider.notifier)
              .createGroup(name, currency: currency, report: false);
          if (!ctx.mounted) return;
          if (failure != null) {
            setState(() {
              busy = false;
              error = friendlyMessage(failure);
            });
            return;
          }
          Navigator.of(ctx).pop();
          if (context.mounted) {
            showMessage(
              context,
              '"$name" created. It is now your active group.',
            );
          }
        }

        return AlertDialog(
          title: const Text('Create a group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('group-name'),
                  onChanged: (value) => nameText = value,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Group name',
                    hintText: 'e.g. Flatmates',
                    prefixIcon: const Icon(Icons.group_add_rounded),
                    errorText: nameError,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const Key('group-currency'),
                  initialValue: currency,
                  decoration: const InputDecoration(
                    labelText: 'Group currency',
                    helperText:
                        "Every group expense uses it. It can't be "
                        'changed later.',
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.currency_exchange_rounded),
                  ),
                  items: [
                    for (final c in CurrencyInfo.all)
                      DropdownMenuItem(
                        value: c.code,
                        child: Text('${c.code} (${c.symbol})'),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => currency = value);
                        },
                ),
                if (error != null) DialogError(error!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            BusyButton(busy: busy, label: 'Create', onPressed: submit),
          ],
        );
      },
    ),
  );
}

/// Sends a join request with an invite code. The request waits for the
/// admin's approval.
Future<void> showJoinGroupDialog(BuildContext context, WidgetRef ref) {
  var codeText = '';
  var busy = false;
  String? error;

  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> submit() async {
          final code = codeText.trim();
          if (code.isEmpty) {
            setState(() => error = friendlyMessageForKey('invalid_code'));
            return;
          }
          setState(() {
            busy = true;
            error = null;
          });
          final (request, failure) = await ref
              .read(groupsProvider.notifier)
              .joinByCode(code, report: false);
          if (!ctx.mounted) return;
          if (failure != null || request == null) {
            setState(() {
              busy = false;
              error = failure == null ? null : friendlyMessage(failure);
            });
            return;
          }
          Navigator.of(ctx).pop();
          if (context.mounted) {
            showMessage(
              context,
              'Request sent to ${request.groupName}. You can open the group '
              'once an admin approves you.',
            );
          }
        }

        return AlertDialog(
          title: const Text('Join with a code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('join-code'),
                onChanged: (value) => codeText = value,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Invite code',
                  hintText: 'XXXX-XXXX-XXXX-XXXX',
                  helperText: 'The group admin approves new members.',
                  prefixIcon: Icon(Icons.vpn_key_rounded),
                ),
              ),
              if (error != null) DialogError(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            BusyButton(busy: busy, label: 'Send request', onPressed: submit),
          ],
        );
      },
    ),
  );
}

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
          title: const Text('Invite by email'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'We email an invitation link that only works for this '
                  'address.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('invite-email'),
                  onChanged: (value) => emailText = value,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Email address',
                    hintText: 'name@example.com',
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                    errorText: fieldError,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<GroupRole>(
                  isExpanded: true,
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: GroupRole.member,
                      child: Text(
                        'Member (adds and shares expenses)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: GroupRole.viewer,
                      child: Text(
                        'Viewer (read only)',
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
              child: const Text('Cancel'),
            ),
            BusyButton(busy: busy, label: 'Send invitation', onPressed: submit),
          ],
        );
      },
    ),
  );
}

/// Says honestly what happened: "Email sent" only when the server sent
/// it; otherwise the link to share by hand.
Future<void> showInvitationResult(
  BuildContext context,
  WidgetRef ref,
  String email,
  SentInvitation sent,
) async {
  final link = sent.shareUrl;
  if (sent.sent || link == null) {
    showMessage(context, 'Email sent to $email.');
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Couldn't send the email"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share this link instead. It only works for $email and expires '
            'in 7 days.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          SelectableText(
            link,
            key: const Key('invite-share-link'),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            AppHaptics.selection();
            await Clipboard.setData(ClipboardData(text: link));
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (context.mounted) showMessage(context, 'Invite link copied.');
          },
          child: const Text('Copy link'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            AppHaptics.selection();
            final shared = await ref
                .read(shareServiceProvider)
                .shareText(
                  "You're invited to a group on Exevra: $link",
                  subject: 'Exevra group invitation',
                );
            if (!shared) {
              await Clipboard.setData(ClipboardData(text: link));
              if (context.mounted) {
                showMessage(
                  context,
                  "Couldn't open the share sheet, so the link was copied.",
                );
              }
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          icon: const Icon(Icons.share_rounded, size: 16),
          label: const Text('Share'),
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
  final text =
      'Join my group "${group.name}" on Exevra with the invite code '
      '$displayCode. The admin approves new members.';
  final shared = await ref
      .read(shareServiceProvider)
      .shareText(text, subject: 'Join ${group.name} on Exevra');
  if (shared) return;
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showMessage(context, 'Invite code copied.');
}

/// Copies [text] and confirms it.
void copyToClipboard(BuildContext context, String text, String confirmation) {
  AppHaptics.selection();
  unawaited(Clipboard.setData(ClipboardData(text: text)));
  showMessage(context, confirmation);
}
