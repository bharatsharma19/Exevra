import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'confirm_dialog.dart';

/// Asks "Discard changes?" before leaving a form with unsaved edits.
///
/// Wrap the form's page or sheet content. While [hasChanges] is true, system
/// back, the app bar back button and sheet dismissal by back gesture are
/// intercepted; if the user chooses to discard, the route is popped.
///
/// ```dart
/// UnsavedChangesGuard(hasChanges: _dirty, child: Form(...))
/// ```
///
/// A tap on a modal sheet's barrier goes through the guard, but a drag on
/// the sheet closes it without asking; open guarded sheets with
/// `showAppSheet(guarded: true)`, which turns dragging off.
class UnsavedChangesGuard extends StatelessWidget {
  /// Creates a guard.
  const UnsavedChangesGuard({
    required this.hasChanges,
    required this.child,
    this.title,
    this.message,
    this.discardLabel,
    this.keepEditingLabel,
    super.key,
  });

  /// Whether leaving now would lose edits.
  final bool hasChanges;

  /// The form.
  final Widget child;

  /// Dialog title. Defaults to "Discard changes?".
  final String? title;

  /// Dialog message.
  final String? message;

  /// Confirm label. Defaults to "Discard".
  final String? discardLabel;

  /// Cancel label. Defaults to "Keep editing".
  final String? keepEditingLabel;

  Future<void> _confirmPop(BuildContext context, Object? result) async {
    final l10n = context.l10n;
    final discard = await showConfirmDialog(
      context,
      title: title ?? l10n.discardChangesTitle,
      message: message ?? l10n.discardChangesMessage,
      confirmLabel: discardLabel ?? l10n.discardChangesConfirm,
      cancelLabel: keepEditingLabel ?? l10n.keepEditing,
      destructive: true,
    );
    if (discard && context.mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !hasChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmPop(context, result).ignore();
      },
      child: child,
    );
  }
}
