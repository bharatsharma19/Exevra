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

  /// Bottom navigation tab with the spending summary.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get shellNavHome;

  /// No description provided for @shellNavExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get shellNavExpenses;

  /// No description provided for @shellNavInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get shellNavInsights;

  /// Bottom navigation tab of the AI assistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get shellNavAssistant;

  /// No description provided for @shellNavProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get shellNavProfile;

  /// Second line of the offline banner shown above every tab.
  ///
  /// In en, this message translates to:
  /// **'Changes can\'t be saved until you reconnect.'**
  String get shellOfflineMessage;

  /// No description provided for @dashboardGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get dashboardGreetingMorning;

  /// No description provided for @dashboardGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get dashboardGreetingAfternoon;

  /// No description provided for @dashboardGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get dashboardGreetingEvening;

  /// Name of the personal (no group) view.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get dashboardScopePersonal;

  /// Screen reader label of the button that switches between personal and group views.
  ///
  /// In en, this message translates to:
  /// **'Showing {scope}. Change view'**
  String dashboardScopeButtonLabel(String scope);

  /// No description provided for @dashboardScopeButtonTooltip.
  ///
  /// In en, this message translates to:
  /// **'Change view'**
  String get dashboardScopeButtonTooltip;

  /// No description provided for @dashboardSwitcherTitle.
  ///
  /// In en, this message translates to:
  /// **'Show spending for'**
  String get dashboardSwitcherTitle;

  /// No description provided for @dashboardSwitcherPersonalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your expenses and your share of group expenses'**
  String get dashboardSwitcherPersonalSubtitle;

  /// No description provided for @dashboardSwitcherGroupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything spent in this group'**
  String get dashboardSwitcherGroupSubtitle;

  /// Screen reader suffix for the view that is currently shown.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get dashboardSwitcherSelected;

  /// No description provided for @dashboardSwitcherManageGroups.
  ///
  /// In en, this message translates to:
  /// **'Manage groups'**
  String get dashboardSwitcherManageGroups;

  /// Title of the summary card in personal view.
  ///
  /// In en, this message translates to:
  /// **'Your spending'**
  String get dashboardYourSpending;

  /// Title of the summary card in group view: what everyone in the group spent.
  ///
  /// In en, this message translates to:
  /// **'Group total'**
  String get dashboardGroupTotal;

  /// No description provided for @dashboardPersonalScopeNote.
  ///
  /// In en, this message translates to:
  /// **'Your personal expenses plus your share of group expenses'**
  String get dashboardPersonalScopeNote;

  /// No description provided for @dashboardGroupScopeNote.
  ///
  /// In en, this message translates to:
  /// **'Everything spent in {group}, by everyone'**
  String dashboardGroupScopeNote(String group);

  /// Screen reader text for a total that could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get dashboardTotalUnavailable;

  /// Screen reader label of the summary total.
  ///
  /// In en, this message translates to:
  /// **'{title}, {period}: {amount}'**
  String dashboardSummaryLabel(String title, String period, String amount);

  /// No description provided for @dashboardDailyAverage.
  ///
  /// In en, this message translates to:
  /// **'Daily average'**
  String get dashboardDailyAverage;

  /// No description provided for @dashboardExpenseCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get dashboardExpenseCountLabel;

  /// No description provided for @dashboardOtherCurrencies.
  ///
  /// In en, this message translates to:
  /// **'Also spent in other currencies: {amounts}. Not included in this total.'**
  String dashboardOtherCurrencies(String amounts);

  /// No description provided for @dashboardBalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Your balance in this group'**
  String get dashboardBalanceTitle;

  /// No description provided for @dashboardBalanceYouOwe.
  ///
  /// In en, this message translates to:
  /// **'You owe {amount}'**
  String dashboardBalanceYouOwe(String amount);

  /// No description provided for @dashboardBalanceOwesYou.
  ///
  /// In en, this message translates to:
  /// **'The group owes you {amount}'**
  String dashboardBalanceOwesYou(String amount);

  /// No description provided for @dashboardBalanceSettled.
  ///
  /// In en, this message translates to:
  /// **'You\'re all settled up'**
  String get dashboardBalanceSettled;

  /// No description provided for @dashboardAskAssistant.
  ///
  /// In en, this message translates to:
  /// **'Ask the assistant'**
  String get dashboardAskAssistant;

  /// No description provided for @dashboardAskAssistantSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Questions about your spending, budgets or saving'**
  String get dashboardAskAssistantSubtitle;

  /// No description provided for @dashboardSettleUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Who owes whom'**
  String get dashboardSettleUpTitle;

  /// No description provided for @dashboardSettleUpAction.
  ///
  /// In en, this message translates to:
  /// **'Settle up'**
  String get dashboardSettleUpAction;

  /// No description provided for @dashboardYouOwePerson.
  ///
  /// In en, this message translates to:
  /// **'You owe {name}'**
  String dashboardYouOwePerson(String name);

  /// No description provided for @dashboardPersonOwesYou.
  ///
  /// In en, this message translates to:
  /// **'{name} owes you'**
  String dashboardPersonOwesYou(String name);

  /// No description provided for @dashboardPersonOwesPerson.
  ///
  /// In en, this message translates to:
  /// **'{from} owes {to}'**
  String dashboardPersonOwesPerson(String from, String to);

  /// Name used when a group member's name is not known.
  ///
  /// In en, this message translates to:
  /// **'A member'**
  String get dashboardMemberFallback;

  /// No description provided for @dashboardHighlightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get dashboardHighlightsTitle;

  /// No description provided for @dashboardSeeInsights.
  ///
  /// In en, this message translates to:
  /// **'See insights'**
  String get dashboardSeeInsights;

  /// No description provided for @dashboardTopCategory.
  ///
  /// In en, this message translates to:
  /// **'Top category'**
  String get dashboardTopCategory;

  /// No description provided for @dashboardBiggestExpense.
  ///
  /// In en, this message translates to:
  /// **'Biggest expense'**
  String get dashboardBiggestExpense;

  /// No description provided for @dashboardNoneYet.
  ///
  /// In en, this message translates to:
  /// **'None yet'**
  String get dashboardNoneYet;

  /// No description provided for @dashboardRecentPersonal.
  ///
  /// In en, this message translates to:
  /// **'Recent personal expenses'**
  String get dashboardRecentPersonal;

  /// No description provided for @dashboardRecentGroup.
  ///
  /// In en, this message translates to:
  /// **'Recent in {group}'**
  String dashboardRecentGroup(String group);

  /// No description provided for @dashboardSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get dashboardSeeAll;

  /// No description provided for @dashboardEmptyPersonalTitle.
  ///
  /// In en, this message translates to:
  /// **'No expenses yet'**
  String get dashboardEmptyPersonalTitle;

  /// No description provided for @dashboardEmptyPersonalMessage.
  ///
  /// In en, this message translates to:
  /// **'Add an expense to start seeing where your money goes.'**
  String get dashboardEmptyPersonalMessage;

  /// No description provided for @dashboardEmptyGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'No group expenses yet'**
  String get dashboardEmptyGroupTitle;

  /// No description provided for @dashboardEmptyGroupMessage.
  ///
  /// In en, this message translates to:
  /// **'Expenses added to {group} will show up here.'**
  String dashboardEmptyGroupMessage(String group);

  /// Floating button and empty-state button that open the new expense form.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get dashboardAddExpense;

  /// No description provided for @dashboardExpenseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{category} · {date}'**
  String dashboardExpenseSubtitle(String category, String date);

  /// No description provided for @insightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get insightsTitle;

  /// No description provided for @insightsRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh insights'**
  String get insightsRefreshTooltip;

  /// No description provided for @insightsTimeframeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time range'**
  String get insightsTimeframeLabel;

  /// No description provided for @insightsTimeframeWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get insightsTimeframeWeek;

  /// No description provided for @insightsTimeframeMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get insightsTimeframeMonth;

  /// No description provided for @insightsTimeframeYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get insightsTimeframeYear;

  /// No description provided for @insightsPeriodWeek.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get insightsPeriodWeek;

  /// No description provided for @insightsPeriodMonth.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get insightsPeriodMonth;

  /// No description provided for @insightsPeriodYear.
  ///
  /// In en, this message translates to:
  /// **'Last 12 months'**
  String get insightsPeriodYear;

  /// No description provided for @insightsScopePersonal.
  ///
  /// In en, this message translates to:
  /// **'Your personal expenses plus your share of group expenses'**
  String get insightsScopePersonal;

  /// No description provided for @insightsScopeGroup.
  ///
  /// In en, this message translates to:
  /// **'Everything spent in {group}'**
  String insightsScopeGroup(String group);

  /// No description provided for @insightsScopeGroupFallback.
  ///
  /// In en, this message translates to:
  /// **'this group'**
  String get insightsScopeGroupFallback;

  /// No description provided for @insightsTotalSpent.
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get insightsTotalSpent;

  /// No description provided for @insightsExpenseCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No expenses} =1{1 expense} other{{count} expenses}}'**
  String insightsExpenseCount(int count);

  /// No description provided for @insightsDailyAverage.
  ///
  /// In en, this message translates to:
  /// **'Daily average'**
  String get insightsDailyAverage;

  /// No description provided for @insightsBiggestExpense.
  ///
  /// In en, this message translates to:
  /// **'Biggest expense'**
  String get insightsBiggestExpense;

  /// No description provided for @insightsNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get insightsNone;

  /// No description provided for @insightsOtherCurrencies.
  ///
  /// In en, this message translates to:
  /// **'Also spent: {amounts}'**
  String insightsOtherCurrencies(String amounts);

  /// No description provided for @insightsOtherCurrenciesNote.
  ///
  /// In en, this message translates to:
  /// **'Other currencies aren\'t included in the totals or charts.'**
  String get insightsOtherCurrenciesNote;

  /// No description provided for @insightsTrendTitle.
  ///
  /// In en, this message translates to:
  /// **'Spending over time'**
  String get insightsTrendTitle;

  /// Screen reader summary of the spending chart.
  ///
  /// In en, this message translates to:
  /// **'Bar chart of spending, {period}. Highest: {date}, {amount}. {activeCount} of {bucketCount} with spending.'**
  String insightsTrendSummary(
    String period,
    String date,
    String amount,
    int activeCount,
    String bucketCount,
  );

  /// No description provided for @insightsDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String insightsDays(int count);

  /// No description provided for @insightsMonths.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 month} other{{count} months}}'**
  String insightsMonths(int count);

  /// No description provided for @insightsBarTooltip.
  ///
  /// In en, this message translates to:
  /// **'{date}\n{amount}'**
  String insightsBarTooltip(String date, String amount);

  /// No description provided for @insightsCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Spending by category'**
  String get insightsCategoriesTitle;

  /// No description provided for @insightsCategoriesSummary.
  ///
  /// In en, this message translates to:
  /// **'Donut chart of spending by category. {details}'**
  String insightsCategoriesSummary(String details);

  /// No description provided for @insightsCategoryRowLabel.
  ///
  /// In en, this message translates to:
  /// **'{category}: {amount}, {percent} of spending, {count}'**
  String insightsCategoryRowLabel(
    String category,
    String amount,
    String percent,
    String count,
  );

  /// No description provided for @insightsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No spending in this period'**
  String get insightsEmptyTitle;

  /// No description provided for @insightsEmptyPersonal.
  ///
  /// In en, this message translates to:
  /// **'Add an expense, or choose a longer time range.'**
  String get insightsEmptyPersonal;

  /// No description provided for @insightsEmptyGroup.
  ///
  /// In en, this message translates to:
  /// **'Expenses added to this group will show up here.'**
  String get insightsEmptyGroup;

  /// No description provided for @insightsAddExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get insightsAddExpense;

  /// No description provided for @insightsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your insights'**
  String get insightsErrorTitle;

  /// No description provided for @insightsExpenseDetail.
  ///
  /// In en, this message translates to:
  /// **'{category} · {date}'**
  String insightsExpenseDetail(String category, String date);

  /// Name of the AI assistant. 'Exevra' is not translated.
  ///
  /// In en, this message translates to:
  /// **'Exevra Assistant'**
  String get chatAssistantName;

  /// No description provided for @chatAnswersBy.
  ///
  /// In en, this message translates to:
  /// **'Answers by {provider}'**
  String chatAnswersBy(String provider);

  /// No description provided for @chatAuthorLine.
  ///
  /// In en, this message translates to:
  /// **'{name} · {provider}'**
  String chatAuthorLine(String name, String provider);

  /// No description provided for @chatDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Exevra Assistant can make mistakes. Not financial advice.'**
  String get chatDisclaimer;

  /// No description provided for @chatInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Response interrupted. Tap Retry.'**
  String get chatInterrupted;

  /// Note under an answer the user stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped.'**
  String get chatStopped;

  /// No description provided for @chatTruncated.
  ///
  /// In en, this message translates to:
  /// **'This answer reached its length limit and may be incomplete.'**
  String get chatTruncated;

  /// No description provided for @chatResponding.
  ///
  /// In en, this message translates to:
  /// **'Assistant is responding'**
  String get chatResponding;

  /// No description provided for @chatAnnounceComplete.
  ///
  /// In en, this message translates to:
  /// **'Response complete'**
  String get chatAnnounceComplete;

  /// No description provided for @chatAnnounceTruncated.
  ///
  /// In en, this message translates to:
  /// **'Response complete, but it may be cut short'**
  String get chatAnnounceTruncated;

  /// No description provided for @chatAnnounceFailed.
  ///
  /// In en, this message translates to:
  /// **'The assistant couldn\'t answer. {message}'**
  String chatAnnounceFailed(String message);

  /// No description provided for @chatAnnounceDeclined.
  ///
  /// In en, this message translates to:
  /// **'The assistant can\'t help with that question'**
  String get chatAnnounceDeclined;

  /// No description provided for @chatAnnounceStopped.
  ///
  /// In en, this message translates to:
  /// **'Response stopped'**
  String get chatAnnounceStopped;

  /// No description provided for @chatAnnounceInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Response interrupted'**
  String get chatAnnounceInterrupted;

  /// No description provided for @chatDeclinedFallback.
  ///
  /// In en, this message translates to:
  /// **'I can\'t help with that. Try asking about your spending, budgets or ways to save.'**
  String get chatDeclinedFallback;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask about your money'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Ask about your spending, budgets or ways to save, or tap a question below to get started.'**
  String get chatEmptyBody;

  /// No description provided for @chatPromptsLabel.
  ///
  /// In en, this message translates to:
  /// **'Suggested questions'**
  String get chatPromptsLabel;

  /// No description provided for @chatPromptTopCategories.
  ///
  /// In en, this message translates to:
  /// **'What are my top spending categories this month?'**
  String get chatPromptTopCategories;

  /// No description provided for @chatPromptCompareWeek.
  ///
  /// In en, this message translates to:
  /// **'Am I spending more than last week?'**
  String get chatPromptCompareWeek;

  /// No description provided for @chatPromptTips.
  ///
  /// In en, this message translates to:
  /// **'Give me 3 simple ways to spend less'**
  String get chatPromptTips;

  /// No description provided for @chatPromptBudgetRule.
  ///
  /// In en, this message translates to:
  /// **'Explain the 50/30/20 budgeting rule'**
  String get chatPromptBudgetRule;

  /// No description provided for @chatPromptGroupFood.
  ///
  /// In en, this message translates to:
  /// **'How much did my group spend on food recently?'**
  String get chatPromptGroupFood;

  /// No description provided for @chatErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the assistant. Check your connection and try again.'**
  String get chatErrorNetwork;

  /// No description provided for @chatErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The assistant took too long to respond. Please try again.'**
  String get chatErrorTimeout;

  /// No description provided for @chatErrorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get chatErrorUnauthorized;

  /// No description provided for @chatErrorConsent.
  ///
  /// In en, this message translates to:
  /// **'Allow the assistant to use your spending summary to continue.'**
  String get chatErrorConsent;

  /// Short-term (per minute) limit. Different from the daily limit.
  ///
  /// In en, this message translates to:
  /// **'You\'re sending messages quickly. Try again in a minute.'**
  String get chatErrorRateLimited;

  /// Daily limit. Different from the per-minute limit. time is the local reset time, e.g. 5:30 AM.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached today\'s assistant limit. It resets at {time}.'**
  String chatErrorQuota(String time);

  /// No description provided for @chatErrorTooLong.
  ///
  /// In en, this message translates to:
  /// **'That conversation is too long. Clear the chat and try again.'**
  String get chatErrorTooLong;

  /// No description provided for @chatErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The assistant is unavailable right now. Please try again shortly.'**
  String get chatErrorUnavailable;

  /// No description provided for @chatErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get chatErrorGeneric;

  /// No description provided for @chatClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear conversation'**
  String get chatClearTooltip;

  /// No description provided for @chatClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear conversation?'**
  String get chatClearTitle;

  /// No description provided for @chatClearMessage.
  ///
  /// In en, this message translates to:
  /// **'This deletes the conversation from this device. It can\'t be undone.'**
  String get chatClearMessage;

  /// No description provided for @chatClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get chatClearConfirm;

  /// No description provided for @chatJumpToLatest.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest'**
  String get chatJumpToLatest;

  /// No description provided for @chatInputHint.
  ///
  /// In en, this message translates to:
  /// **'Ask about your spending…'**
  String get chatInputHint;

  /// No description provided for @chatInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Message to the assistant'**
  String get chatInputLabel;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get chatSend;

  /// No description provided for @chatStop.
  ///
  /// In en, this message translates to:
  /// **'Stop response'**
  String get chatStop;

  /// No description provided for @chatCharacterCount.
  ///
  /// In en, this message translates to:
  /// **'{current}/{max}'**
  String chatCharacterCount(int current, int max);

  /// No description provided for @chatThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get chatThinking;

  /// Screen reader prefix of the user's own message.
  ///
  /// In en, this message translates to:
  /// **'You said'**
  String get chatYouSaid;

  /// No description provided for @chatCopyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy message'**
  String get chatCopyTooltip;

  /// No description provided for @chatCopied.
  ///
  /// In en, this message translates to:
  /// **'Message copied'**
  String get chatCopied;

  /// No description provided for @chatReportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Report response'**
  String get chatReportTooltip;

  /// No description provided for @chatOffTitle.
  ///
  /// In en, this message translates to:
  /// **'The assistant is off'**
  String get chatOffTitle;

  /// No description provided for @chatOffBody.
  ///
  /// In en, this message translates to:
  /// **'You can keep using Exevra without it, and turn it on whenever you like.'**
  String get chatOffBody;

  /// No description provided for @chatOffAction.
  ///
  /// In en, this message translates to:
  /// **'Turn on the assistant'**
  String get chatOffAction;

  /// No description provided for @chatConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you use {name}'**
  String chatConsentTitle(String name);

  /// No description provided for @chatConsentWhatTitle.
  ///
  /// In en, this message translates to:
  /// **'What is sent'**
  String get chatConsentWhatTitle;

  /// No description provided for @chatConsentWhatBody.
  ///
  /// In en, this message translates to:
  /// **'Your spending totals by category and month, your 15 most recent expenses (title, category, amount and date; for group expenses only your share), the names of your groups, your currency, time zone, language and today\'s date, and the messages you write, including earlier messages in this chat.'**
  String get chatConsentWhatBody;

  /// No description provided for @chatConsentWhoTitle.
  ///
  /// In en, this message translates to:
  /// **'Who receives it'**
  String get chatConsentWhoTitle;

  /// No description provided for @chatConsentWhoBody.
  ///
  /// In en, this message translates to:
  /// **'Anthropic\'s Claude answers your questions. If it is unavailable, Google\'s Gemini is used as a backup.'**
  String get chatConsentWhoBody;

  /// No description provided for @chatConsentWhyTitle.
  ///
  /// In en, this message translates to:
  /// **'Why'**
  String get chatConsentWhyTitle;

  /// No description provided for @chatConsentWhyBody.
  ///
  /// In en, this message translates to:
  /// **'So the assistant can answer questions about your own spending, budgets and ways to save.'**
  String get chatConsentWhyBody;

  /// No description provided for @chatConsentOptionalTitle.
  ///
  /// In en, this message translates to:
  /// **'It\'s optional'**
  String get chatConsentOptionalTitle;

  /// No description provided for @chatConsentOptionalBody.
  ///
  /// In en, this message translates to:
  /// **'You can use Exevra without the assistant and turn it off at any time in Settings. Turning it off also deletes this conversation from this device.'**
  String get chatConsentOptionalBody;

  /// No description provided for @chatConsentPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Read the privacy policy'**
  String get chatConsentPrivacy;

  /// No description provided for @chatConsentPrivacyFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the privacy policy. Please try again later.'**
  String get chatConsentPrivacyFailed;

  /// No description provided for @chatConsentAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow and continue'**
  String get chatConsentAllow;

  /// No description provided for @chatConsentNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get chatConsentNotNow;

  /// No description provided for @chatReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report response'**
  String get chatReportTitle;

  /// No description provided for @chatReportBody.
  ///
  /// In en, this message translates to:
  /// **'Tell us what was wrong. The answer text is sent with your report so we can review it.'**
  String get chatReportBody;

  /// No description provided for @chatReportReasonOffensive.
  ///
  /// In en, this message translates to:
  /// **'Offensive'**
  String get chatReportReasonOffensive;

  /// No description provided for @chatReportReasonHarmful.
  ///
  /// In en, this message translates to:
  /// **'Harmful or unsafe'**
  String get chatReportReasonHarmful;

  /// No description provided for @chatReportReasonInaccurate.
  ///
  /// In en, this message translates to:
  /// **'Inaccurate'**
  String get chatReportReasonInaccurate;

  /// No description provided for @chatReportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get chatReportReasonOther;

  /// No description provided for @chatReportNote.
  ///
  /// In en, this message translates to:
  /// **'Add a note (optional)'**
  String get chatReportNote;

  /// No description provided for @chatReportSend.
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get chatReportSend;

  /// No description provided for @chatReportSent.
  ///
  /// In en, this message translates to:
  /// **'Thanks. Your report was sent.'**
  String get chatReportSent;

  /// No description provided for @chatLinkOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open this link?'**
  String get chatLinkOpenTitle;

  /// No description provided for @chatLinkBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'This link can\'t be opened'**
  String get chatLinkBlockedTitle;

  /// No description provided for @chatLinkOpenBody.
  ///
  /// In en, this message translates to:
  /// **'It will open outside Exevra. Check the address first:'**
  String get chatLinkOpenBody;

  /// No description provided for @chatLinkBlockedBody.
  ///
  /// In en, this message translates to:
  /// **'Only secure (https) links can be opened. The address is:'**
  String get chatLinkBlockedBody;

  /// No description provided for @chatLinkCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get chatLinkCopy;

  /// No description provided for @chatLinkOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get chatLinkOpen;

  /// No description provided for @chatLinkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link.'**
  String get chatLinkOpenFailed;

  /// No description provided for @chatLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get chatLinkCopied;
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
