import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Product name. Not translated.
  ///
  /// In en, this message translates to:
  /// **'Exevra'**
  String get appName;

  /// Subtitle shown under the product name.
  ///
  /// In en, this message translates to:
  /// **'Expense & Split Tracker'**
  String get appTagline;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Button that repeats a failed action.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Tooltip of the button that reveals a hidden password.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// Tooltip of the button that hides a revealed password.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// Snackbar action that reverts the last change.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Accessibility label and text for a loading indicator.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// No description provided for @genericErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get genericErrorMessage;

  /// No description provided for @discardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. If you leave now, they will be lost.'**
  String get discardChangesMessage;

  /// No description provided for @discardChangesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardChangesConfirm;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @offlineTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get offlineTitle;

  /// No description provided for @offlineMessage.
  ///
  /// In en, this message translates to:
  /// **'Some actions need an internet connection.'**
  String get offlineMessage;

  /// Screen reader prefix for a success message.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get snackbarSuccessLabel;

  /// Screen reader prefix for an error message.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get snackbarErrorLabel;

  /// Screen reader prefix for an informational message.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get snackbarInfoLabel;

  /// Settlement waiting for the payee to confirm.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get statusConfirmed;

  /// No description provided for @statusVoided.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get statusVoided;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get roleMember;

  /// No description provided for @roleViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get roleViewer;

  /// Screen reader label for money coming in or owed to the user.
  ///
  /// In en, this message translates to:
  /// **'Plus {amount}'**
  String amountPositive(String amount);

  /// Screen reader label for money going out or owed by the user.
  ///
  /// In en, this message translates to:
  /// **'Minus {amount}'**
  String amountNegative(String amount);

  /// Error shown when a web page cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link. Please try again later.'**
  String get linkOpenFailed;

  /// Screen reader hint for a row that opens a web page.
  ///
  /// In en, this message translates to:
  /// **'Opens in your browser'**
  String get opensInBrowser;

  /// Title of the About screen.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// App version and build number.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String aboutVersion(String version, String build);

  /// Credit line on the About screen. Not translated.
  ///
  /// In en, this message translates to:
  /// **'Designed & developed by Bharat Sharma'**
  String get aboutCredit;

  /// Copyright line on the open-source licenses page.
  ///
  /// In en, this message translates to:
  /// **'© 2026 Bharat Sharma'**
  String get aboutLegalese;

  /// Section title on the About screen.
  ///
  /// In en, this message translates to:
  /// **'Help & legal'**
  String get aboutSupportSection;

  /// No description provided for @aboutPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get aboutPrivacyPolicy;

  /// No description provided for @aboutTermsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get aboutTermsOfUse;

  /// No description provided for @aboutHelpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get aboutHelpSupport;

  /// Row that opens the list of third-party licenses. US spelling, to match the title of the system licenses page it opens.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get aboutLicenses;

  /// Section title on the About screen.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get aboutAccountSection;

  /// Row that opens the web page about deleting an account.
  ///
  /// In en, this message translates to:
  /// **'Account deletion info'**
  String get aboutDeleteAccountInfo;

  /// No description provided for @aboutDeleteAccountInfoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How to delete your account and data, also without the app'**
  String get aboutDeleteAccountInfoSubtitle;

  /// Destructive button that starts account deletion.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get aboutDeleteAccount;

  /// Subject of the support email.
  ///
  /// In en, this message translates to:
  /// **'Exevra support'**
  String get supportEmailSubject;

  /// Body of the support email.
  ///
  /// In en, this message translates to:
  /// **'App version: {version}'**
  String supportEmailBody(String version);

  /// Error shown when no email app can be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open an email app. Write to us at {email}.'**
  String supportEmailOpenFailed(String email);

  /// Button that leaves the introduction.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingSkipTooltip.
  ///
  /// In en, this message translates to:
  /// **'Skip the introduction'**
  String get onboardingSkipTooltip;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Button on the last introduction page.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// Screen reader label of the introduction page indicator.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String onboardingPageIndicator(int current, int total);

  /// Screen reader label of the introduction page indicator, announced when the page changes. {title} is the title of the page.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}: {title}'**
  String onboardingPageAnnouncement(int current, int total, String title);

  /// No description provided for @onboardingTrackTitle.
  ///
  /// In en, this message translates to:
  /// **'Track every expense'**
  String get onboardingTrackTitle;

  /// No description provided for @onboardingTrackBody.
  ///
  /// In en, this message translates to:
  /// **'Log personal and shared spending in your own currency and see where your money goes.'**
  String get onboardingTrackBody;

  /// No description provided for @onboardingSplitTitle.
  ///
  /// In en, this message translates to:
  /// **'Split and settle up'**
  String get onboardingSplitTitle;

  /// No description provided for @onboardingSplitBody.
  ///
  /// In en, this message translates to:
  /// **'Share costs with a group and see who owes whom. When you settle up, the payment counts once the person who receives it confirms it.'**
  String get onboardingSplitBody;

  /// No description provided for @onboardingAssistantTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask about your spending'**
  String get onboardingAssistantTitle;

  /// No description provided for @onboardingAssistantBody.
  ///
  /// In en, this message translates to:
  /// **'Ask the assistant questions about your spending. It\'s optional and respects your privacy: it only sees your spending totals if you allow it, and you can turn it off in Settings.'**
  String get onboardingAssistantBody;

  /// No description provided for @firstExpenseNudgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your first expense'**
  String get firstExpenseNudgeTitle;

  /// No description provided for @firstExpenseNudgeMessage.
  ///
  /// In en, this message translates to:
  /// **'Record a purchase to start seeing where your money goes.'**
  String get firstExpenseNudgeMessage;

  /// No description provided for @firstExpenseNudgeAction.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get firstExpenseNudgeAction;

  /// Tooltip of the button that hides the first-expense tip for good.
  ///
  /// In en, this message translates to:
  /// **'Dismiss tip'**
  String get firstExpenseNudgeDismiss;

  /// Title of the expenses tab.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesTitle;

  /// Tooltip of the refresh button on the expenses tab.
  ///
  /// In en, this message translates to:
  /// **'Refresh expenses'**
  String get expensesRefresh;

  /// Button that opens the form for a new expense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get expensesAdd;

  /// No description provided for @expensesAddFirst.
  ///
  /// In en, this message translates to:
  /// **'Add your first expense'**
  String get expensesAddFirst;

  /// No description provided for @expensesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No expenses yet'**
  String get expensesEmptyTitle;

  /// No description provided for @expensesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add what you spend to see where your money goes.'**
  String get expensesEmptyMessage;

  /// No description provided for @expensesEmptyGroupMessage.
  ///
  /// In en, this message translates to:
  /// **'Nobody has added an expense to {group} yet. Add the first one to start splitting costs.'**
  String expensesEmptyGroupMessage(String group);

  /// No description provided for @expensesEmptyViewerMessage.
  ///
  /// In en, this message translates to:
  /// **'Nobody has added an expense to {group} yet. You can still add your own personal expenses.'**
  String expensesEmptyViewerMessage(String group);

  /// No description provided for @expensesEmptyFilteredTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching expenses'**
  String get expensesEmptyFilteredTitle;

  /// No description provided for @expensesEmptyFilteredMessage.
  ///
  /// In en, this message translates to:
  /// **'Try a different search, category or date range.'**
  String get expensesEmptyFilteredMessage;

  /// No description provided for @expensesClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get expensesClearFilters;

  /// No description provided for @expensesLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your expenses'**
  String get expensesLoadErrorTitle;

  /// Announced while a search or filter is active.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 expense found} other{{count} expenses found}}'**
  String expensesResultCount(int count);

  /// No description provided for @expensesSectionToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get expensesSectionToday;

  /// No description provided for @expensesSectionYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get expensesSectionYesterday;

  /// No description provided for @expensesSectionTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get expensesSectionTomorrow;

  /// No description provided for @expensesOnlyPayerCanEdit.
  ///
  /// In en, this message translates to:
  /// **'Only the person who paid can edit this expense.'**
  String get expensesOnlyPayerCanEdit;

  /// Shown on a personal expense in a list that also has group expenses.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get expensesPersonalTag;

  /// No description provided for @expensesPaidByYou.
  ///
  /// In en, this message translates to:
  /// **'You paid'**
  String get expensesPaidByYou;

  /// No description provided for @expensesPaidBy.
  ///
  /// In en, this message translates to:
  /// **'{name} paid'**
  String expensesPaidBy(String name);

  /// No description provided for @expensesPaidByFormer.
  ///
  /// In en, this message translates to:
  /// **'Paid by a former member'**
  String get expensesPaidByFormer;

  /// No description provided for @expensesPaidByMember.
  ///
  /// In en, this message translates to:
  /// **'Paid by a group member'**
  String get expensesPaidByMember;

  /// No description provided for @expensesActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Actions for {title}'**
  String expensesActionsTooltip(String title);

  /// No description provided for @expensesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get expensesEdit;

  /// No description provided for @expensesSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search expenses'**
  String get expensesSearchLabel;

  /// No description provided for @expensesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by title'**
  String get expensesSearchHint;

  /// No description provided for @expensesClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get expensesClearSearch;

  /// No description provided for @expensesTypeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get expensesTypeAll;

  /// No description provided for @expensesTypePersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get expensesTypePersonal;

  /// No description provided for @expensesTypeGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get expensesTypeGroup;

  /// No description provided for @expensesDateFilterTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filter by date'**
  String get expensesDateFilterTooltip;

  /// No description provided for @expensesDateFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Show expenses from'**
  String get expensesDateFilterTitle;

  /// No description provided for @expensesDateAny.
  ///
  /// In en, this message translates to:
  /// **'Any date'**
  String get expensesDateAny;

  /// No description provided for @expensesDateLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get expensesDateLast7Days;

  /// No description provided for @expensesDateThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get expensesDateThisMonth;

  /// No description provided for @expensesDateLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get expensesDateLastMonth;

  /// No description provided for @expensesDateLast3Months.
  ///
  /// In en, this message translates to:
  /// **'Last 3 months'**
  String get expensesDateLast3Months;

  /// No description provided for @expensesDateThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get expensesDateThisYear;

  /// No description provided for @expensesAllCategories.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get expensesAllCategories;

  /// No description provided for @expensesCategoryFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get expensesCategoryFood;

  /// No description provided for @expensesCategoryTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get expensesCategoryTransport;

  /// No description provided for @expensesCategoryHousing.
  ///
  /// In en, this message translates to:
  /// **'Housing'**
  String get expensesCategoryHousing;

  /// No description provided for @expensesCategoryEntertainment.
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get expensesCategoryEntertainment;

  /// No description provided for @expensesCategoryHealthcare.
  ///
  /// In en, this message translates to:
  /// **'Healthcare'**
  String get expensesCategoryHealthcare;

  /// No description provided for @expensesCategoryUtilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get expensesCategoryUtilities;

  /// No description provided for @expensesCategoryShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get expensesCategoryShopping;

  /// No description provided for @expensesCategoryPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get expensesCategoryPersonal;

  /// No description provided for @expensesCategoryEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get expensesCategoryEducation;

  /// No description provided for @expensesCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get expensesCategoryOther;

  /// No description provided for @expensesLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'This expense is locked'**
  String get expensesLockedTitle;

  /// No description provided for @expensesLockedRow.
  ///
  /// In en, this message translates to:
  /// **'Locked: someone in it left the group'**
  String get expensesLockedRow;

  /// No description provided for @expensesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete expense?'**
  String get expensesDeleteTitle;

  /// No description provided for @expensesDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" ({amount}) will be deleted.'**
  String expensesDeleteMessage(String title, String amount);

  /// No description provided for @expensesDeleteGroupMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" ({amount}) will be deleted for everyone in the group, and the balances will change.'**
  String expensesDeleteGroupMessage(String title, String amount);

  /// No description provided for @expensesDeleteNoUndo.
  ///
  /// In en, this message translates to:
  /// **'You didn\'t pay for it, so this can\'t be undone.'**
  String get expensesDeleteNoUndo;

  /// No description provided for @expensesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\"'**
  String expensesDeleted(String title);

  /// No description provided for @expensesRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored \"{title}\"'**
  String expensesRestored(String title);

  /// Title of the form for a new expense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get expensesAddTitle;

  /// No description provided for @expensesEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit expense'**
  String get expensesEditTitle;

  /// No description provided for @expensesDiscardEditMessage.
  ///
  /// In en, this message translates to:
  /// **'Your changes to this expense will be lost.'**
  String get expensesDiscardEditMessage;

  /// No description provided for @expensesDiscardNewMessage.
  ///
  /// In en, this message translates to:
  /// **'This expense won\'t be saved.'**
  String get expensesDiscardNewMessage;

  /// No description provided for @expensesAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get expensesAmountLabel;

  /// No description provided for @expensesCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get expensesCurrencyLabel;

  /// No description provided for @expensesGroupCurrencyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Group expenses use the group currency, {currency}'**
  String expensesGroupCurrencyTooltip(String currency);

  /// No description provided for @expensesLockedStillEditable.
  ///
  /// In en, this message translates to:
  /// **'You can still change the title, category, date and note.'**
  String get expensesLockedStillEditable;

  /// No description provided for @expensesCurrencyChanged.
  ///
  /// In en, this message translates to:
  /// **'The amount is now in {currency}. Check it before saving.'**
  String expensesCurrencyChanged(String currency);

  /// No description provided for @expensesTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get expensesTitleLabel;

  /// No description provided for @expensesTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Weekly groceries'**
  String get expensesTitleHint;

  /// No description provided for @expensesTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a title.'**
  String get expensesTitleRequired;

  /// No description provided for @expensesScopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Personal or group expense'**
  String get expensesScopeLabel;

  /// No description provided for @expensesScopePersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get expensesScopePersonal;

  /// No description provided for @expensesScopeGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get expensesScopeGroup;

  /// No description provided for @expensesScopeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available for this expense'**
  String get expensesScopeUnavailable;

  /// No description provided for @expensesNoGroupHint.
  ///
  /// In en, this message translates to:
  /// **'To share costs, create or join a group in Profile.'**
  String get expensesNoGroupHint;

  /// No description provided for @expensesGroupScopeCaption.
  ///
  /// In en, this message translates to:
  /// **'Shared with everyone in {group}, in {currency}.'**
  String expensesGroupScopeCaption(String group, String currency);

  /// No description provided for @expensesCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get expensesCategoryLabel;

  /// No description provided for @expensesChangeDate.
  ///
  /// In en, this message translates to:
  /// **'Change date'**
  String get expensesChangeDate;

  /// No description provided for @expensesChangeTime.
  ///
  /// In en, this message translates to:
  /// **'Change time'**
  String get expensesChangeTime;

  /// No description provided for @expensesNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get expensesNoteLabel;

  /// No description provided for @expensesNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a description or location'**
  String get expensesNoteHint;

  /// No description provided for @expensesClearNote.
  ///
  /// In en, this message translates to:
  /// **'Clear note'**
  String get expensesClearNote;

  /// No description provided for @expensesSave.
  ///
  /// In en, this message translates to:
  /// **'Save expense'**
  String get expensesSave;

  /// No description provided for @expensesSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get expensesSaveChanges;

  /// No description provided for @expensesMovedToGroup.
  ///
  /// In en, this message translates to:
  /// **'Moved \"{title}\" to {group}'**
  String expensesMovedToGroup(String title, String group);

  /// No description provided for @expensesMovedToPersonal.
  ///
  /// In en, this message translates to:
  /// **'Moved \"{title}\" to your personal expenses'**
  String expensesMovedToPersonal(String title);

  /// No description provided for @expensesMovedNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Moved \"{title}\", but your other changes weren\'t saved. {reason}'**
  String expensesMovedNotSaved(String title, String reason);

  /// No description provided for @expensesMoveUndone.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" is back as it was'**
  String expensesMoveUndone(String title);

  /// Title of the groups area on the Profile tab.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groupsTitle;

  /// No description provided for @groupsMyGroups.
  ///
  /// In en, this message translates to:
  /// **'My groups ({count})'**
  String groupsMyGroups(int count);

  /// No description provided for @groupsCreateTooltip.
  ///
  /// In en, this message translates to:
  /// **'Create a group'**
  String get groupsCreateTooltip;

  /// No description provided for @groupsJoinTooltip.
  ///
  /// In en, this message translates to:
  /// **'Join with a code'**
  String get groupsJoinTooltip;

  /// Choice that shows only the user's own expenses.
  ///
  /// In en, this message translates to:
  /// **'Personal (no group)'**
  String get groupsPersonalScope;

  /// No description provided for @groupsPendingChip.
  ///
  /// In en, this message translates to:
  /// **'{name} (waiting for approval)'**
  String groupsPendingChip(String name);

  /// Screen reader label of a group the user asked to join.
  ///
  /// In en, this message translates to:
  /// **'{name}, waiting for approval. Opens once the admin approves you.'**
  String groupsPendingChipLabel(String name);

  /// No description provided for @groupsPendingNote.
  ///
  /// In en, this message translates to:
  /// **'Groups waiting for approval open once their admin approves you.'**
  String get groupsPendingNote;

  /// No description provided for @groupsNoGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Share costs with a group'**
  String get groupsNoGroupsTitle;

  /// No description provided for @groupsNoGroupsMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a group for flatmates, a trip or a team, or join one with an invite code.'**
  String get groupsNoGroupsMessage;

  /// No description provided for @groupsScopeSwitched.
  ///
  /// In en, this message translates to:
  /// **'Showing expenses from {name}'**
  String groupsScopeSwitched(String name);

  /// No description provided for @groupsScopePersonal.
  ///
  /// In en, this message translates to:
  /// **'Showing your personal expenses'**
  String get groupsScopePersonal;

  /// No description provided for @groupsCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a group'**
  String get groupsCreateTitle;

  /// No description provided for @groupsNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupsNameLabel;

  /// No description provided for @groupsNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Flatmates'**
  String get groupsNameHint;

  /// No description provided for @groupsCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Group currency'**
  String get groupsCurrencyLabel;

  /// No description provided for @groupsCurrencyHelper.
  ///
  /// In en, this message translates to:
  /// **'Every group expense uses it. It can\'t be changed later.'**
  String get groupsCurrencyHelper;

  /// No description provided for @groupsCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get groupsCreateAction;

  /// No description provided for @groupsCreated.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" created. It is now your active group.'**
  String groupsCreated(String name);

  /// No description provided for @groupsCreatedNotOpened.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" was created, but we couldn\'t open it yet. Refresh your groups to see it.'**
  String groupsCreatedNotOpened(String name);

  /// No description provided for @groupsJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join with a code'**
  String get groupsJoinTitle;

  /// No description provided for @groupsInviteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get groupsInviteCodeLabel;

  /// No description provided for @groupsJoinHelper.
  ///
  /// In en, this message translates to:
  /// **'The group admin approves new members.'**
  String get groupsJoinHelper;

  /// No description provided for @groupsJoinAction.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get groupsJoinAction;

  /// No description provided for @groupsJoinRequested.
  ///
  /// In en, this message translates to:
  /// **'Request sent to {group}. You can open the group once an admin approves you.'**
  String groupsJoinRequested(String group);

  /// No description provided for @groupsInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite by email'**
  String get groupsInviteTitle;

  /// No description provided for @groupsInviteIntro.
  ///
  /// In en, this message translates to:
  /// **'We email an invitation to {group}. The link only works for this address.'**
  String groupsInviteIntro(String group);

  /// No description provided for @groupsInviteEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get groupsInviteEmailLabel;

  /// No description provided for @groupsInviteRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get groupsInviteRoleLabel;

  /// No description provided for @groupsRoleMemberLong.
  ///
  /// In en, this message translates to:
  /// **'Member (adds and shares expenses)'**
  String get groupsRoleMemberLong;

  /// No description provided for @groupsRoleViewerLong.
  ///
  /// In en, this message translates to:
  /// **'Viewer (read only)'**
  String get groupsRoleViewerLong;

  /// No description provided for @groupsInviteSend.
  ///
  /// In en, this message translates to:
  /// **'Send invitation'**
  String get groupsInviteSend;

  /// No description provided for @groupsInviteEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Email sent to {email}.'**
  String groupsInviteEmailSent(String email);

  /// No description provided for @groupsInviteNotEmailed.
  ///
  /// In en, this message translates to:
  /// **'The invitation for {email} was created, but we couldn\'t email it. Ask them to join with the invite code instead.'**
  String groupsInviteNotEmailed(String email);

  /// No description provided for @groupsInviteShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the email'**
  String get groupsInviteShareTitle;

  /// No description provided for @groupsInviteShareMessage.
  ///
  /// In en, this message translates to:
  /// **'Share this link instead. It only works for {email} and expires in 7 days.'**
  String groupsInviteShareMessage(String email);

  /// No description provided for @groupsInviteLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite link copied.'**
  String get groupsInviteLinkCopied;

  /// No description provided for @groupsCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get groupsCopyLink;

  /// No description provided for @groupsInviteShareText.
  ///
  /// In en, this message translates to:
  /// **'You\'re invited to a group on Exevra: {link}'**
  String groupsInviteShareText(String link);

  /// No description provided for @groupsInviteShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Exevra group invitation'**
  String get groupsInviteShareSubject;

  /// No description provided for @groupsShareFallbackCopied.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the share sheet, so the link was copied.'**
  String get groupsShareFallbackCopied;

  /// No description provided for @groupsShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get groupsShare;

  /// No description provided for @groupsInviteCodeShareText.
  ///
  /// In en, this message translates to:
  /// **'Join my group \"{group}\" on Exevra with the invite code {code}. The admin approves new members.'**
  String groupsInviteCodeShareText(String group, String code);

  /// No description provided for @groupsInviteCodeShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Join {group} on Exevra'**
  String groupsInviteCodeShareSubject(String group);

  /// No description provided for @groupsInviteCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite code copied.'**
  String get groupsInviteCodeCopied;

  /// No description provided for @groupsSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Currency {currency} · 1 member} other{Currency {currency} · {count} members}}'**
  String groupsSummary(String currency, int count);

  /// No description provided for @groupsViewerNote.
  ///
  /// In en, this message translates to:
  /// **'You can see this group but not add expenses. Ask the admin to make you a member.'**
  String get groupsViewerNote;

  /// No description provided for @groupsInviteByEmail.
  ///
  /// In en, this message translates to:
  /// **'Invite by email'**
  String get groupsInviteByEmail;

  /// No description provided for @groupsNewCode.
  ///
  /// In en, this message translates to:
  /// **'New code'**
  String get groupsNewCode;

  /// No description provided for @groupsNewCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Issue a new invite code?'**
  String get groupsNewCodeTitle;

  /// No description provided for @groupsNewCodeMessage.
  ///
  /// In en, this message translates to:
  /// **'The current code stops working. People who have it can no longer ask to join.'**
  String get groupsNewCodeMessage;

  /// No description provided for @groupsNewCodeReady.
  ///
  /// In en, this message translates to:
  /// **'New invite code: {code}'**
  String groupsNewCodeReady(String code);

  /// No description provided for @groupsNoInviteCode.
  ///
  /// In en, this message translates to:
  /// **'No invite code yet. Tap New code to create one.'**
  String get groupsNoInviteCode;

  /// No description provided for @groupsCopyCodeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy invite code'**
  String get groupsCopyCodeTooltip;

  /// No description provided for @groupsInviteCodeApproval.
  ///
  /// In en, this message translates to:
  /// **'People who join with the code wait for your approval.'**
  String get groupsInviteCodeApproval;

  /// No description provided for @groupsInviteCodeExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}. People who join with it wait for your approval.'**
  String groupsInviteCodeExpires(String date);

  /// No description provided for @groupsPendingInvitations.
  ///
  /// In en, this message translates to:
  /// **'Pending invitations ({count})'**
  String groupsPendingInvitations(int count);

  /// No description provided for @groupsWaitingForApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval ({count})'**
  String groupsWaitingForApproval(int count);

  /// No description provided for @groupsMembers.
  ///
  /// In en, this message translates to:
  /// **'Members ({count})'**
  String groupsMembers(int count);

  /// No description provided for @groupsLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave group'**
  String get groupsLeave;

  /// No description provided for @groupsLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave {group}?'**
  String groupsLeaveTitle(String group);

  /// No description provided for @groupsLeaveLastMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'re the only member, so leaving deletes {group} and all its expenses and payments.'**
  String groupsLeaveLastMessage(String group);

  /// No description provided for @groupsLeaveAdminMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'re the admin. {name}, the longest-standing member, becomes the admin when you leave. You can choose someone else first with \"Make admin\". You need to be settled up to leave.'**
  String groupsLeaveAdminMessage(String name);

  /// No description provided for @groupsLeaveMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ll no longer see {group}\'s expenses and balances. Your past expenses stay in the group. You need to be settled up to leave.'**
  String groupsLeaveMessage(String group);

  /// No description provided for @groupsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get groupsDelete;

  /// No description provided for @groupsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {group}?'**
  String groupsDeleteTitle(String group);

  /// No description provided for @groupsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the group with all its expenses and payments. It can\'t be undone.'**
  String get groupsDeleteMessage;

  /// No description provided for @groupsDeleteHasMembers.
  ///
  /// In en, this message translates to:
  /// **'Remove the other members or make someone else admin before deleting this group.'**
  String get groupsDeleteHasMembers;

  /// No description provided for @groupsInvitationStatus.
  ///
  /// In en, this message translates to:
  /// **'{role} · expires {date}'**
  String groupsInvitationStatus(String role, String date);

  /// No description provided for @groupsRevokeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Revoke invitation'**
  String get groupsRevokeTooltip;

  /// No description provided for @groupsRevokeTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke this invitation?'**
  String get groupsRevokeTitle;

  /// No description provided for @groupsRevokeMessage.
  ///
  /// In en, this message translates to:
  /// **'The link sent to {email} stops working.'**
  String groupsRevokeMessage(String email);

  /// No description provided for @groupsRevokeAction.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get groupsRevokeAction;

  /// No description provided for @groupsRevoked.
  ///
  /// In en, this message translates to:
  /// **'Invitation for {email} revoked.'**
  String groupsRevoked(String email);

  /// No description provided for @groupsRequestPending.
  ///
  /// In en, this message translates to:
  /// **'Wants to join'**
  String get groupsRequestPending;

  /// No description provided for @groupsApproveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Approve {name}'**
  String groupsApproveTooltip(String name);

  /// No description provided for @groupsApproveAsMember.
  ///
  /// In en, this message translates to:
  /// **'Approve as member'**
  String get groupsApproveAsMember;

  /// No description provided for @groupsApproveAsViewer.
  ///
  /// In en, this message translates to:
  /// **'Approve as viewer (read only)'**
  String get groupsApproveAsViewer;

  /// No description provided for @groupsApprovedMember.
  ///
  /// In en, this message translates to:
  /// **'{name} can now add expenses.'**
  String groupsApprovedMember(String name);

  /// No description provided for @groupsApprovedViewer.
  ///
  /// In en, this message translates to:
  /// **'{name} can now see the group.'**
  String groupsApprovedViewer(String name);

  /// No description provided for @groupsDenyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Deny {name}'**
  String groupsDenyTooltip(String name);

  /// No description provided for @groupsDenyTitle.
  ///
  /// In en, this message translates to:
  /// **'Deny {name}?'**
  String groupsDenyTitle(String name);

  /// No description provided for @groupsDenyMessage.
  ///
  /// In en, this message translates to:
  /// **'They won\'t join the group and can\'t ask again with this code. You can still invite them by email later.'**
  String get groupsDenyMessage;

  /// No description provided for @groupsDenyAction.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get groupsDenyAction;

  /// No description provided for @groupsMemberYou.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String groupsMemberYou(String name);

  /// No description provided for @groupsManageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Manage {name}'**
  String groupsManageTooltip(String name);

  /// No description provided for @groupsMakeMember.
  ///
  /// In en, this message translates to:
  /// **'Make member (can add expenses)'**
  String get groupsMakeMember;

  /// No description provided for @groupsMakeViewer.
  ///
  /// In en, this message translates to:
  /// **'Make viewer (read only)'**
  String get groupsMakeViewer;

  /// No description provided for @groupsMakeViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Make {name} a viewer?'**
  String groupsMakeViewerTitle(String name);

  /// No description provided for @groupsMakeViewerMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} will only be able to see the group, not add expenses. You can make them a member again later.'**
  String groupsMakeViewerMessage(String name);

  /// No description provided for @groupsMakeViewerAction.
  ///
  /// In en, this message translates to:
  /// **'Make viewer'**
  String get groupsMakeViewerAction;

  /// No description provided for @groupsNowViewer.
  ///
  /// In en, this message translates to:
  /// **'{name} can now only view the group.'**
  String groupsNowViewer(String name);

  /// No description provided for @groupsMakeAdmin.
  ///
  /// In en, this message translates to:
  /// **'Make admin'**
  String get groupsMakeAdmin;

  /// No description provided for @groupsMakeAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Make {name} the admin?'**
  String groupsMakeAdminTitle(String name);

  /// No description provided for @groupsMakeAdminMessage.
  ///
  /// In en, this message translates to:
  /// **'A group has one admin. You become a member, and your pending email invitations are cancelled.'**
  String get groupsMakeAdminMessage;

  /// No description provided for @groupsNowAdmin.
  ///
  /// In en, this message translates to:
  /// **'{name} is now the admin.'**
  String groupsNowAdmin(String name);

  /// No description provided for @groupsRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get groupsRemoveMember;

  /// No description provided for @groupsRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String groupsRemoveTitle(String name);

  /// No description provided for @groupsRemoveMessage.
  ///
  /// In en, this message translates to:
  /// **'They lose access to {group} and can\'t rejoin with the invite code. Their past expenses stay in the group.'**
  String groupsRemoveMessage(String group);

  /// No description provided for @groupsRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get groupsRemoveAction;

  /// No description provided for @groupsRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} was removed from the group.'**
  String groupsRemoved(String name);

  /// No description provided for @groupsNotSettledTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} is not settled up'**
  String groupsNotSettledTitle(String name);

  /// No description provided for @groupsNotSettledMessage.
  ///
  /// In en, this message translates to:
  /// **'They still have an open balance or a payment waiting for confirmation. If you remove them anyway, their balance stays in the group\'s balances but can\'t be settled in the app.'**
  String get groupsNotSettledMessage;

  /// No description provided for @groupsRemoveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Remove anyway'**
  String get groupsRemoveAnyway;

  /// No description provided for @settleTitle.
  ///
  /// In en, this message translates to:
  /// **'Balances & payments'**
  String get settleTitle;

  /// No description provided for @settleRecordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get settleRecordPayment;

  /// No description provided for @settleBalancesHeader.
  ///
  /// In en, this message translates to:
  /// **'Balances ({currency})'**
  String settleBalancesHeader(String currency);

  /// No description provided for @settleSuggestionsHeader.
  ///
  /// In en, this message translates to:
  /// **'Suggested payments'**
  String get settleSuggestionsHeader;

  /// No description provided for @settlePaymentsHeader.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get settlePaymentsHeader;

  /// No description provided for @settleEveryoneSettled.
  ///
  /// In en, this message translates to:
  /// **'Everyone is settled up.'**
  String get settleEveryoneSettled;

  /// No description provided for @settleNoPayments.
  ///
  /// In en, this message translates to:
  /// **'No payments recorded yet.'**
  String get settleNoPayments;

  /// No description provided for @settleShowOlder.
  ///
  /// In en, this message translates to:
  /// **'Show older payments'**
  String get settleShowOlder;

  /// Stands for the signed-in user in balances and payments.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get settleYou;

  /// No description provided for @settleFormerMember.
  ///
  /// In en, this message translates to:
  /// **'Former member'**
  String get settleFormerMember;

  /// No description provided for @settleYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You owe {amount}'**
  String settleYouOwe(String amount);

  /// No description provided for @settleYouAreOwed.
  ///
  /// In en, this message translates to:
  /// **'You\'re owed {amount}'**
  String settleYouAreOwed(String amount);

  /// No description provided for @settleYouAreSettled.
  ///
  /// In en, this message translates to:
  /// **'You\'re settled up'**
  String get settleYouAreSettled;

  /// No description provided for @settleMemberOwes.
  ///
  /// In en, this message translates to:
  /// **'{name} owes {amount}'**
  String settleMemberOwes(String name, String amount);

  /// No description provided for @settleMemberIsOwed.
  ///
  /// In en, this message translates to:
  /// **'{name} is owed {amount}'**
  String settleMemberIsOwed(String name, String amount);

  /// No description provided for @settleMemberSettled.
  ///
  /// In en, this message translates to:
  /// **'{name} is settled up'**
  String settleMemberSettled(String name);

  /// No description provided for @settleSuggestYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You owe {name} {amount}'**
  String settleSuggestYouOwe(String name, String amount);

  /// No description provided for @settleSuggestOwesYou.
  ///
  /// In en, this message translates to:
  /// **'{name} owes you {amount}'**
  String settleSuggestOwesYou(String name, String amount);

  /// No description provided for @settleSuggestOther.
  ///
  /// In en, this message translates to:
  /// **'{from} owes {to} {amount}'**
  String settleSuggestOther(String from, String to, String amount);

  /// No description provided for @settlePay.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get settlePay;

  /// No description provided for @settlePayTooltip.
  ///
  /// In en, this message translates to:
  /// **'Record paying {name} {amount}'**
  String settlePayTooltip(String name, String amount);

  /// No description provided for @settlePaidRow.
  ///
  /// In en, this message translates to:
  /// **'{from} paid {to}'**
  String settlePaidRow(String from, String to);

  /// No description provided for @settlePendingFor.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name} to confirm'**
  String settlePendingFor(String name);

  /// No description provided for @settlePendingForYou.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you to confirm'**
  String get settlePendingForYou;

  /// No description provided for @settleVoidReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String settleVoidReason(String reason);

  /// No description provided for @settleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get settleConfirm;

  /// No description provided for @settleVoid.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get settleVoid;

  /// No description provided for @settleConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm this payment?'**
  String get settleConfirmTitle;

  /// No description provided for @settleConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Confirm only if you received {amount} from {name}. It then counts in the balances.'**
  String settleConfirmMessage(String amount, String name);

  /// No description provided for @settleConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'I received it'**
  String get settleConfirmAction;

  /// No description provided for @settleConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed.'**
  String get settleConfirmed;

  /// No description provided for @settleNoOneToPay.
  ///
  /// In en, this message translates to:
  /// **'There is no one else in this group to pay.'**
  String get settleNoOneToPay;

  /// No description provided for @settleRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Record a payment'**
  String get settleRecordTitle;

  /// No description provided for @settleRecordIntro.
  ///
  /// In en, this message translates to:
  /// **'Record money you paid to a group member. It counts once they confirm they received it.'**
  String get settleRecordIntro;

  /// No description provided for @settlePaidTo.
  ///
  /// In en, this message translates to:
  /// **'Paid to'**
  String get settlePaidTo;

  /// No description provided for @settleAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String settleAmountLabel(String currency);

  /// No description provided for @settleLimitHelper.
  ///
  /// In en, this message translates to:
  /// **'You owe {name} up to {amount}.'**
  String settleLimitHelper(String name, String amount);

  /// No description provided for @settleOverLimit.
  ///
  /// In en, this message translates to:
  /// **'That\'s more than you owe {name} (up to {amount}).'**
  String settleOverLimit(String name, String amount);

  /// No description provided for @settleNothingOwed.
  ///
  /// In en, this message translates to:
  /// **'You don\'t owe {name} anything right now.'**
  String settleNothingOwed(String name);

  /// No description provided for @settleNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get settleNoteLabel;

  /// No description provided for @settleNoteHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. UPI, cash, bank transfer'**
  String get settleNoteHint;

  /// No description provided for @settleRecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded. It counts once {name} confirms it.'**
  String settleRecorded(String name);

  /// No description provided for @settleVoidTitle.
  ///
  /// In en, this message translates to:
  /// **'Void this payment?'**
  String get settleVoidTitle;

  /// No description provided for @settleVoidMessage.
  ///
  /// In en, this message translates to:
  /// **'{from} paid {to} {amount}. A voided payment no longer counts in the balances.'**
  String settleVoidMessage(String from, String to, String amount);

  /// No description provided for @settleVoidReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get settleVoidReasonLabel;

  /// No description provided for @settleVoidReasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Entered twice'**
  String get settleVoidReasonHint;

  /// No description provided for @settleKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get settleKeep;

  /// No description provided for @settleVoidAction.
  ///
  /// In en, this message translates to:
  /// **'Void payment'**
  String get settleVoidAction;

  /// No description provided for @settleVoided.
  ///
  /// In en, this message translates to:
  /// **'Payment voided.'**
  String get settleVoided;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
