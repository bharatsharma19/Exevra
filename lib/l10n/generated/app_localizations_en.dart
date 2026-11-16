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
  String get authEmailLabel => 'Email address';

  @override
  String get authEmailHint => 'name@example.com';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authNewPasswordLabel => 'New password';

  @override
  String get authConfirmPasswordLabel => 'Confirm password';

  @override
  String get authConfirmNewPasswordLabel => 'Confirm new password';

  @override
  String get authPasswordRules =>
      'At least 8 characters with upper and lower case letters and a number.';

  @override
  String get authCodeLabel => '6-digit code';

  @override
  String get authNameLabel => 'Your name';

  @override
  String get authOr => 'or';

  @override
  String get authContinueWithGoogle => 'Continue with Google';

  @override
  String get authContinueWithApple => 'Continue with Apple';

  @override
  String get authLoginTitle => 'Welcome back';

  @override
  String get authLoginSubtitle =>
      'Sign in to track your spending and split costs with others.';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authNoAccount => 'Don\'t have an account?';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authRegisterTitle => 'Create your account';

  @override
  String get authRegisterSubtitle =>
      'Track your own spending and split costs with others.';

  @override
  String get authAgreeTerms =>
      'I agree to the Terms of Service and the Privacy Policy.';

  @override
  String get authTermsLink => 'Terms of Service';

  @override
  String get authPrivacyLink => 'Privacy Policy';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authHaveAccount => 'Already have an account?';

  @override
  String get authResetPasswordAction => 'Reset password';

  @override
  String get authVerifyTitle => 'Verify your email';

  @override
  String get authVerifySubtitle =>
      'We sent a confirmation link and a 6-digit code to';

  @override
  String get authVerifyCode => 'Verify code';

  @override
  String get authVerifyConfirmed => 'I\'ve confirmed my email';

  @override
  String get authResendEmail => 'Resend email';

  @override
  String get authResendCode => 'Resend code';

  @override
  String authResendIn(String time) {
    return 'You can resend in $time';
  }

  @override
  String authResendInSemantics(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '1 second',
    );
    return 'Resend available in $_temp0';
  }

  @override
  String get authResendReady => 'You can send a new email now.';

  @override
  String get authEmailResent => 'We sent a new email. Check your inbox.';

  @override
  String get authEnterPasswordToContinue => 'Enter your password to continue.';

  @override
  String get authNotConfirmedYet =>
      'Your email isn\'t confirmed yet. Open the link or enter the code from the email.';

  @override
  String get authCheckSpam => 'Can\'t find it? Check your spam folder.';

  @override
  String get authUseDifferentEmail => 'Use a different email';

  @override
  String get authForgotTitle => 'Reset your password';

  @override
  String get authForgotSubtitle =>
      'Enter your account\'s email address and we\'ll send you a 6-digit code.';

  @override
  String get authCodeTitle => 'Enter the code';

  @override
  String authCodeSubtitle(String email) {
    return 'Enter the 6-digit code we emailed to $email and choose a new password.';
  }

  @override
  String get authSendCode => 'Send code';

  @override
  String get authCodeSent =>
      'If an account exists for this address, we emailed it a 6-digit code.';

  @override
  String get authSetNewPassword => 'Set new password';

  @override
  String get authResetTitle => 'Choose a new password';

  @override
  String get authResetSubtitle => 'Set a new password to finish resetting it.';

  @override
  String authResetSubtitleFor(String email) {
    return 'Set a new password for $email to finish resetting it.';
  }

  @override
  String get authSavePassword => 'Save password';

  @override
  String get authCancelAndSignOut => 'Cancel and sign out';

  @override
  String get authBack => 'Back';

  @override
  String get lockTitle => 'Exevra is locked';

  @override
  String get lockMessage =>
      'Use your fingerprint, face or device PIN to continue.';

  @override
  String get lockUnlock => 'Unlock';

  @override
  String get lockChecking => 'Checking it\'s you…';

  @override
  String get lockTurnOffExplanation =>
      'You just signed in, so you can turn App Lock off on this device. Turn it on again in Profile once the device has a screen lock.';

  @override
  String get lockTurnOff => 'Turn off App Lock';

  @override
  String get lockSignOut => 'Sign out';

  @override
  String get lockSignOutInstead => 'Sign out instead';

  @override
  String get lockSignOutConfirm =>
      'Sign out on this device? App Lock stays on for this account when you sign in again.';

  @override
  String get lockCoverLabel => 'Exevra is hidden while in the background';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileLoadFailed => 'We couldn\'t load your profile.';

  @override
  String get profileEditTooltip => 'Edit profile';

  @override
  String get profileEditTitle => 'Edit profile';

  @override
  String get profileNameLabel => 'Display name';

  @override
  String get profileNameHelper => 'Shown to people in your groups.';

  @override
  String get profilePhotoLabel => 'Photo link (optional)';

  @override
  String get profilePhotoHint => 'https://…';

  @override
  String get profilePhotoHelper =>
      'A link to an image that starts with https://.';

  @override
  String get profileSaved => 'Profile updated.';

  @override
  String get profileFallbackName => 'You';

  @override
  String profileAvatarLabel(String name) {
    return 'Profile photo of $name';
  }

  @override
  String get settingsSection => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeHint => 'System follows your device setting.';

  @override
  String get settingsThemeSelected => 'Selected';

  @override
  String get settingsCurrency => 'Default currency';

  @override
  String settingsCurrencySubtitle(String code, String name) {
    return '$code · $name. Used for new personal expenses; groups keep their own currency.';
  }

  @override
  String get settingsCurrencyPickerTitle => 'Choose a currency';

  @override
  String get settingsCurrencySearch => 'Search currencies';

  @override
  String settingsCurrencyNoMatch(String query) {
    return 'No currency matches \"$query\".';
  }

  @override
  String get settingsCurrencySelected => 'Selected';

  @override
  String settingsCurrencySaved(String code) {
    return 'Default currency set to $code.';
  }

  @override
  String get settingsAppLock => 'App Lock';

  @override
  String get settingsAppLockOn =>
      'On. Exevra asks for your fingerprint, face or device PIN when it opens.';

  @override
  String get settingsAppLockOff =>
      'Ask for your fingerprint, face or device PIN when Exevra opens.';

  @override
  String get settingsAppLockChecking => 'Checking it\'s you…';

  @override
  String get settingsAppLockTurnedOn => 'App Lock is on.';

  @override
  String get settingsAppLockTurnedOff => 'App Lock is off.';

  @override
  String get settingsHaptics => 'Vibration feedback';

  @override
  String get settingsHapticsSubtitle =>
      'A light vibration when you tap buttons and switches.';

  @override
  String get settingsAssistant => 'AI assistant';

  @override
  String get settingsAssistantOn =>
      'On. The assistant can use a summary of your spending to answer your questions.';

  @override
  String get settingsAssistantOff =>
      'Off. Turn it on to ask questions about your spending.';

  @override
  String settingsSaveFailed(String reason) {
    return 'We couldn\'t save that setting. $reason';
  }

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignOutTitle => 'Sign out?';

  @override
  String get settingsSignOutMessage =>
      'Your data stays in your account. To come back, sign in again with your email and password or Google. App Lock is turned off on this device.';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsDeleteAccountSubtitle =>
      'Permanently delete your account and personal data.';

  @override
  String get settingsDeleteTitle => 'Delete your account?';

  @override
  String get settingsDeleteMessage =>
      'This permanently deletes your profile, your personal expenses, your settings and your AI assistant history.\n\nExpenses you added to shared groups stay with those groups so the other members\' balances remain correct; they will show as \"Former member\". If you are a group admin, the longest-standing member becomes admin; groups with no other members are deleted. Payments still waiting for confirmation are cancelled.\n\nThis can\'t be undone.';

  @override
  String get settingsDeleting => 'Deleting your account…';

  @override
  String get settingsDeleted => 'Your account was deleted.';

  @override
  String get settingsReauthTitle => 'Confirm it\'s you';

  @override
  String get settingsReauthPassword =>
      'For your security, enter your password to delete your account.';

  @override
  String settingsReauthProvider(String provider) {
    return 'For your security, sign in with $provider again to delete your account.';
  }

  @override
  String settingsReauthContinueWith(String provider) {
    return 'Continue with $provider';
  }

  @override
  String get settingsReauthContinue => 'Continue';

  @override
  String get settingsReauthChecking => 'Checking it\'s you…';

  @override
  String get inviteTitle => 'Group invitation';

  @override
  String get inviteClose => 'Close';

  @override
  String get inviteLoading => 'Checking the invitation…';

  @override
  String get inviteProblemTitle => 'This invitation can\'t be opened';

  @override
  String inviteSignedInAs(String email) {
    return 'You\'re signed in as $email.';
  }

  @override
  String inviteWrongEmailHelp(String email) {
    return 'Sign out and sign in with the address the invitation was sent to, or ask the group admin to invite $email instead.';
  }

  @override
  String get inviteSwitchAccount => 'Sign out and use the invited address';

  @override
  String get inviteBack => 'Back';

  @override
  String get inviteGoHome => 'Go to Home';

  @override
  String get inviteSignedOutTitle => 'You\'ve been invited to a group';

  @override
  String get inviteSignedOutMessage =>
      'Sign in or create an account with the invited email address to see the invitation and join.';

  @override
  String get inviteSignIn => 'Sign in to see it';

  @override
  String get inviteCreateAccount => 'Create an account';

  @override
  String invitePendingTitle(String group) {
    return 'You\'re invited to $group';
  }

  @override
  String invitePendingMessage(String inviter) {
    return '$inviter invited you to share expenses in this group.';
  }

  @override
  String get inviteSomeone => 'A group admin';

  @override
  String inviteAcceptedTitle(String group) {
    return 'You\'re already in $group';
  }

  @override
  String get inviteAcceptedMessage => 'You are already a member of this group.';

  @override
  String get inviteExpiredTitle => 'This invitation has expired';

  @override
  String get inviteExpiredMessage =>
      'Ask someone in the group to send you a new invitation.';

  @override
  String get inviteCancelledTitle => 'This invitation is no longer active';

  @override
  String get inviteCancelledMessage =>
      'It was cancelled or declined. Ask the group admin for a new one if you still want to join.';

  @override
  String get inviteGroupLabel => 'Group';

  @override
  String get inviteInvitedBy => 'Invited by';

  @override
  String get inviteRoleLabel => 'Your role';

  @override
  String get inviteValidUntil => 'Valid until';

  @override
  String get inviteExpiredOn => 'Expired on';

  @override
  String get inviteAccept => 'Join group';

  @override
  String get inviteDecline => 'Decline';

  @override
  String get inviteDeclineTitle => 'Decline this invitation?';

  @override
  String inviteDeclineMessage(String group) {
    return 'You won\'t join $group. Someone in the group can invite you again later.';
  }

  @override
  String get inviteDeclined => 'Invitation declined.';

  @override
  String inviteJoined(String group) {
    return 'You joined $group.';
  }

  @override
  String get inviteOpenGroup => 'Open the group';

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
