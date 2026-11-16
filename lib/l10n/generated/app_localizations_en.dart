// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Exevra';

  @override
  String get appTagline => 'Expense & Split Tracker';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get retry => 'Retry';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get undo => 'Undo';

  @override
  String get loading => 'Loading…';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get genericErrorMessage => 'Something went wrong. Please try again.';

  @override
  String get discardChangesTitle => 'Discard changes?';

  @override
  String get discardChangesMessage =>
      'You have unsaved changes. If you leave now, they will be lost.';

  @override
  String get discardChangesConfirm => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get offlineTitle => 'You\'re offline';

  @override
  String get offlineMessage => 'Some actions need an internet connection.';

  @override
  String get snackbarSuccessLabel => 'Success';

  @override
  String get snackbarErrorLabel => 'Error';

  @override
  String get snackbarInfoLabel => 'Information';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusConfirmed => 'Confirmed';

  @override
  String get statusVoided => 'Voided';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleMember => 'Member';

  @override
  String get roleViewer => 'Viewer';

  @override
  String amountPositive(String amount) {
    return 'Plus $amount';
  }

  @override
  String amountNegative(String amount) {
    return 'Minus $amount';
  }

  @override
  String get linkOpenFailed =>
      'Couldn\'t open the link. Please try again later.';

  @override
  String get opensInBrowser => 'Opens in your browser';

  @override
  String get aboutTitle => 'About';

  @override
  String aboutVersion(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get aboutCredit => 'Designed & developed by Bharat Sharma';

  @override
  String get aboutLegalese => '© 2026 Bharat Sharma';

  @override
  String get aboutSupportSection => 'Help & legal';

  @override
  String get aboutPrivacyPolicy => 'Privacy policy';

  @override
  String get aboutTermsOfUse => 'Terms of use';

  @override
  String get aboutHelpSupport => 'Help & support';

  @override
  String get aboutLicenses => 'Open-source licenses';

  @override
  String get aboutAccountSection => 'Account';

  @override
  String get aboutDeleteAccountInfo => 'Account deletion info';

  @override
  String get aboutDeleteAccountInfoSubtitle =>
      'How to delete your account and data, also without the app';

  @override
  String get aboutDeleteAccount => 'Delete account';

  @override
  String get supportEmailSubject => 'Exevra support';

  @override
  String supportEmailBody(String version) {
    return 'App version: $version';
  }

  @override
  String supportEmailOpenFailed(String email) {
    return 'Couldn\'t open an email app. Write to us at $email.';
  }

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingSkipTooltip => 'Skip the introduction';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String onboardingPageIndicator(int current, int total) {
    return 'Page $current of $total';
  }

  @override
  String onboardingPageAnnouncement(int current, int total, String title) {
    return 'Page $current of $total: $title';
  }

  @override
  String get onboardingTrackTitle => 'Track every expense';

  @override
  String get onboardingTrackBody =>
      'Log personal and shared spending in your own currency and see where your money goes.';

  @override
  String get onboardingSplitTitle => 'Split and settle up';

  @override
  String get onboardingSplitBody =>
      'Share costs with a group and see who owes whom. When you settle up, the payment counts once the person who receives it confirms it.';

  @override
  String get onboardingAssistantTitle => 'Ask about your spending';

  @override
  String get onboardingAssistantBody =>
      'Ask the assistant questions about your spending. It\'s optional and respects your privacy: it only sees your spending totals if you allow it, and you can turn it off in Settings.';

  @override
  String get firstExpenseNudgeTitle => 'Add your first expense';

  @override
  String get firstExpenseNudgeMessage =>
      'Record a purchase to start seeing where your money goes.';

  @override
  String get firstExpenseNudgeAction => 'Add expense';

  @override
  String get firstExpenseNudgeDismiss => 'Dismiss tip';

  @override
  String get shellNavHome => 'Home';

  @override
  String get shellNavExpenses => 'Expenses';

  @override
  String get shellNavInsights => 'Insights';

  @override
  String get shellNavAssistant => 'Assistant';

  @override
  String get shellNavProfile => 'Profile';

  @override
  String get shellOfflineMessage =>
      'Changes can\'t be saved until you reconnect.';

  @override
  String get dashboardGreetingMorning => 'Good morning';

  @override
  String get dashboardGreetingAfternoon => 'Good afternoon';

  @override
  String get dashboardGreetingEvening => 'Good evening';

  @override
  String get dashboardScopePersonal => 'Personal';

  @override
  String dashboardScopeButtonLabel(String scope) {
    return 'Showing $scope. Change view';
  }

  @override
  String get dashboardScopeButtonTooltip => 'Change view';

  @override
  String get dashboardSwitcherTitle => 'Show spending for';

  @override
  String get dashboardSwitcherPersonalSubtitle =>
      'Your expenses and your share of group expenses';

  @override
  String get dashboardSwitcherGroupSubtitle => 'Everything spent in this group';

  @override
  String get dashboardSwitcherSelected => 'Selected';

  @override
  String get dashboardSwitcherManageGroups => 'Manage groups';

  @override
  String get dashboardYourSpending => 'Your spending';

  @override
  String get dashboardGroupTotal => 'Group total';

  @override
  String get dashboardPersonalScopeNote =>
      'Your personal expenses plus your share of group expenses';

  @override
  String dashboardGroupScopeNote(String group) {
    return 'Everything spent in $group, by everyone';
  }

  @override
  String get dashboardTotalUnavailable => 'Not available';

  @override
  String dashboardSummaryLabel(String title, String period, String amount) {
    return '$title, $period: $amount';
  }

  @override
  String get dashboardDailyAverage => 'Daily average';

  @override
  String get dashboardExpenseCountLabel => 'Expenses';

  @override
  String dashboardOtherCurrencies(String amounts) {
    return 'Also spent in other currencies: $amounts. Not included in this total.';
  }

  @override
  String get dashboardBalanceTitle => 'Your balance in this group';

  @override
  String dashboardBalanceYouOwe(String amount) {
    return 'You owe $amount';
  }

  @override
  String dashboardBalanceOwesYou(String amount) {
    return 'The group owes you $amount';
  }

  @override
  String get dashboardBalanceSettled => 'You\'re all settled up';

  @override
  String get dashboardAskAssistant => 'Ask the assistant';

  @override
  String get dashboardAskAssistantSubtitle =>
      'Questions about your spending, budgets or saving';

  @override
  String get dashboardSettleUpTitle => 'Who owes whom';

  @override
  String get dashboardSettleUpAction => 'Settle up';

  @override
  String dashboardYouOwePerson(String name) {
    return 'You owe $name';
  }

  @override
  String dashboardPersonOwesYou(String name) {
    return '$name owes you';
  }

  @override
  String dashboardPersonOwesPerson(String from, String to) {
    return '$from owes $to';
  }

  @override
  String get dashboardMemberFallback => 'A member';

  @override
  String get dashboardHighlightsTitle => 'Highlights';

  @override
  String get dashboardSeeInsights => 'See insights';

  @override
  String get dashboardTopCategory => 'Top category';

  @override
  String get dashboardBiggestExpense => 'Biggest expense';

  @override
  String get dashboardNoneYet => 'None yet';

  @override
  String get dashboardRecentPersonal => 'Recent personal expenses';

  @override
  String dashboardRecentGroup(String group) {
    return 'Recent in $group';
  }

  @override
  String get dashboardSeeAll => 'See all';

  @override
  String get dashboardEmptyPersonalTitle => 'No expenses yet';

  @override
  String get dashboardEmptyPersonalMessage =>
      'Add an expense to start seeing where your money goes.';

  @override
  String get dashboardEmptyGroupTitle => 'No group expenses yet';

  @override
  String dashboardEmptyGroupMessage(String group) {
    return 'Expenses added to $group will show up here.';
  }

  @override
  String get dashboardAddExpense => 'Add expense';

  @override
  String dashboardExpenseSubtitle(String category, String date) {
    return '$category · $date';
  }

  @override
  String get insightsTitle => 'Insights';

  @override
  String get insightsRefreshTooltip => 'Refresh insights';

  @override
  String get insightsTimeframeLabel => 'Time range';

  @override
  String get insightsTimeframeWeek => 'Week';

  @override
  String get insightsTimeframeMonth => 'Month';

  @override
  String get insightsTimeframeYear => 'Year';

  @override
  String get insightsPeriodWeek => 'Last 7 days';

  @override
  String get insightsPeriodMonth => 'Last 30 days';

  @override
  String get insightsPeriodYear => 'Last 12 months';

  @override
  String get insightsScopePersonal =>
      'Your personal expenses plus your share of group expenses';

  @override
  String insightsScopeGroup(String group) {
    return 'Everything spent in $group';
  }

  @override
  String get insightsScopeGroupFallback => 'this group';

  @override
  String get insightsTotalSpent => 'Total spent';

  @override
  String insightsExpenseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count expenses',
      one: '1 expense',
      zero: 'No expenses',
    );
    return '$_temp0';
  }

  @override
  String get insightsDailyAverage => 'Daily average';

  @override
  String get insightsBiggestExpense => 'Biggest expense';

  @override
  String get insightsNone => 'None';

  @override
  String insightsOtherCurrencies(String amounts) {
    return 'Also spent: $amounts';
  }

  @override
  String get insightsOtherCurrenciesNote =>
      'Other currencies aren\'t included in the totals or charts.';

  @override
  String get insightsTrendTitle => 'Spending over time';

  @override
  String insightsTrendSummary(
    String period,
    String date,
    String amount,
    int activeCount,
    String bucketCount,
  ) {
    return 'Bar chart of spending, $period. Highest: $date, $amount. $activeCount of $bucketCount with spending.';
  }

  @override
  String insightsDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String insightsMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String insightsBarTooltip(String date, String amount) {
    return '$date\n$amount';
  }

  @override
  String get insightsCategoriesTitle => 'Spending by category';

  @override
  String insightsCategoriesSummary(String details) {
    return 'Donut chart of spending by category. $details';
  }

  @override
  String insightsCategoryRowLabel(
    String category,
    String amount,
    String percent,
    String count,
  ) {
    return '$category: $amount, $percent of spending, $count';
  }

  @override
  String get insightsEmptyTitle => 'No spending in this period';

  @override
  String get insightsEmptyPersonal =>
      'Add an expense, or choose a longer time range.';

  @override
  String get insightsEmptyGroup =>
      'Expenses added to this group will show up here.';

  @override
  String get insightsAddExpense => 'Add expense';

  @override
  String get insightsErrorTitle => 'Couldn\'t load your insights';

  @override
  String insightsExpenseDetail(String category, String date) {
    return '$category · $date';
  }

  @override
  String get chatAssistantName => 'Exevra Assistant';

  @override
  String chatAnswersBy(String provider) {
    return 'Answers by $provider';
  }

  @override
  String chatAuthorLine(String name, String provider) {
    return '$name · $provider';
  }

  @override
  String get chatDisclaimer =>
      'Exevra Assistant can make mistakes. Not financial advice.';

  @override
  String get chatInterrupted => 'Response interrupted. Tap Retry.';

  @override
  String get chatStopped => 'Stopped.';

  @override
  String get chatTruncated =>
      'This answer reached its length limit and may be incomplete.';

  @override
  String get chatResponding => 'Assistant is responding';

  @override
  String get chatAnnounceComplete => 'Response complete';

  @override
  String get chatAnnounceTruncated =>
      'Response complete, but it may be cut short';

  @override
  String chatAnnounceFailed(String message) {
    return 'The assistant couldn\'t answer. $message';
  }

  @override
  String get chatAnnounceDeclined =>
      'The assistant can\'t help with that question';

  @override
  String get chatAnnounceStopped => 'Response stopped';

  @override
  String get chatAnnounceInterrupted => 'Response interrupted';

  @override
  String get chatDeclinedFallback =>
      'I can\'t help with that. Try asking about your spending, budgets or ways to save.';

  @override
  String get chatEmptyTitle => 'Ask about your money';

  @override
  String get chatEmptyBody =>
      'Ask about your spending, budgets or ways to save, or tap a question below to get started.';

  @override
  String get chatPromptsLabel => 'Suggested questions';

  @override
  String get chatPromptTopCategories =>
      'What are my top spending categories this month?';

  @override
  String get chatPromptCompareWeek => 'Am I spending more than last week?';

  @override
  String get chatPromptTips => 'Give me 3 simple ways to spend less';

  @override
  String get chatPromptBudgetRule => 'Explain the 50/30/20 budgeting rule';

  @override
  String get chatPromptGroupFood =>
      'How much did my group spend on food recently?';

  @override
  String get chatErrorNetwork =>
      'Couldn\'t reach the assistant. Check your connection and try again.';

  @override
  String get chatErrorTimeout =>
      'The assistant took too long to respond. Please try again.';

  @override
  String get chatErrorUnauthorized =>
      'Your session has expired. Please sign in again.';

  @override
  String get chatErrorConsent =>
      'Allow the assistant to use your spending summary to continue.';

  @override
  String get chatErrorRateLimited =>
      'You\'re sending messages quickly. Try again in a minute.';

  @override
  String get chatErrorQuota =>
      'You\'ve reached today\'s assistant limit. It resets at midnight UTC.';

  @override
  String get chatErrorTooLong =>
      'That conversation is too long. Clear the chat and try again.';

  @override
  String get chatErrorUnavailable =>
      'The assistant is unavailable right now. Please try again shortly.';

  @override
  String get chatErrorGeneric => 'Something went wrong. Please try again.';

  @override
  String get chatClearTooltip => 'Clear conversation';

  @override
  String get chatClearTitle => 'Clear conversation?';

  @override
  String get chatClearMessage =>
      'This deletes the conversation from this device. It can\'t be undone.';

  @override
  String get chatClearConfirm => 'Clear';

  @override
  String get chatJumpToLatest => 'Jump to latest';

  @override
  String get chatInputHint => 'Ask about your spending…';

  @override
  String get chatInputLabel => 'Message to the assistant';

  @override
  String get chatSend => 'Send message';

  @override
  String get chatStop => 'Stop response';

  @override
  String chatCharacterCount(int current, int max) {
    return '$current/$max';
  }

  @override
  String get chatThinking => 'Thinking…';

  @override
  String get chatYouSaid => 'You said';

  @override
  String get chatCopyTooltip => 'Copy message';

  @override
  String get chatCopied => 'Message copied';

  @override
  String get chatReportTooltip => 'Report response';

  @override
  String get chatOffTitle => 'The assistant is off';

  @override
  String get chatOffBody =>
      'You can keep using Exevra without it, and turn it on whenever you like.';

  @override
  String get chatOffAction => 'Turn on the assistant';

  @override
  String chatConsentTitle(String name) {
    return 'Before you use $name';
  }

  @override
  String get chatConsentWhatTitle => 'What is sent';

  @override
  String get chatConsentWhatBody =>
      'Your spending totals by category and month, your 15 most recent expenses (title, category, amount and date; for group expenses only your share), the names of your groups, your currency, time zone, language and today\'s date, and the messages you write, including earlier messages in this chat.';

  @override
  String get chatConsentWhoTitle => 'Who receives it';

  @override
  String get chatConsentWhoBody =>
      'Anthropic\'s Claude answers your questions. If it is unavailable, Google\'s Gemini is used as a backup.';

  @override
  String get chatConsentWhyTitle => 'Why';

  @override
  String get chatConsentWhyBody =>
      'So the assistant can answer questions about your own spending, budgets and ways to save.';

  @override
  String get chatConsentOptionalTitle => 'It\'s optional';

  @override
  String get chatConsentOptionalBody =>
      'You can use Exevra without the assistant and turn it off at any time in Settings. Turning it off also deletes this conversation from this device.';

  @override
  String get chatConsentPrivacy => 'Read the privacy policy';

  @override
  String get chatConsentPrivacyFailed =>
      'Couldn\'t open the privacy policy. Please try again later.';

  @override
  String get chatConsentAllow => 'Allow and continue';

  @override
  String get chatConsentNotNow => 'Not now';

  @override
  String get chatReportTitle => 'Report response';

  @override
  String get chatReportBody =>
      'Tell us what was wrong. The answer text is sent with your report so we can review it.';

  @override
  String get chatReportReasonOffensive => 'Offensive';

  @override
  String get chatReportReasonHarmful => 'Harmful or unsafe';

  @override
  String get chatReportReasonInaccurate => 'Inaccurate';

  @override
  String get chatReportReasonOther => 'Something else';

  @override
  String get chatReportNote => 'Add a note (optional)';

  @override
  String get chatReportSend => 'Send report';

  @override
  String get chatReportSent => 'Thanks. Your report was sent.';

  @override
  String get chatLinkOpenTitle => 'Open this link?';

  @override
  String get chatLinkBlockedTitle => 'This link can\'t be opened';

  @override
  String get chatLinkOpenBody =>
      'It will open outside Exevra. Check the address first:';

  @override
  String get chatLinkBlockedBody =>
      'Only secure (https) links can be opened. The address is:';

  @override
  String get chatLinkCopy => 'Copy link';

  @override
  String get chatLinkOpen => 'Open';

  @override
  String get chatLinkOpenFailed => 'Couldn\'t open the link.';

  @override
  String get chatLinkCopied => 'Link copied';
}
