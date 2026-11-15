import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// Access to [AppLocalizations] from a [BuildContext].
extension AppLocalizationsContext on BuildContext {
  /// Strings for the current locale.
  ///
  /// Falls back to English when [AppLocalizations.delegate] is not registered
  /// above this context (for example in isolated widget tests), so widgets in
  /// the kit never crash on a missing delegate.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(const Locale('en'));
}
