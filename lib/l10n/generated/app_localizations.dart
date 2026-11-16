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

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get authEmailLabel;

  /// No description provided for @authEmailHint.
  ///
  /// In en, this message translates to:
  /// **'name@example.com'**
  String get authEmailHint;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get authNewPasswordLabel;

  /// No description provided for @authConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authConfirmPasswordLabel;

  /// No description provided for @authConfirmNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get authConfirmNewPasswordLabel;

  /// Helper text under a new password field.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters with upper and lower case letters and a number.'**
  String get authPasswordRules;

  /// Label of the field for the code from the email.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get authCodeLabel;

  /// No description provided for @authNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get authNameLabel;

  /// Divider between email sign-in and the Google or Apple buttons.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOr;

  /// No description provided for @authContinueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueWithGoogle;

  /// No description provided for @authContinueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get authContinueWithApple;

  /// No description provided for @authLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authLoginTitle;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to track your spending and split costs with others.'**
  String get authLoginSubtitle;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get authNoAccount;

  /// No description provided for @authSignUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUp;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track your own spending and split costs with others.'**
  String get authRegisterSubtitle;

  /// Label of the sign-up checkbox. The two documents open from the links under it.
  ///
  /// In en, this message translates to:
  /// **'I agree to the Terms of Service and the Privacy Policy.'**
  String get authAgreeTerms;

  /// No description provided for @authTermsLink.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get authTermsLink;

  /// No description provided for @authPrivacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get authPrivacyLink;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authHaveAccount;

  /// Button shown when an account already exists for the email.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get authResetPasswordAction;

  /// No description provided for @authVerifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get authVerifyTitle;

  /// Followed by the email address on its own line.
  ///
  /// In en, this message translates to:
  /// **'We sent a confirmation link and a 6-digit code to'**
  String get authVerifySubtitle;

  /// No description provided for @authVerifyCode.
  ///
  /// In en, this message translates to:
  /// **'Verify code'**
  String get authVerifyCode;

  /// No description provided for @authVerifyConfirmed.
  ///
  /// In en, this message translates to:
  /// **'I\'ve confirmed my email'**
  String get authVerifyConfirmed;

  /// No description provided for @authResendEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend email'**
  String get authResendEmail;

  /// No description provided for @authResendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get authResendCode;

  /// Shown while a new email cannot be sent yet. {time} is a countdown such as 0:42.
  ///
  /// In en, this message translates to:
  /// **'You can resend in {time}'**
  String authResendIn(String time);

  /// Screen reader label of the disabled resend button.
  ///
  /// In en, this message translates to:
  /// **'Resend available in {seconds, plural, =1{1 second} other{{seconds} seconds}}'**
  String authResendInSemantics(int seconds);

  /// Announced to screen readers when the resend countdown ends.
  ///
  /// In en, this message translates to:
  /// **'You can send a new email now.'**
  String get authResendReady;

  /// No description provided for @authEmailResent.
  ///
  /// In en, this message translates to:
  /// **'We sent a new email. Check your inbox.'**
  String get authEmailResent;

  /// No description provided for @authEnterPasswordToContinue.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to continue.'**
  String get authEnterPasswordToContinue;

  /// No description provided for @authNotConfirmedYet.
  ///
  /// In en, this message translates to:
  /// **'Your email isn\'t confirmed yet. Open the link or enter the code from the email.'**
  String get authNotConfirmedYet;

  /// No description provided for @authCheckSpam.
  ///
  /// In en, this message translates to:
  /// **'Can\'t find it? Check your spam folder.'**
  String get authCheckSpam;

  /// No description provided for @authUseDifferentEmail.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get authUseDifferentEmail;

  /// No description provided for @authForgotTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get authForgotTitle;

  /// No description provided for @authForgotSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your account\'s email address and we\'ll send you a 6-digit code.'**
  String get authForgotSubtitle;

  /// No description provided for @authCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code'**
  String get authCodeTitle;

  /// No description provided for @authCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code we emailed to {email} and choose a new password.'**
  String authCodeSubtitle(String email);

  /// No description provided for @authSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get authSendCode;

  /// No description provided for @authCodeSent.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for this address, we emailed it a 6-digit code.'**
  String get authCodeSent;

  /// No description provided for @authSetNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get authSetNewPassword;

  /// No description provided for @authResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get authResetTitle;

  /// No description provided for @authResetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set a new password to finish resetting it.'**
  String get authResetSubtitle;

  /// No description provided for @authResetSubtitleFor.
  ///
  /// In en, this message translates to:
  /// **'Set a new password for {email} to finish resetting it.'**
  String authResetSubtitleFor(String email);

  /// No description provided for @authSavePassword.
  ///
  /// In en, this message translates to:
  /// **'Save password'**
  String get authSavePassword;

  /// No description provided for @authCancelAndSignOut.
  ///
  /// In en, this message translates to:
  /// **'Cancel and sign out'**
  String get authCancelAndSignOut;

  /// No description provided for @authBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get authBack;

  /// No description provided for @lockTitle.
  ///
  /// In en, this message translates to:
  /// **'Exevra is locked'**
  String get lockTitle;

  /// No description provided for @lockMessage.
  ///
  /// In en, this message translates to:
  /// **'Use your fingerprint, face or device PIN to continue.'**
  String get lockMessage;

  /// No description provided for @lockUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get lockUnlock;

  /// Shown while the fingerprint, face or PIN prompt is open.
  ///
  /// In en, this message translates to:
  /// **'Checking it\'s you…'**
  String get lockChecking;

  /// No description provided for @lockTurnOffExplanation.
  ///
  /// In en, this message translates to:
  /// **'You just signed in, so you can turn App Lock off on this device. Turn it on again in Profile once the device has a screen lock.'**
  String get lockTurnOffExplanation;

  /// No description provided for @lockTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off App Lock'**
  String get lockTurnOff;

  /// No description provided for @lockSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get lockSignOut;

  /// No description provided for @lockSignOutInstead.
  ///
  /// In en, this message translates to:
  /// **'Sign out instead'**
  String get lockSignOutInstead;

  /// No description provided for @lockSignOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out on this device? App Lock stays on for this account when you sign in again.'**
  String get lockSignOutConfirm;

  /// Screen reader label of the cover shown in the app switcher.
  ///
  /// In en, this message translates to:
  /// **'Exevra is hidden while in the background'**
  String get lockCoverLabel;

  /// Title of the Profile tab.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your profile.'**
  String get profileLoadFailed;

  /// No description provided for @profileEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get profileEditTooltip;

  /// No description provided for @profileEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get profileEditTitle;

  /// No description provided for @profileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get profileNameLabel;

  /// No description provided for @profileNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Shown to people in your groups.'**
  String get profileNameHelper;

  /// No description provided for @profilePhotoLabel.
  ///
  /// In en, this message translates to:
  /// **'Photo link (optional)'**
  String get profilePhotoLabel;

  /// No description provided for @profilePhotoHint.
  ///
  /// In en, this message translates to:
  /// **'https://…'**
  String get profilePhotoHint;

  /// No description provided for @profilePhotoHelper.
  ///
  /// In en, this message translates to:
  /// **'A link to an image that starts with https://.'**
  String get profilePhotoHelper;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile updated.'**
  String get profileSaved;

  /// Shown when the account has no name yet.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get profileFallbackName;

  /// No description provided for @profileAvatarLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile photo of {name}'**
  String profileAvatarLabel(String name);

  /// No description provided for @settingsSection.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsSection;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeHint.
  ///
  /// In en, this message translates to:
  /// **'System follows your device setting.'**
  String get settingsThemeHint;

  /// No description provided for @settingsCurrency.
  ///
  /// In en, this message translates to:
  /// **'Default currency'**
  String get settingsCurrency;

  /// No description provided for @settingsCurrencySubtitle.
  ///
  /// In en, this message translates to:
  /// **'{code} · {name}. Used for new personal expenses; groups keep their own currency.'**
  String settingsCurrencySubtitle(String code, String name);

  /// No description provided for @settingsCurrencyPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a currency'**
  String get settingsCurrencyPickerTitle;

  /// No description provided for @settingsCurrencySearch.
  ///
  /// In en, this message translates to:
  /// **'Search currencies'**
  String get settingsCurrencySearch;

  /// No description provided for @settingsCurrencyNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No currency matches \"{query}\".'**
  String settingsCurrencyNoMatch(String query);

  /// No description provided for @settingsCurrencySelected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get settingsCurrencySelected;

  /// No description provided for @settingsCurrencySaved.
  ///
  /// In en, this message translates to:
  /// **'Default currency set to {code}.'**
  String settingsCurrencySaved(String code);

  /// No description provided for @settingsAppLock.
  ///
  /// In en, this message translates to:
  /// **'App Lock'**
  String get settingsAppLock;

  /// No description provided for @settingsAppLockOn.
  ///
  /// In en, this message translates to:
  /// **'On. Exevra asks for your fingerprint, face or device PIN when it opens.'**
  String get settingsAppLockOn;

  /// No description provided for @settingsAppLockOff.
  ///
  /// In en, this message translates to:
  /// **'Ask for your fingerprint, face or device PIN when Exevra opens.'**
  String get settingsAppLockOff;

  /// No description provided for @settingsAppLockChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking it\'s you…'**
  String get settingsAppLockChecking;

  /// No description provided for @settingsAppLockTurnedOn.
  ///
  /// In en, this message translates to:
  /// **'App Lock is on.'**
  String get settingsAppLockTurnedOn;

  /// No description provided for @settingsAppLockTurnedOff.
  ///
  /// In en, this message translates to:
  /// **'App Lock is off.'**
  String get settingsAppLockTurnedOff;

  /// No description provided for @settingsHaptics.
  ///
  /// In en, this message translates to:
  /// **'Vibration feedback'**
  String get settingsHaptics;

  /// No description provided for @settingsHapticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A light vibration when you tap buttons and switches.'**
  String get settingsHapticsSubtitle;

  /// No description provided for @settingsAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI assistant'**
  String get settingsAssistant;

  /// No description provided for @settingsAssistantOn.
  ///
  /// In en, this message translates to:
  /// **'On. The assistant can use a summary of your spending to answer your questions.'**
  String get settingsAssistantOn;

  /// No description provided for @settingsAssistantOff.
  ///
  /// In en, this message translates to:
  /// **'Off. Turn it on to ask questions about your spending.'**
  String get settingsAssistantOff;

  /// A setting failed to save. {reason} is the friendly error.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t save that setting. {reason}'**
  String settingsSaveFailed(String reason);

  /// No description provided for @settingsAccountSection.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountSection;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @settingsSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get settingsSignOutTitle;

  /// No description provided for @settingsSignOutMessage.
  ///
  /// In en, this message translates to:
  /// **'Your data stays in your account. To come back, sign in again with your email and password or Google. App Lock is turned off on this device.'**
  String get settingsSignOutMessage;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsDeleteAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and personal data.'**
  String get settingsDeleteAccountSubtitle;

  /// No description provided for @settingsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get settingsDeleteTitle;

  /// No description provided for @settingsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your profile, your personal expenses, your settings and your AI assistant history.\n\nExpenses you added to shared groups stay with those groups so the other members\' balances remain correct; they will show as \"Former member\". If you are a group admin, the longest-standing member becomes admin; groups with no other members are deleted. Payments still waiting for confirmation are cancelled.\n\nThis can\'t be undone.'**
  String get settingsDeleteMessage;

  /// No description provided for @settingsDeleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account…'**
  String get settingsDeleting;

  /// No description provided for @settingsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Your account was deleted.'**
  String get settingsDeleted;

  /// No description provided for @settingsReauthTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you'**
  String get settingsReauthTitle;

  /// No description provided for @settingsReauthPassword.
  ///
  /// In en, this message translates to:
  /// **'For your security, enter your password to delete your account.'**
  String get settingsReauthPassword;

  /// No description provided for @settingsReauthProvider.
  ///
  /// In en, this message translates to:
  /// **'For your security, sign in with {provider} again to delete your account.'**
  String settingsReauthProvider(String provider);

  /// No description provided for @settingsReauthContinueWith.
  ///
  /// In en, this message translates to:
  /// **'Continue with {provider}'**
  String settingsReauthContinueWith(String provider);

  /// No description provided for @settingsReauthContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get settingsReauthContinue;

  /// No description provided for @settingsReauthChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking it\'s you…'**
  String get settingsReauthChecking;

  /// No description provided for @inviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Group invitation'**
  String get inviteTitle;

  /// No description provided for @inviteClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get inviteClose;

  /// No description provided for @inviteLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking the invitation…'**
  String get inviteLoading;

  /// No description provided for @inviteProblemTitle.
  ///
  /// In en, this message translates to:
  /// **'This invitation can\'t be opened'**
  String get inviteProblemTitle;

  /// No description provided for @inviteSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed in as {email}.'**
  String inviteSignedInAs(String email);

  /// No description provided for @inviteWrongEmailHelp.
  ///
  /// In en, this message translates to:
  /// **'Sign out and sign in with the address the invitation was sent to, or ask the group admin to invite {email} instead.'**
  String inviteWrongEmailHelp(String email);

  /// No description provided for @inviteSwitchAccount.
  ///
  /// In en, this message translates to:
  /// **'Sign out and use the invited address'**
  String get inviteSwitchAccount;

  /// No description provided for @inviteBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get inviteBack;

  /// No description provided for @inviteGoHome.
  ///
  /// In en, this message translates to:
  /// **'Go to Home'**
  String get inviteGoHome;

  /// No description provided for @inviteSignedOutTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve been invited to a group'**
  String get inviteSignedOutTitle;

  /// No description provided for @inviteSignedOutMessage.
  ///
  /// In en, this message translates to:
  /// **'Sign in or create an account with the invited email address to see the invitation and join.'**
  String get inviteSignedOutMessage;

  /// No description provided for @inviteSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see it'**
  String get inviteSignIn;

  /// No description provided for @inviteCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get inviteCreateAccount;

  /// No description provided for @invitePendingTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re invited to {group}'**
  String invitePendingTitle(String group);

  /// No description provided for @invitePendingMessage.
  ///
  /// In en, this message translates to:
  /// **'{inviter} invited you to share expenses in this group.'**
  String invitePendingMessage(String inviter);

  /// Used when the inviter has no name.
  ///
  /// In en, this message translates to:
  /// **'A group admin'**
  String get inviteSomeone;

  /// No description provided for @inviteAcceptedTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re already in {group}'**
  String inviteAcceptedTitle(String group);

  /// No description provided for @inviteAcceptedMessage.
  ///
  /// In en, this message translates to:
  /// **'You are already a member of this group.'**
  String get inviteAcceptedMessage;

  /// No description provided for @inviteExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'This invitation has expired'**
  String get inviteExpiredTitle;

  /// No description provided for @inviteExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Ask someone in the group to send you a new invitation.'**
  String get inviteExpiredMessage;

  /// No description provided for @inviteCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'This invitation is no longer active'**
  String get inviteCancelledTitle;

  /// No description provided for @inviteCancelledMessage.
  ///
  /// In en, this message translates to:
  /// **'It was cancelled or declined. Ask the group admin for a new one if you still want to join.'**
  String get inviteCancelledMessage;

  /// No description provided for @inviteGroupLabel.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get inviteGroupLabel;

  /// No description provided for @inviteInvitedBy.
  ///
  /// In en, this message translates to:
  /// **'Invited by'**
  String get inviteInvitedBy;

  /// No description provided for @inviteRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Your role'**
  String get inviteRoleLabel;

  /// No description provided for @inviteValidUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid until'**
  String get inviteValidUntil;

  /// No description provided for @inviteExpiredOn.
  ///
  /// In en, this message translates to:
  /// **'Expired on'**
  String get inviteExpiredOn;

  /// No description provided for @inviteAccept.
  ///
  /// In en, this message translates to:
  /// **'Join group'**
  String get inviteAccept;

  /// No description provided for @inviteDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get inviteDecline;

  /// No description provided for @inviteDeclineTitle.
  ///
  /// In en, this message translates to:
  /// **'Decline this invitation?'**
  String get inviteDeclineTitle;

  /// No description provided for @inviteDeclineMessage.
  ///
  /// In en, this message translates to:
  /// **'You won\'t join {group}. Someone in the group can invite you again later.'**
  String inviteDeclineMessage(String group);

  /// No description provided for @inviteDeclined.
  ///
  /// In en, this message translates to:
  /// **'Invitation declined.'**
  String get inviteDeclined;

  /// No description provided for @inviteJoined.
  ///
  /// In en, this message translates to:
  /// **'You joined {group}.'**
  String inviteJoined(String group);

  /// No description provided for @inviteOpenGroup.
  ///
  /// In en, this message translates to:
  /// **'Open the group'**
  String get inviteOpenGroup;

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
