import 'app_failure.dart';

/// Short, plain-English copy for every [AppFailure].
///
/// This is the only place user-facing error text is written; it moves to
/// the ARB files when localization lands. Raw exception strings are never
/// shown to users.
String friendlyMessage(AppFailure failure) {
  final key = failure.key;
  if (key != null) {
    final specific = _byKey[key];
    if (specific != null) return specific;
  }
  return switch (failure) {
    NetworkFailure() =>
      "Couldn't reach Exevra. Check your connection and try again.",
    OfflineFailure() => "You're offline. Check your connection and try again.",
    TimeoutFailure() => 'This is taking too long. Please try again.',
    PermissionDeniedFailure() => "You don't have permission to do that.",
    NotFoundFailure() => "We couldn't find that. It may have been removed.",
    ValidationFailure() => 'Please check the details and try again.',
    ConflictFailure() => 'That already exists.',
    RateLimitedFailure() =>
      'Too many attempts. Please wait a moment and try again.',
    QuotaExceededFailure() =>
      "You've reached today's limit. Please try again tomorrow.",
    SessionExpiredFailure() =>
      'Your session has expired. Please sign in again.',
    EmailNotConfirmedFailure() =>
      'Please confirm your email address first. Check your inbox.',
    InvalidCredentialsFailure() => 'Incorrect email or password.',
    AccountExistsFailure() =>
      'An account with this email already exists. Try signing in.',
    WeakPasswordFailure() =>
      'Choose a stronger password: at least 8 characters, with upper and '
          'lower case letters and a number.',
    CodeExpiredFailure() =>
      'That code has expired or is not valid. Request a new one.',
    BusinessFailure() => "We couldn't complete that. Please try again.",
    UnknownFailure() => 'Something went wrong. Please try again.',
  };
}

/// Copy for a message [key] (for checks made before calling the server).
String friendlyMessageForKey(String key) =>
    friendlyMessage(AppFailure.business(key));

const Map<String, String> _byKey = {
  // Invitations
  'invite_expired':
      'This invitation has expired. Ask the group admin for a new one.',
  'invite_already_used': 'This invitation has already been used.',
  'invite_declined': 'This invitation was declined.',
  'invite_revoked': 'This invitation was cancelled by the group admin.',
  'invite_not_found': "We couldn't find that invitation.",
  'invite_not_pending': 'This invitation is no longer pending.',
  'invite_email_mismatch':
      'This invitation was sent to a different email address. Sign in with '
      'that address to accept it.',
  'email_not_confirmed': 'Please confirm your email address first.',
  // Groups and members
  'already_member': "You're already a member of this group.",
  'banned': "You can't join this group. Ask the admin to invite you again.",
  'not_group_admin': 'Only the group admin can do that.',
  'not_group_member': "You're not a member of this group.",
  'group_not_found': "We couldn't find that group.",
  'member_not_found': "We couldn't find that member.",
  'profile_not_found': "We couldn't load your profile. Please try again.",
  'member_pending': 'This member is still waiting for approval.',
  'member_not_pending': 'This member has already been approved.',
  'cannot_remove_self': "You can't remove yourself. Leave the group instead.",
  'cannot_change_own_role': "You can't change your own role.",
  'outstanding_balance':
      "Settle up first: there's still an open balance or a payment waiting "
      'for confirmation.',
  'group_has_members':
      'Remove the other members or make someone else admin before deleting '
      'this group.',
  'membership_rpc_only': "You don't have permission to do that.",
  'invalid_code': "That invite code isn't valid. Check it and try again.",
  'group_not_ready': 'Your groups are still loading. Try again in a moment.',
  'group_unconfirmed':
      "We couldn't confirm the group was created. Check your groups before "
      'trying again.',
  'code_expired':
      'That invite code has expired. Ask the group admin for a new one.',
  // Input
  'invalid_group_name': 'Group names must be 1 to 60 characters.',
  'invalid_currency': "That currency isn't supported.",
  'invalid_role': 'Choose member or viewer.',
  'invalid_email': 'Enter a valid email address.',
  'invalid_target': 'Choose another member.',
  'invalid_timezone': "Your device's time zone isn't recognised.",
  'invalid_amount': 'Enter an amount greater than zero.',
  'invalid_note': 'Notes can be at most 200 characters.',
  'invalid_reason': 'The reason can be at most 200 characters.',
  'invalid_scope': "That view isn't available.",
  'invalid_timeframe': "That time range isn't available.",
  'invalid_group': "That group isn't available.",
  'same_password': 'Your new password must be different from the old one.',
  'too_long': 'That message is too long. Please shorten it.',
  // Amount entry (money_parser.dart)
  'amount_required': 'Enter an amount.',
  'amount_invalid': 'Enter a valid amount, for example 1250.50.',
  'amount_not_positive': 'The amount must be more than zero.',
  'amount_too_many_decimals': 'Too many decimal places for this currency.',
  'amount_too_large': 'That amount is too large.',
  // Expenses and profile
  'invalid_title': 'Titles must be 1 to 120 characters.',
  'invalid_category': 'Choose a category from the list.',
  'invalid_display_name': 'Names must be 1 to 60 characters.',
  'invalid_avatar_url': 'Use an https:// image link.',
  'currency_mismatch': "Group expenses must use the group's currency.",
  'expense_group_immutable':
      "An expense can't be moved between personal and a group.",
  'no_split_members': 'This group has no members who can share expenses.',
  'expense_not_saved_yet': 'This expense is still saving. Try again shortly.',
  'expense_unconfirmed':
      "We couldn't confirm this change was saved. Check your expenses before "
      'trying again.',
  'viewer_cannot_add': 'Viewers can see group expenses but cannot add them.',
  // Settlements
  'settlement_exceeds_debt': "That's more than you currently owe this person.",
  'settlement_not_pending': 'This payment is no longer pending.',
  'settlement_already_voided': 'This payment has already been voided.',
  'settlement_not_found': "We couldn't find that payment.",
  'not_settlement_payee':
      'Only the person receiving the payment can confirm it.',
  'not_settlement_party':
      'Only the payer, the receiver or the group admin can void this payment.',
  'settlement_unconfirmed':
      "We couldn't confirm this payment change was saved. Check the payments "
      'before trying again.',
  'settlement_in_progress':
      'This payment is still being saved. Wait a moment, then try again.',
  // Limits and services
  'rate_limited': 'Too many attempts. Please wait a moment and try again.',
  'quota_exceeded': "You've reached today's limit. Please try again tomorrow.",
  'consent_required': 'Turn on the AI assistant in Settings to use it.',
  'reauth_required':
      'For your security, please sign in again and then try once more.',
  'deletion_failed':
      "We couldn't delete your account and nothing was removed. Please try "
      'again.',
  'unavailable':
      'This service is temporarily unavailable. Please try again later.',
  'google_unavailable': "Google sign-in isn't available in this version.",
  'google_failed': "Google sign-in didn't work. Please try again.",
  'apple_failed': "Sign in with Apple didn't work. Please try again.",
  'apple_reauth_cancelled':
      'Confirm with Apple to delete your account. Nothing was deleted.',
  'terms_required': 'Please accept the Terms of Service and Privacy Policy.',
  'password_mismatch': "The passwords don't match.",
  // App Lock (local_auth)
  'lock_cancelled': 'App Lock was not changed.',
  'lock_failed': "We couldn't confirm it's you. Please try again.",
  'lock_no_credentials':
      'Set up a screen lock (PIN, pattern, password or biometrics) in your '
      'device settings to use App Lock.',
  'lock_temporary_lockout': 'Too many attempts. Wait a moment, then try again.',
  'lock_biometric_lockout':
      'Biometrics are locked after too many attempts. Unlock with your '
      'device PIN, pattern or password.',
  'lock_hardware_busy':
      'The fingerprint or face sensor is busy. Try again, or use your '
      'device PIN.',
  'lock_in_progress': 'Finish the current unlock request first.',
  'lock_ui_unavailable':
      "The unlock prompt couldn't be shown. Please try again.",
  'lock_signed_out': 'Sign in to change App Lock.',
  'signup_disabled': "New sign-ups aren't available right now.",
};
