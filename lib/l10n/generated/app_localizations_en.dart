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
  String get expensesTitle => 'Expenses';

  @override
  String get expensesRefresh => 'Refresh expenses';

  @override
  String get expensesAdd => 'Add expense';

  @override
  String get expensesAddFirst => 'Add your first expense';

  @override
  String get expensesEmptyTitle => 'No expenses yet';

  @override
  String get expensesEmptyMessage =>
      'Add what you spend to see where your money goes.';

  @override
  String expensesEmptyGroupMessage(String group) {
    return 'Nobody has added an expense to $group yet. Add the first one to start splitting costs.';
  }

  @override
  String expensesEmptyViewerMessage(String group) {
    return 'Nobody has added an expense to $group yet. You can still add your own personal expenses.';
  }

  @override
  String get expensesEmptyFilteredTitle => 'No matching expenses';

  @override
  String get expensesEmptyFilteredMessage =>
      'Try a different search, category or date range.';

  @override
  String get expensesClearFilters => 'Clear filters';

  @override
  String get expensesLoadErrorTitle => 'Couldn\'t load your expenses';

  @override
  String expensesResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count expenses found',
      one: '1 expense found',
    );
    return '$_temp0';
  }

  @override
  String get expensesOnlyPayerCanEdit =>
      'Only the person who paid can edit this expense.';

  @override
  String get expensesPersonalTag => 'Personal';

  @override
  String get expensesPaidByYou => 'You paid';

  @override
  String expensesPaidBy(String name) {
    return '$name paid';
  }

  @override
  String get expensesPaidByFormer => 'Paid by a former member';

  @override
  String get expensesPaidByMember => 'Paid by a group member';

  @override
  String expensesActionsTooltip(String title) {
    return 'Actions for $title';
  }

  @override
  String get expensesEdit => 'Edit';

  @override
  String get expensesSearchLabel => 'Search expenses';

  @override
  String get expensesSearchHint => 'Search by title';

  @override
  String get expensesClearSearch => 'Clear search';

  @override
  String get expensesTypeAll => 'All';

  @override
  String get expensesTypePersonal => 'Personal';

  @override
  String get expensesTypeGroup => 'Group';

  @override
  String get expensesDateFilterTooltip => 'Filter by date';

  @override
  String get expensesDateFilterTitle => 'Show expenses from';

  @override
  String get expensesDateAny => 'Any date';

  @override
  String get expensesDateLast7Days => 'Last 7 days';

  @override
  String get expensesDateThisMonth => 'This month';

  @override
  String get expensesDateLastMonth => 'Last month';

  @override
  String get expensesDateLast3Months => 'Last 3 months';

  @override
  String get expensesDateThisYear => 'This year';

  @override
  String get expensesAllCategories => 'All categories';

  @override
  String get expensesCategoryFood => 'Food';

  @override
  String get expensesCategoryTransport => 'Transport';

  @override
  String get expensesCategoryHousing => 'Housing';

  @override
  String get expensesCategoryEntertainment => 'Entertainment';

  @override
  String get expensesCategoryHealthcare => 'Healthcare';

  @override
  String get expensesCategoryUtilities => 'Utilities';

  @override
  String get expensesCategoryShopping => 'Shopping';

  @override
  String get expensesCategoryPersonal => 'Personal';

  @override
  String get expensesCategoryEducation => 'Education';

  @override
  String get expensesCategoryOther => 'Other';

  @override
  String get expensesLockedTitle => 'This expense is locked';

  @override
  String get expensesDeleteTitle => 'Delete expense?';

  @override
  String expensesDeleteMessage(String title, String amount) {
    return '\"$title\" ($amount) will be deleted.';
  }

  @override
  String expensesDeleteGroupMessage(String title, String amount) {
    return '\"$title\" ($amount) will be deleted for everyone in the group, and the balances will change.';
  }

  @override
  String get expensesDeleteNoUndo =>
      'You didn\'t pay for it, so this can\'t be undone.';

  @override
  String expensesDeleted(String title) {
    return 'Deleted \"$title\"';
  }

  @override
  String expensesRestored(String title) {
    return 'Restored \"$title\"';
  }

  @override
  String get expensesAddTitle => 'Add expense';

  @override
  String get expensesEditTitle => 'Edit expense';

  @override
  String get expensesDiscardEditMessage =>
      'Your changes to this expense will be lost.';

  @override
  String get expensesDiscardNewMessage => 'This expense won\'t be saved.';

  @override
  String get expensesAmountLabel => 'Amount';

  @override
  String get expensesCurrencyLabel => 'Currency';

  @override
  String expensesGroupCurrencyTooltip(String currency) {
    return 'Group expenses use the group currency, $currency';
  }

  @override
  String get expensesLockedStillEditable =>
      'You can still change the title, category, date and note.';

  @override
  String expensesCurrencyChanged(String currency) {
    return 'The amount is now in $currency. Check it before saving.';
  }

  @override
  String get expensesTitleLabel => 'Title';

  @override
  String get expensesTitleHint => 'e.g. Weekly groceries';

  @override
  String get expensesTitleRequired => 'Enter a title.';

  @override
  String get expensesScopeLabel => 'Personal or group expense';

  @override
  String get expensesScopePersonal => 'Personal';

  @override
  String get expensesScopeGroup => 'Group';

  @override
  String get expensesScopeUnavailable => 'Not available for this expense';

  @override
  String get expensesNoGroupHint =>
      'To share costs, create or join a group in Profile.';

  @override
  String expensesGroupScopeCaption(String group, String currency) {
    return 'Shared with everyone in $group, in $currency.';
  }

  @override
  String get expensesCategoryLabel => 'Category';

  @override
  String get expensesChangeDate => 'Change date';

  @override
  String get expensesChangeTime => 'Change time';

  @override
  String get expensesNoteLabel => 'Note (optional)';

  @override
  String get expensesNoteHint => 'Add a description or location';

  @override
  String get expensesClearNote => 'Clear note';

  @override
  String get expensesSave => 'Save expense';

  @override
  String get expensesSaveChanges => 'Save changes';

  @override
  String expensesMovedToGroup(String title, String group) {
    return 'Moved \"$title\" to $group';
  }

  @override
  String expensesMovedToPersonal(String title) {
    return 'Moved \"$title\" to your personal expenses';
  }

  @override
  String expensesMovedNotSaved(String title, String reason) {
    return 'Moved \"$title\", but your other changes weren\'t saved. $reason';
  }

  @override
  String expensesMoveUndone(String title) {
    return '\"$title\" is back as it was';
  }

  @override
  String get groupsTitle => 'Groups';

  @override
  String groupsMyGroups(int count) {
    return 'My groups ($count)';
  }

  @override
  String get groupsCreateTooltip => 'Create a group';

  @override
  String get groupsJoinTooltip => 'Join with a code';

  @override
  String get groupsPersonalScope => 'Personal (no group)';

  @override
  String groupsPendingChip(String name) {
    return '$name (waiting for approval)';
  }

  @override
  String groupsPendingChipLabel(String name) {
    return '$name, waiting for approval. Opens once the admin approves you.';
  }

  @override
  String get groupsPendingNote =>
      'Groups waiting for approval open once their admin approves you.';

  @override
  String get groupsNoGroupsTitle => 'Share costs with a group';

  @override
  String get groupsNoGroupsMessage =>
      'Create a group for flatmates, a trip or a team, or join one with an invite code.';

  @override
  String groupsScopeSwitched(String name) {
    return 'Showing expenses from $name';
  }

  @override
  String get groupsScopePersonal => 'Showing your personal expenses';

  @override
  String get groupsCreateTitle => 'Create a group';

  @override
  String get groupsNameLabel => 'Group name';

  @override
  String get groupsNameHint => 'e.g. Flatmates';

  @override
  String get groupsCurrencyLabel => 'Group currency';

  @override
  String get groupsCurrencyHelper =>
      'Every group expense uses it. It can\'t be changed later.';

  @override
  String get groupsCreateAction => 'Create';

  @override
  String groupsCreated(String name) {
    return '\"$name\" created. It is now your active group.';
  }

  @override
  String groupsCreatedNotOpened(String name) {
    return '\"$name\" was created, but we couldn\'t open it yet. Refresh your groups to see it.';
  }

  @override
  String get groupsJoinTitle => 'Join with a code';

  @override
  String get groupsInviteCodeLabel => 'Invite code';

  @override
  String get groupsJoinHelper => 'The group admin approves new members.';

  @override
  String get groupsJoinAction => 'Send request';

  @override
  String groupsJoinRequested(String group) {
    return 'Request sent to $group. You can open the group once an admin approves you.';
  }

  @override
  String get groupsInviteTitle => 'Invite by email';

  @override
  String groupsInviteIntro(String group) {
    return 'We email an invitation to $group. The link only works for this address.';
  }

  @override
  String get groupsInviteEmailLabel => 'Email address';

  @override
  String get groupsInviteRoleLabel => 'Role';

  @override
  String get groupsRoleMemberLong => 'Member (adds and shares expenses)';

  @override
  String get groupsRoleViewerLong => 'Viewer (read only)';

  @override
  String get groupsInviteSend => 'Send invitation';

  @override
  String groupsInviteEmailSent(String email) {
    return 'Email sent to $email.';
  }

  @override
  String groupsInviteNotEmailed(String email) {
    return 'The invitation for $email was created, but we couldn\'t email it. Ask them to join with the invite code instead.';
  }

  @override
  String get groupsInviteShareTitle => 'Couldn\'t send the email';

  @override
  String groupsInviteShareMessage(String email) {
    return 'Share this link instead. It only works for $email and expires in 7 days.';
  }

  @override
  String get groupsInviteLinkCopied => 'Invite link copied.';

  @override
  String get groupsCopyLink => 'Copy link';

  @override
  String groupsInviteShareText(String link) {
    return 'You\'re invited to a group on Exevra: $link';
  }

  @override
  String get groupsInviteShareSubject => 'Exevra group invitation';

  @override
  String get groupsShareFallbackCopied =>
      'Couldn\'t open the share sheet, so the link was copied.';

  @override
  String get groupsShare => 'Share';

  @override
  String groupsInviteCodeShareText(String group, String code) {
    return 'Join my group \"$group\" on Exevra with the invite code $code. The admin approves new members.';
  }

  @override
  String groupsInviteCodeShareSubject(String group) {
    return 'Join $group on Exevra';
  }

  @override
  String get groupsInviteCodeCopied => 'Invite code copied.';

  @override
  String groupsSummary(String currency, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Currency $currency · $count members',
      one: 'Currency $currency · 1 member',
    );
    return '$_temp0';
  }

  @override
  String get groupsViewerNote =>
      'You can see this group but not add expenses. Ask the admin to make you a member.';

  @override
  String get groupsInviteByEmail => 'Invite by email';

  @override
  String get groupsNewCode => 'New code';

  @override
  String get groupsNewCodeTitle => 'Issue a new invite code?';

  @override
  String get groupsNewCodeMessage =>
      'The current code stops working. People who have it can no longer ask to join.';

  @override
  String groupsNewCodeReady(String code) {
    return 'New invite code: $code';
  }

  @override
  String get groupsNoInviteCode =>
      'No invite code yet. Tap New code to create one.';

  @override
  String get groupsCopyCodeTooltip => 'Copy invite code';

  @override
  String get groupsInviteCodeApproval =>
      'People who join with the code wait for your approval.';

  @override
  String groupsInviteCodeExpires(String date) {
    return 'Expires $date. People who join with it wait for your approval.';
  }

  @override
  String groupsPendingInvitations(int count) {
    return 'Pending invitations ($count)';
  }

  @override
  String groupsWaitingForApproval(int count) {
    return 'Waiting for approval ($count)';
  }

  @override
  String groupsMembers(int count) {
    return 'Members ($count)';
  }

  @override
  String get groupsLeave => 'Leave group';

  @override
  String groupsLeaveTitle(String group) {
    return 'Leave $group?';
  }

  @override
  String groupsLeaveLastMessage(String group) {
    return 'You\'re the only member, so leaving deletes $group and all its expenses and payments.';
  }

  @override
  String groupsLeaveAdminMessage(String name) {
    return 'You\'re the admin. $name, the longest-standing member, becomes the admin when you leave. You can choose someone else first with \"Make admin\". You need to be settled up to leave.';
  }

  @override
  String groupsLeaveMessage(String group) {
    return 'You\'ll no longer see $group\'s expenses and balances. Your past expenses stay in the group. You need to be settled up to leave.';
  }

  @override
  String get groupsDelete => 'Delete group';

  @override
  String groupsDeleteTitle(String group) {
    return 'Delete $group?';
  }

  @override
  String get groupsDeleteMessage =>
      'This permanently deletes the group with all its expenses and payments. It can\'t be undone.';

  @override
  String get groupsDeleteHasMembers =>
      'Remove the other members or make someone else admin before deleting this group.';

  @override
  String groupsInvitationStatus(String role, String date) {
    return '$role · expires $date';
  }

  @override
  String get groupsRevokeTooltip => 'Revoke invitation';

  @override
  String get groupsRevokeTitle => 'Revoke this invitation?';

  @override
  String groupsRevokeMessage(String email) {
    return 'The link sent to $email stops working.';
  }

  @override
  String get groupsRevokeAction => 'Revoke';

  @override
  String groupsRevoked(String email) {
    return 'Invitation for $email revoked.';
  }

  @override
  String get groupsRequestPending => 'Wants to join';

  @override
  String groupsApproveTooltip(String name) {
    return 'Approve $name';
  }

  @override
  String get groupsApproveAsMember => 'Approve as member';

  @override
  String get groupsApproveAsViewer => 'Approve as viewer (read only)';

  @override
  String groupsApprovedMember(String name) {
    return '$name can now add expenses.';
  }

  @override
  String groupsApprovedViewer(String name) {
    return '$name can now see the group.';
  }

  @override
  String groupsDenyTooltip(String name) {
    return 'Deny $name';
  }

  @override
  String groupsDenyTitle(String name) {
    return 'Deny $name?';
  }

  @override
  String get groupsDenyMessage =>
      'They won\'t join the group and can\'t ask again with this code. You can still invite them by email later.';

  @override
  String get groupsDenyAction => 'Deny';

  @override
  String groupsMemberYou(String name) {
    return '$name (you)';
  }

  @override
  String groupsManageTooltip(String name) {
    return 'Manage $name';
  }

  @override
  String get groupsMakeMember => 'Make member (can add expenses)';

  @override
  String get groupsMakeViewer => 'Make viewer (read only)';

  @override
  String groupsMakeViewerTitle(String name) {
    return 'Make $name a viewer?';
  }

  @override
  String groupsMakeViewerMessage(String name) {
    return '$name will only be able to see the group, not add expenses. You can make them a member again later.';
  }

  @override
  String get groupsMakeViewerAction => 'Make viewer';

  @override
  String groupsNowViewer(String name) {
    return '$name can now only view the group.';
  }

  @override
  String get groupsMakeAdmin => 'Make admin';

  @override
  String groupsMakeAdminTitle(String name) {
    return 'Make $name the admin?';
  }

  @override
  String get groupsMakeAdminMessage =>
      'A group has one admin. You become a member, and your pending email invitations are cancelled.';

  @override
  String groupsNowAdmin(String name) {
    return '$name is now the admin.';
  }

  @override
  String get groupsRemoveMember => 'Remove from group';

  @override
  String groupsRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String groupsRemoveMessage(String group) {
    return 'They lose access to $group and can\'t rejoin with the invite code. Their past expenses stay in the group.';
  }

  @override
  String get groupsRemoveAction => 'Remove';

  @override
  String groupsRemoved(String name) {
    return '$name was removed from the group.';
  }

  @override
  String groupsNotSettledTitle(String name) {
    return '$name is not settled up';
  }

  @override
  String get groupsNotSettledMessage =>
      'They still have an open balance or a payment waiting for confirmation. If you remove them anyway, their balance stays in the group\'s balances but can\'t be settled in the app.';

  @override
  String get groupsRemoveAnyway => 'Remove anyway';

  @override
  String get settleTitle => 'Balances & payments';

  @override
  String get settleRecordPayment => 'Record payment';

  @override
  String settleBalancesHeader(String currency) {
    return 'Balances ($currency)';
  }

  @override
  String get settleSuggestionsHeader => 'Suggested payments';

  @override
  String get settlePaymentsHeader => 'Payments';

  @override
  String get settleEveryoneSettled => 'Everyone is settled up.';

  @override
  String get settleNoPayments => 'No payments recorded yet.';

  @override
  String get settleShowOlder => 'Show older payments';

  @override
  String get settleYou => 'You';

  @override
  String get settleFormerMember => 'Former member';

  @override
  String settleYouOwe(String amount) {
    return 'You owe $amount';
  }

  @override
  String settleYouAreOwed(String amount) {
    return 'You get back $amount';
  }

  @override
  String get settleYouAreSettled => 'You\'re settled up';

  @override
  String settleMemberOwes(String name, String amount) {
    return '$name owes $amount';
  }

  @override
  String settleMemberIsOwed(String name, String amount) {
    return '$name gets back $amount';
  }

  @override
  String settleMemberSettled(String name) {
    return '$name is settled up';
  }

  @override
  String settleSuggestYouOwe(String name, String amount) {
    return 'You owe $name $amount';
  }

  @override
  String settleSuggestOwesYou(String name, String amount) {
    return '$name owes you $amount';
  }

  @override
  String settleSuggestOther(String from, String to, String amount) {
    return '$from owes $to $amount';
  }

  @override
  String get settlePay => 'Pay';

  @override
  String settlePayTooltip(String name, String amount) {
    return 'Record paying $name $amount';
  }

  @override
  String settlePaidRow(String from, String to) {
    return '$from paid $to';
  }

  @override
  String settlePendingFor(String name) {
    return 'Waiting for $name to confirm';
  }

  @override
  String get settlePendingForYou => 'Waiting for you to confirm';

  @override
  String settleVoidReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get settleConfirm => 'Confirm';

  @override
  String get settleVoid => 'Void';

  @override
  String get settleConfirmTitle => 'Confirm this payment?';

  @override
  String settleConfirmMessage(String amount, String name) {
    return 'Confirm only if you received $amount from $name. It then counts in the balances.';
  }

  @override
  String get settleConfirmAction => 'I received it';

  @override
  String get settleConfirmed => 'Payment confirmed.';

  @override
  String get settleNoOneToPay => 'There is no one else in this group to pay.';

  @override
  String get settleRecordTitle => 'Record a payment';

  @override
  String get settleRecordIntro =>
      'Record money you paid to a group member. It counts once they confirm they received it.';

  @override
  String get settlePaidTo => 'Paid to';

  @override
  String settleAmountLabel(String currency) {
    return 'Amount ($currency)';
  }

  @override
  String settleLimitHelper(String name, String amount) {
    return 'You owe $name up to $amount.';
  }

  @override
  String settleOverLimit(String name, String amount) {
    return 'That\'s more than you owe $name (up to $amount).';
  }

  @override
  String settleNothingOwed(String name) {
    return 'You don\'t owe $name anything right now.';
  }

  @override
  String get settleNoteLabel => 'Note (optional)';

  @override
  String get settleNoteHint => 'e.g. UPI, cash, bank transfer';

  @override
  String settleRecorded(String name) {
    return 'Payment recorded. It counts once $name confirms it.';
  }

  @override
  String get settleVoidTitle => 'Void this payment?';

  @override
  String settleVoidMessage(String from, String to, String amount) {
    return '$from paid $to $amount. A voided payment no longer counts in the balances.';
  }

  @override
  String get settleVoidReasonLabel => 'Reason (optional)';

  @override
  String get settleVoidReasonHint => 'e.g. Entered twice';

  @override
  String get settleKeep => 'Keep it';

  @override
  String get settleVoidAction => 'Void payment';

  @override
  String get settleVoided => 'Payment voided.';
}
