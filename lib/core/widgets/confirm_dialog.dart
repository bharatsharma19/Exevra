import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_palette.dart';

/// Asks the user to confirm an action and resolves to `true` only when they
/// tap the confirm button. Dismissing the dialog (back, barrier tap, Cancel)
/// resolves to `false`.
///
/// Set [destructive] for irreversible actions (delete, remove member, leave
/// group): the confirm button then uses the danger colours.
///
/// ```dart
/// if (await showConfirmDialog(
///   context,
///   title: 'Delete expense?',
///   message: 'This removes it for everyone in the group.',
///   confirmLabel: 'Delete',
///   destructive: true,
/// )) { ... }
/// ```
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  String? cancelLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );
  return confirmed ?? false;
}

/// The dialog shown by [showConfirmDialog]. Pops `true` on confirm and
/// `false` on cancel.
class ConfirmDialog extends StatelessWidget {
  /// Creates a confirmation dialog.
  const ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel,
    this.destructive = false,
    super.key,
  });

  /// Question, ideally naming the action ("Delete expense?").
  final String title;

  /// Consequence of confirming.
  final String message;

  /// Confirm button label; use the verb ("Delete"), not "OK".
  final String confirmLabel;

  /// Cancel button label. Defaults to "Cancel".
  final String? cancelLabel;

  /// Styles the confirm button as destructive.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // scrollable: the title and message scroll together, so the dialog fits
    // on a 320 dp screen at 200% text with the actions still reachable.
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel ?? context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: palette.danger,
                  foregroundColor: palette.onDanger,
                  // Keeps the label at 4.5:1 while hovered, focused or
                  // pressed (see LoadingButton).
                  overlayColor: palette.onDangerContainer,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
