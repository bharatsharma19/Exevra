import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Opens a modal bottom sheet with the app's defaults: scroll-controlled
/// height, a drag handle, safe-area insets, and content padded above the
/// soft keyboard.
///
/// For a form, set [guarded] and wrap the form in an `UnsavedChangesGuard`.
/// A guarded sheet cannot be dragged closed (a drag would bypass the guard);
/// back and a tap on the barrier still go through the guard, which asks
/// "Discard changes?" while there are edits.
///
/// ```dart
/// showAppSheet<void>(
///   context: context,
///   guarded: true,
///   builder: (context) => const AddExpenseForm(),
/// );
/// ```
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool guarded = false,
  bool showDragHandle = true,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    showDragHandle: showDragHandle,
    enableDrag: !guarded,
    builder: (context) => AppSheetBody(child: builder(context)),
  );
}

/// Sheet content layout used by [showAppSheet]: pads by the keyboard inset
/// and the bottom safe area and scrolls when the content is taller than the
/// space left.
class AppSheetBody extends StatelessWidget {
  /// Creates the sheet body.
  const AppSheetBody({required this.child, super.key});

  /// The sheet content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.lg,
          ),
          child: child,
        ),
      ),
    );
  }
}
