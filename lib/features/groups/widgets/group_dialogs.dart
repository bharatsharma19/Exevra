import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/currency_info.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../expenses/widgets/inline_notice.dart';

export 'invite_dialogs.dart';

/// Asks to confirm [title]. Completes with true only when confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) => showConfirmDialog(
  context,
  title: title,
  message: message,
  confirmLabel: confirmLabel,
  destructive: destructive,
);

/// Shows [message] in a snack bar of [kind] on the nearest messenger (the
/// app's root messenger in the app).
void showMessage(
  BuildContext context,
  String message, {
  AppSnackbarKind kind = AppSnackbarKind.info,
}) {
  AppSnackbar.show(
    message,
    kind: kind,
    messenger: ScaffoldMessenger.maybeOf(context),
  );
}

/// Inline error text for dialogs (errors are never shown under a modal).
class DialogError extends StatelessWidget {
  const DialogError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: InlineNotice(message: message, kind: NoticeKind.error),
  );
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
        final l10n = ctx.l10n;
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
          final result = await ref
              .read(groupsProvider.notifier)
              .createGroup(name, currency: currency, report: false);
          if (!ctx.mounted) return;
          if (result.status == GroupCreateStatus.failed) {
            setState(() {
              busy = false;
              error = friendlyMessage(
                result.failure ?? const AppFailure.unknown(),
              );
            });
            return;
          }
          // Created, or maybe created: never offer the same form again.
          Navigator.of(ctx).pop();
          if (!context.mounted) return;
          showMessage(
            context,
            switch (result.status) {
              GroupCreateStatus.opened => l10n.groupsCreated(name),
              GroupCreateStatus.createdNotOpened => l10n.groupsCreatedNotOpened(
                name,
              ),
              GroupCreateStatus.unconfirmed || GroupCreateStatus.failed =>
                friendlyMessageForKey('group_unconfirmed'),
            },
            kind: result.status == GroupCreateStatus.opened
                ? AppSnackbarKind.success
                : AppSnackbarKind.info,
          );
        }

        return AlertDialog(
          scrollable: true,
          title: Text(l10n.groupsCreateTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('group-name'),
                onChanged: (value) => nameText = value,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.groupsNameLabel,
                  hintText: l10n.groupsNameHint,
                  prefixIcon: const Icon(Icons.group_add_rounded),
                  errorText: nameError,
                  errorMaxLines: 3,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: const Key('group-currency'),
                initialValue: currency,
                decoration: InputDecoration(
                  labelText: l10n.groupsCurrencyLabel,
                  helperText: l10n.groupsCurrencyHelper,
                  helperMaxLines: 4,
                  prefixIcon: const Icon(Icons.currency_exchange_rounded),
                ),
                items: [
                  for (final c in CurrencyInfo.all)
                    DropdownMenuItem(
                      value: c.code,
                      child: Text(
                        '${c.code} (${c.symbol})',
                        overflow: TextOverflow.ellipsis,
                      ),
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
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            LoadingButton(
              key: const Key('group-create'),
              expand: false,
              isLoading: busy,
              label: l10n.groupsCreateAction,
              onPressed: submit,
            ),
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
        final l10n = ctx.l10n;
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
              l10n.groupsJoinRequested(request.groupName),
              kind: AppSnackbarKind.success,
            );
          }
        }

        return AlertDialog(
          scrollable: true,
          title: Text(l10n.groupsJoinTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('join-code'),
                onChanged: (value) => codeText = value,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: l10n.groupsInviteCodeLabel,
                  hintText: 'XXXX-XXXX-XXXX-XXXX',
                  helperText: l10n.groupsJoinHelper,
                  helperMaxLines: 3,
                  prefixIcon: const Icon(Icons.vpn_key_rounded),
                ),
              ),
              if (error != null) DialogError(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            LoadingButton(
              key: const Key('join-send'),
              expand: false,
              isLoading: busy,
              label: l10n.groupsJoinAction,
              onPressed: submit,
            ),
          ],
        );
      },
    ),
  );
}
