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
}
