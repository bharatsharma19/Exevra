import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';

/// Goes back when there is somewhere to go back to, else to [fallback].
/// Screens reached by `go` (deep links, redirects) have nothing to pop.
void popOrGo(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// Switches to a bottom-navigation tab, keeping each tab's own stack.
void goTab(BuildContext context, String tabPath) {
  final index = AppRoutes.tabs.indexOf(tabPath);
  final shell = StatefulNavigationShell.maybeOf(context);
  if (shell != null && index >= 0) {
    shell.goBranch(index);
  } else {
    context.go(tabPath);
  }
}
