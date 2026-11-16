import '../../l10n/l10n.dart';

/// The display name of the stored category [name] (the keys in
/// `AppConstants.categories`), or [name] itself for an unknown one.
String categoryLabel(AppLocalizations l10n, String name) {
  return switch (name.toLowerCase()) {
    'food' => l10n.expensesCategoryFood,
    'transport' => l10n.expensesCategoryTransport,
    'housing' => l10n.expensesCategoryHousing,
    'entertainment' => l10n.expensesCategoryEntertainment,
    'healthcare' => l10n.expensesCategoryHealthcare,
    'utilities' => l10n.expensesCategoryUtilities,
    'shopping' => l10n.expensesCategoryShopping,
    'personal' => l10n.expensesCategoryPersonal,
    'education' => l10n.expensesCategoryEducation,
    'other' => l10n.expensesCategoryOther,
    _ => name,
  };
}
