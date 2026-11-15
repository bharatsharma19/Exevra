import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/utils/date_helpers.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/money_parser.dart';
import '../../../core/utils/validators.dart';
import '../../../data/repositories/group_repository.dart';
import '../../../models/balance.dart';
import '../../../models/currency_info.dart';
import '../../../models/group.dart';
import '../../../models/invitation.dart';
import '../../../models/money.dart';
import '../../../models/profile.dart';
import '../../../models/settlement.dart';
import '../../../providers/app_lock_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/failure_reporter.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../shared/failure_retry.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _avatarUrlController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _inviteCodeController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _avatarUrlController.dispose();
    _groupNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  void _showEditProfileDialog() {
    final profile = ref.read(userProfileProvider);
    if (profile == null) return;
    _nameController.text = profile.displayName;
    _avatarUrlController.text = profile.avatarUrl ?? '';
    String? fieldError;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit Profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _avatarUrlController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Profile Image URL (optional)',
                      prefixIcon: const Icon(Icons.link_rounded),
                      hintText: 'https://...',
                      errorText: fieldError,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final url = _avatarUrlController.text.trim();
                  final update = ProfileUpdate(
                    displayName: _nameController.text,
                    avatarUrl: url.isEmpty ? null : url,
                  );
                  final invalid = update.validate();
                  if (invalid != null) {
                    setDialogState(
                      () => fieldError = friendlyMessageForKey(invalid),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop();
                  final failure = await ref
                      .read(profileProvider.notifier)
                      .updateProfile(update);
                  if (failure == null && mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateGroupDialog() {
    _groupNameController.clear();
    var currency = ref.read(preferredCurrencyProvider);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Create Household / Group'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _groupNameController,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    hintText: 'e.g. Mercer Household',
                    prefixIcon: Icon(Icons.group_add_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                // A group's currency is fixed once it is created.
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(
                    labelText: 'Group currency',
                    prefixIcon: Icon(Icons.currency_exchange_rounded),
                  ),
                  items: [
                    for (final c in CurrencyInfo.all)
                      DropdownMenuItem(
                        value: c.code,
                        child: Text('${c.code} (${c.symbol})'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => currency = value);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = _groupNameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(ctx).pop();
                  await ref
                      .read(groupsProvider.notifier)
                      .createGroup(name, currency: currency);
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showJoinGroupDialog() {
    _inviteCodeController.clear();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Join via Invite Code'),
          content: TextField(
            controller: _inviteCodeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invite Code',
              hintText: 'XXXX-XXXX-XXXX-XXXX',
              prefixIcon: Icon(Icons.vpn_key_rounded),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final code = _inviteCodeController.text.trim();
                if (code.isEmpty) return;
                Navigator.of(ctx).pop();
                final (request, _) = await ref
                    .read(groupsProvider.notifier)
                    .joinByCode(code);
                if (request != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Request sent to ${request.groupName}. You can open '
                        'the group once an admin approves you.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Join Group'),
            ),
          ],
        ),
      ),
    );
  }

  void _showInviteByEmailDialog() {
    final group = ref.read(activeGroupProvider);
    if (group == null || !group.isAdmin) return;
    final emailController = TextEditingController();
    var selectedRole = GroupRole.member;
    var isSending = false;
    String? fieldError;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.mail_outline_rounded),
                SizedBox(width: 8),
                Text('Invite by Email'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'We email an invitation link that only works for this '
                    'address.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: 'Recipient Email',
                      hintText: 'member@example.com',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      errorText: fieldError,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<GroupRole>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: GroupRole.member,
                        child: Text('Member (adds and shares expenses)'),
                      ),
                      DropdownMenuItem(
                        value: GroupRole.viewer,
                        child: Text('Viewer (read only)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedRole = val);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              isSending
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        final email = emailController.text.trim().toLowerCase();
                        final invalid = Validators.validateEmail(email);
                        if (invalid != null) {
                          setDialogState(() => fieldError = invalid);
                          return;
                        }
                        setDialogState(() {
                          isSending = true;
                          fieldError = null;
                        });

                        final (sent, failure) = await ref
                            .read(pendingInvitationsProvider(group.id).notifier)
                            .send(email, role: selectedRole);

                        if (failure != null) {
                          // Reported once by the shell; keep the dialog.
                          if (ctx.mounted) {
                            setDialogState(() => isSending = false);
                          }
                          return;
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted && sent != null) {
                          _showInvitationResult(email, sent);
                        }
                      },
                      child: const Text('Send Invitation'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  /// Reports the outcome honestly: "emailed" only when the server sent the
  /// email; otherwise the share link so the admin can send it themselves.
  void _showInvitationResult(String email, SentInvitation sent) {
    final link = sent.shareUrl;
    if (sent.sent || link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent.sent
                ? 'Invitation emailed to $email.'
                : "The invitation was created but the email couldn't be sent. "
                      'Ask the person to check the app later.',
          ),
        ),
      );
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invitation created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "We couldn't email it, so send this link to $email "
                'yourself. It only works for that email address.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              SelectableText(link, style: const TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
            ElevatedButton.icon(
              onPressed: () => _copyInviteLink(link),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy link'),
            ),
          ],
        ),
      ),
    );
  }

  void _copyInviteLink(String link) {
    AppHaptics.selection();
    unawaited(Clipboard.setData(ClipboardData(text: link)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite link copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Records a payment from the signed-in user to another member. It stays
  /// pending until the payee confirms it.
  void _showSettleUpDialog({
    String? prefilledToUserId,
    Money? prefilledAmount,
  }) {
    final group = ref.read(activeGroupProvider);
    final currentUserId = ref.read(currentUserIdProvider);
    if (group == null || currentUserId == null) return;
    final currency = group.currency;

    final otherMembers =
        (ref.read(groupMembersProvider(group.id)).value ??
                const <GroupMember>[])
            .where((m) => m.userId != currentUserId && !m.isPending)
            .toList();

    if (otherMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other members in this group to settle with.'),
        ),
      );
      return;
    }

    String selectedRecipientId =
        (prefilledToUserId != null &&
            otherMembers.any((m) => m.userId == prefilledToUserId))
        ? prefilledToUserId
        : otherMembers.first.userId;

    final amountController = TextEditingController(
      text: prefilledAmount != null && prefilledAmount.isPositive
          ? MoneyFormat.forInput(prefilledAmount)
          : '',
    );
    final notesController = TextEditingController();
    bool isSubmitting = false;
    String? amountError;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.handshake_rounded),
                SizedBox(width: 8),
                Text('Record a Payment'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Record money you paid to a group member. It counts once '
                    'they confirm they received it.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRecipientId,
                    decoration: const InputDecoration(
                      labelText: 'Paid To',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                    items: otherMembers
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.userId,
                            child: Text(m.label),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedRecipientId = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount ($currency)',
                      prefixIcon: const Icon(Icons.payments_rounded),
                      hintText: '0',
                      errorText: amountError,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: notesController,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Notes / Reference (optional)',
                      prefixIcon: Icon(Icons.note_alt_outlined),
                      hintText: 'e.g. Bank transfer, Cash, UPI',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              isSubmitting
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        final parsed = MoneyParser.parse(
                          amountController.text,
                          currency: currency,
                        );
                        if (parsed is MoneyParseError) {
                          setDialogState(
                            () => amountError = friendlyMessage(parsed.failure),
                          );
                          return;
                        }
                        final amount = (parsed as MoneyParsed).value;
                        setDialogState(() {
                          isSubmitting = true;
                          amountError = null;
                        });

                        final failure = await ref
                            .read(settlementsProvider(group.id).notifier)
                            .record(
                              toUser: selectedRecipientId,
                              amount: amount,
                              note: notesController.text,
                            );

                        if (failure != null) {
                          // Reported once by the shell; keep the dialog.
                          if (ctx.mounted) {
                            setDialogState(() => isSubmitting = false);
                          }
                          return;
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Payment recorded. It counts once the other '
                                'person confirms it.',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Record Payment'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfirmLeaveGroupDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave Group?'),
          content: const Text(
            'Are you sure you want to leave this group? You will no longer see shared expenses and balances for this group.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                final group = ref.read(activeGroupProvider);
                if (group != null) {
                  unawaited(
                    ref.read(groupsProvider.notifier).leaveGroup(group.id),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Leave Group'),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfirmDeleteGroupDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Group Permanently?'),
          content: const Text(
            'Are you sure you want to permanently delete this group? All shared expenses, debts, and member associations will be erased for everyone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                final group = ref.read(activeGroupProvider);
                if (group != null && group.isAdmin) {
                  unawaited(
                    ref.read(groupsProvider.notifier).deleteGroup(group.id),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete Group'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAppLock(bool enabled) async {
    AppHaptics.selection();
    final messenger = ScaffoldMessenger.of(context);
    final key = await ref.read(appLockProvider.notifier).setEnabled(enabled);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          key == null
              ? (enabled ? 'App Lock is on.' : 'App Lock is off.')
              : friendlyMessageForKey(key),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSignOutDialog() {
    AppHaptics.medium();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(
            'Your data stays in your account. To come back, sign in again '
            'with your email and password or Google. App Lock is turned off '
            'on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(ref.read(authControllerProvider.notifier).signOut());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    AppHaptics.heavy();
    unawaited(
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Delete your account?',
            style: TextStyle(color: AppColors.error),
          ),
          content: const SingleChildScrollView(
            child: Text(
              'This permanently deletes your profile, your personal expenses, '
              'your settings and your AI assistant history.\n\n'
              'Expenses you added to shared groups stay with those groups so '
              "the other members' balances remain correct; they will show as "
              '"Former member". If you are a group admin, the longest-standing '
              'member becomes admin; groups with no other members are '
              'deleted. Payments still waiting for confirmation are '
              'cancelled.\n\n'
              "This can't be undone.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(_deleteAccount());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );
  }

  /// Deletes the account on the server behind a blocking progress dialog.
  /// The session ends only after the server confirmed the deletion; on
  /// failure nothing changes and the reason is shown.
  Future<void> _deleteAccount() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Deleting your account...')),
              ],
            ),
          ),
        ),
      ),
    );
    final messenger = ScaffoldMessenger.of(context);
    final failure = await ref
        .read(authControllerProvider.notifier)
        .deleteAccount();
    if (navigator.mounted) navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure == null
              ? 'Your account was deleted.'
              : friendlyMessage(failure),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final appLockState = ref.watch(appLockProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final profile = ref.watch(userProfileProvider);
    final themeMode = ref.watch(themePreferenceProvider);
    final resolvedDisplayName =
        (profile != null && profile.displayName.trim().isNotEmpty)
        ? profile.displayName
        : (authState.user?.userMetadata?['full_name'] as String? ??
              authState.user?.email?.split('@').first ??
              'User');
    final groupsState = ref.watch(groupsProvider).value;
    final group = ref.watch(activeGroupProvider);
    final currentUserId = ref.watch(currentUserIdProvider);
    final isGroupAdmin = group?.isAdmin ?? false;
    final membersAsync = group == null
        ? const AsyncData<List<GroupMember>>([])
        : ref.watch(groupMembersProvider(group.id));
    final members = membersAsync.value ?? const <GroupMember>[];
    final approvedMembers = members.where((m) => !m.isPending).toList();
    final pendingMembers = members.where((m) => m.isPending).toList();
    final balances = group == null
        ? const <GroupBalance>[]
        : ref.watch(groupBalancesProvider(group.id)).value ??
              const <GroupBalance>[];
    final suggestions = group == null
        ? const <SettleSuggestion>[]
        : ref.watch(settleSuggestionsProvider(group.id)).value ??
              const <SettleSuggestion>[];
    final settlements = group == null
        ? const <Settlement>[]
        : ref.watch(settlementsProvider(group.id)).value ??
              const <Settlement>[];
    final pendingInvitations = group == null || !group.isAdmin
        ? const <GroupInvitation>[]
        : ref.watch(pendingInvitationsProvider(group.id)).value ??
              const <GroupInvitation>[];
    String nameOf(String? userId) {
      if (userId == null) return 'Former member';
      if (userId == currentUserId) return 'You';
      for (final m in members) {
        if (m.userId == userId) return m.label;
      }
      for (final b in balances) {
        if (b.userId == userId) return b.displayName;
      }
      return 'Member';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account & Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User Profile Card
            GlassCard(
              borderRadius: 24,
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primaryCyan.withValues(
                      alpha: 0.2,
                    ),
                    child:
                        (profile?.avatarUrl != null &&
                            profile!.avatarUrl!.startsWith('https://'))
                        ? ClipOval(
                            child: Image.network(
                              profile.avatarUrl!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Text(
                                    (profile.displayName.isNotEmpty)
                                        ? profile.displayName[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryCyan,
                                    ),
                                  ),
                            ),
                          )
                        : Text(
                            resolvedDisplayName.isNotEmpty
                                ? resolvedDisplayName[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryCyan,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                resolvedDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: _showEditProfileDialog,
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: AppColors.primaryCyan,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile?.email ?? authState.user?.email ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Household / Group Section
            Text(
              'Household & Shared Group',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 10),

            // 1. My Groups Multi-Group Switcher Card
            GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.domain_rounded,
                            size: 18,
                            color: AppColors.primaryCyan,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'My Groups (${groupsState?.groups.length ?? 0})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Create Group',
                            icon: const Icon(
                              Icons.add_circle_outline_rounded,
                              size: 20,
                              color: AppColors.primaryCyan,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _showCreateGroupDialog,
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip: 'Join with Code',
                            icon: const Icon(
                              Icons.group_add_rounded,
                              size: 20,
                              color: AppColors.primaryViolet,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _showJoinGroupDialog,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Personal (No Group)'),
                        selected: group == null,
                        avatar: group == null
                            ? const Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: AppColors.primaryCyan,
                              )
                            : const Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: Colors.grey,
                              ),
                        onSelected: (_) =>
                            ref.read(groupsProvider.notifier).switchScope(null),
                      ),
                      ...?groupsState?.groups.map((g) {
                        final isSelected = group?.id == g.id;
                        return ChoiceChip(
                          // A pending request opens once an admin approves.
                          label: Text(
                            g.isPending ? '${g.name} (pending)' : g.name,
                          ),
                          selected: isSelected,
                          avatar: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: AppColors.primaryCyan,
                                )
                              : const Icon(
                                  Icons.groups_rounded,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                          onSelected: g.isPending
                              ? null
                              : (_) => ref
                                    .read(groupsProvider.notifier)
                                    .switchScope(g.id),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            if (group != null) ...[
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isGroupAdmin)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryCyan.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primaryCyan),
                            ),
                            child: const Text(
                              'GROUP ADMIN',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryCyan,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (isGroupAdmin && group.displayInviteCode != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Invite Code: ',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                          SelectableText(
                            group.displayInviteCode!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              color: AppColors.primaryCyan,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.copy_rounded,
                              size: 16,
                              color: AppColors.primaryCyan,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: group.displayInviteCode!),
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Group invite code copied to clipboard!',
                                  ),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                    if (isGroupAdmin) ...[
                      const SizedBox(height: 14),

                      // Invite Actions: email invitation vs invite code
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _showInviteByEmailDialog,
                              icon: const Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 16,
                              ),
                              label: const Text('Invite Member'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                AppHaptics.selection();
                                // A fresh code also stops the old one working.
                                try {
                                  final code = await ref
                                      .read(groupRepositoryProvider)
                                      .rotateInviteCode(group.id);
                                  await ref
                                      .read(groupsProvider.notifier)
                                      .refresh();
                                  final text =
                                      'Join my group "${group.name}" on Exevra '
                                      'with the invite code ${code.display}. '
                                      'An admin approves new members.';
                                  await Clipboard.setData(
                                    ClipboardData(text: text),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'New invite code copied. The previous '
                                        'code no longer works.',
                                      ),
                                    ),
                                  );
                                } on AppFailure catch (failure) {
                                  ref
                                      .read(failureReporterProvider.notifier)
                                      .report(failure);
                                }
                              },
                              icon: const Icon(Icons.share_rounded, size: 16),
                              label: const Text('New Code'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Pending Invitations List (if any)
                    if (pendingInvitations.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Pending Invitations (${pendingInvitations.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pendingInvitations.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final inv = pendingInvitations[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isDark
                                  ? AppColors.darkCardElevated.withValues(
                                      alpha: 0.4,
                                    )
                                  : AppColors.lightCardElevated,
                              border: Border.all(
                                color: isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.mail_outline_rounded,
                                  size: 16,
                                  color: AppColors.primaryCyan,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        inv.email,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Role: ${inv.role.name} • Expires: ${DateHelpers.formatShortDate(inv.expiresAt)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? AppColors.darkTextTertiary
                                              : AppColors.lightTextTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.cancel_outlined,
                                    size: 18,
                                    color: AppColors.error,
                                  ),
                                  tooltip: 'Revoke Invite',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => ref
                                      .read(
                                        pendingInvitationsProvider(
                                          group.id,
                                        ).notifier,
                                      )
                                      .revoke(inv.id),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],

                    if (membersAsync.hasError && members.isEmpty) ...[
                      const SizedBox(height: 12),
                      FailureRetry(
                        error: membersAsync.error!,
                        compact: true,
                        onRetry: () =>
                            ref.invalidate(groupMembersProvider(group.id)),
                      ),
                    ],
                    if (members.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Group Members (${approvedMembers.length})'
                        '${pendingMembers.isEmpty ? '' : ' • ${pendingMembers.length} waiting'}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: members.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final m = members[index];
                          final isViewer = m.isPending;
                          final membersNotifier = ref.read(
                            groupMembersProvider(group.id).notifier,
                          );
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isDark
                                  ? AppColors.darkCardElevated.withValues(
                                      alpha: 0.5,
                                    )
                                  : AppColors.lightCardElevated,
                              border: Border.all(
                                color: isViewer
                                    ? AppColors.warning.withValues(alpha: 0.4)
                                    : (isDark
                                          ? AppColors.darkBorder
                                          : AppColors.lightBorder),
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.primaryCyan
                                      .withValues(alpha: 0.15),
                                  child: Text(
                                    (m.displayName?.isNotEmpty ?? false)
                                        ? m.displayName![0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryCyan,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.userId == currentUserId
                                            ? '${m.label} (you)'
                                            : m.label,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        m.isAdmin
                                            ? 'Admin'
                                            : (isViewer
                                                  ? 'Waiting for approval'
                                                  : (m.isViewer
                                                        ? 'Viewer (read only)'
                                                        : 'Member (can add)')),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: m.isAdmin
                                              ? AppColors.primaryCyan
                                              : (isViewer
                                                    ? AppColors.warning
                                                    : AppColors.primaryEmerald),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isGroupAdmin &&
                                    m.userId != currentUserId) ...[
                                  if (isViewer)
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        final failure = await membersNotifier
                                            .approve(m.userId);
                                        if (failure == null &&
                                            context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '${m.label} approved. They can now add expenses.',
                                              ),
                                              backgroundColor:
                                                  AppColors.primaryEmerald,
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        size: 14,
                                      ),
                                      label: const Text(
                                        'Approve',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AppColors.primaryEmerald,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (!isViewer && !m.isAdmin)
                                    PopupMenuButton<String>(
                                      tooltip: 'Change role',
                                      icon: const Icon(
                                        Icons.manage_accounts_outlined,
                                        size: 20,
                                      ),
                                      onSelected: (value) {
                                        unawaited(switch (value) {
                                          'member' => membersNotifier.setRole(
                                            m.userId,
                                            GroupRole.member,
                                          ),
                                          'viewer' => membersNotifier.setRole(
                                            m.userId,
                                            GroupRole.viewer,
                                          ),
                                          _ => membersNotifier.transferAdmin(
                                            m.userId,
                                          ),
                                        });
                                      },
                                      itemBuilder: (_) => [
                                        if (m.isViewer)
                                          const PopupMenuItem(
                                            value: 'member',
                                            child: Text('Make member'),
                                          )
                                        else
                                          const PopupMenuItem(
                                            value: 'viewer',
                                            child: Text('Make viewer'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'admin',
                                          child: Text(
                                            'Make admin (you stay a member)',
                                          ),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: isViewer ? 'Reject' : 'Remove',
                                    icon: const Icon(
                                      Icons.person_remove_rounded,
                                      size: 20,
                                      color: AppColors.error,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () async {
                                      final failure = await membersNotifier
                                          .remove(m.userId);
                                      if (failure == null && context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${m.label} removed from the group.',
                                            ),
                                            backgroundColor: AppColors.error,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ],

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _showConfirmLeaveGroupDialog,
                          icon: const Icon(Icons.exit_to_app_rounded, size: 16),
                          label: const Text('Leave Group'),
                        ),
                        if (isGroupAdmin) ...[
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _showConfirmDeleteGroupDialog,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 16,
                              color: AppColors.error,
                            ),
                            label: const Text(
                              'Delete Group',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Group Balances & Debt Settlements Card
              GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_rounded,
                              size: 18,
                              color: AppColors.primaryEmerald,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Group Balances & Debts',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (group.canRead)
                          TextButton.icon(
                            onPressed: () => _showSettleUpDialog(),
                            icon: const Icon(Icons.handshake_rounded, size: 16),
                            label: const Text('Settle Up'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (suggestions.isEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.primaryEmerald.withValues(
                            alpha: 0.1,
                          ),
                          border: Border.all(
                            color: AppColors.primaryEmerald.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primaryEmerald,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'All balances are settled! 🎉 No pending debts among members.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: suggestions.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final debt = suggestions[index];
                          final iOwe = debt.fromUser == currentUserId;
                          final owedToMe = debt.toUser == currentUserId;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isDark
                                  ? AppColors.darkCardElevated.withValues(
                                      alpha: 0.5,
                                    )
                                  : AppColors.lightCardElevated,
                              border: Border.all(
                                color: iOwe
                                    ? AppColors.primaryRose.withValues(
                                        alpha: 0.4,
                                      )
                                    : (owedToMe
                                          ? AppColors.primaryEmerald.withValues(
                                              alpha: 0.4,
                                            )
                                          : (isDark
                                                ? AppColors.darkBorder
                                                : AppColors.lightBorder)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  iOwe
                                      ? Icons.arrow_circle_up_rounded
                                      : (owedToMe
                                            ? Icons.arrow_circle_down_rounded
                                            : Icons.swap_horiz_rounded),
                                  color: iOwe
                                      ? AppColors.primaryRose
                                      : (owedToMe
                                            ? AppColors.primaryEmerald
                                            : AppColors.primaryCyan),
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        iOwe
                                            ? 'You owe ${nameOf(debt.toUser)}'
                                            : (owedToMe
                                                  ? '${nameOf(debt.fromUser)} owes you'
                                                  : '${nameOf(debt.fromUser)} owes ${nameOf(debt.toUser)}'),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        MoneyFormat.format(debt.amount),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: iOwe
                                              ? AppColors.primaryRose
                                              : (owedToMe
                                                    ? AppColors.primaryEmerald
                                                    : (isDark
                                                          ? AppColors
                                                                .darkTextPrimary
                                                          : AppColors
                                                                .lightTextPrimary)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (iOwe)
                                  ElevatedButton(
                                    onPressed: () => _showSettleUpDialog(
                                      prefilledToUserId: debt.toUser,
                                      prefilledAmount: debt.amount,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Pay'),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],

                    // Settlement payments: pending ones wait for the payee.
                    if (settlements.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Payments (${settlements.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...settlements.take(10).map((s) {
                        final notifier = ref.read(
                          settlementsProvider(group.id).notifier,
                        );
                        final canConfirm =
                            s.isPending && s.toUser == currentUserId;
                        final canVoid =
                            !s.isVoided &&
                            (s.fromUser == currentUserId ||
                                s.toUser == currentUserId ||
                                isGroupAdmin);
                        final status = switch (s.status) {
                          SettlementStatus.pending =>
                            'waiting for confirmation',
                          SettlementStatus.confirmed => 'confirmed',
                          SettlementStatus.voided => 'voided',
                        };
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                s.isConfirmed
                                    ? Icons.check_circle_outline_rounded
                                    : (s.isPending
                                          ? Icons.schedule_rounded
                                          : Icons.block_rounded),
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${nameOf(s.fromUser)} paid ${nameOf(s.toUser)} '
                                  '${MoneyFormat.format(s.amount)} • $status'
                                  '${s.note != null ? " • ${s.note}" : ""}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.lightTextTertiary,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (canConfirm)
                                TextButton(
                                  onPressed: () =>
                                      unawaited(notifier.confirm(s.id)),
                                  child: const Text('Confirm'),
                                ),
                              if (canVoid)
                                TextButton(
                                  onPressed: () =>
                                      unawaited(notifier.voidPayment(s.id)),
                                  child: const Text('Void'),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // App Settings Section
            Text(
              'Preferences & Environment',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 10),

            GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  // App Lock: turning it on or off needs authentication.
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(
                      Icons.fingerprint_rounded,
                      color: AppColors.primaryCyan,
                    ),
                    title: const Text(
                      'App Lock',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      appLockState.availability ==
                                  LockAvailability.unavailable &&
                              !appLockState.enabled
                          ? friendlyMessageForKey('lock_no_credentials')
                          : 'Ask for your fingerprint, face or device PIN '
                                'when opening Exevra',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: appLockState.enabled,
                    onChanged:
                        appLockState.isAuthenticating ||
                            (appLockState.availability ==
                                    LockAvailability.unavailable &&
                                !appLockState.enabled)
                        ? null
                        : (val) => unawaited(_setAppLock(val)),
                  ),
                  const Divider(height: 1),

                  // Currency Selector
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.monetization_on_outlined,
                      color: AppColors.primaryCyan,
                    ),
                    title: const Text(
                      'Default Currency',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: DropdownButton<String>(
                      value: ref.watch(preferredCurrencyProvider),
                      underline: const SizedBox(),
                      // Used for new personal expenses; groups keep their
                      // own currency.
                      onChanged: profile == null
                          ? null
                          : (val) {
                              if (val == null) return;
                              AppHaptics.selection();
                              unawaited(
                                ref
                                    .read(profileProvider.notifier)
                                    .setCurrency(val),
                              );
                            },
                      items: CurrencyInfo.all
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.code,
                              child: Text('${c.code} (${c.symbol})'),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const Divider(height: 1),

                  // Theme Mode Selector
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.dark_mode_outlined,
                      color: AppColors.primaryViolet,
                    ),
                    title: const Text(
                      'Theme Mode',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: DropdownButton<ThemePreference>(
                      value: themeMode,
                      underline: const SizedBox(),
                      onChanged: (val) {
                        if (val == null) return;
                        AppHaptics.selection();
                        unawaited(
                          ref.read(profileProvider.notifier).setThemeMode(val),
                        );
                      },
                      items: const [
                        DropdownMenuItem(
                          value: ThemePreference.system,
                          child: Text('System'),
                        ),
                        DropdownMenuItem(
                          value: ThemePreference.dark,
                          child: Text('Dark'),
                        ),
                        DropdownMenuItem(
                          value: ThemePreference.light,
                          child: Text('Light'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Haptics Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(
                      Icons.vibration_rounded,
                      color: AppColors.primaryEmerald,
                    ),
                    title: const Text(
                      'Tactile Haptic Feedback',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    value: profile?.hapticsEnabled ?? true,
                    activeThumbColor: AppColors.primaryEmerald,
                    onChanged: profile == null
                        ? null
                        : (val) {
                            AppHaptics.selection();
                            unawaited(
                              ref
                                  .read(profileProvider.notifier)
                                  .setHapticsEnabled(val),
                            );
                          },
                  ),
                  const Divider(height: 1),

                  // AI Consent Switch
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(
                      Icons.psychology_outlined,
                      color: AppColors.primaryRose,
                    ),
                    title: const Text(
                      'AI Spending Records Analysis',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Permit assistant to inject aggregate totals into prompt context',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: profile?.aiConsent ?? false,
                    activeThumbColor: AppColors.primaryRose,
                    onChanged: profile == null
                        ? null
                        : (val) {
                            AppHaptics.selection();
                            unawaited(
                              ref
                                  .read(profileProvider.notifier)
                                  .setAiConsent(val),
                            );
                          },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // App Store & Compliance Account Lifecycle Actions
            GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: Colors.orangeAccent,
                    ),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: _showSignOutDialog,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.delete_forever_rounded,
                      color: AppColors.error,
                    ),
                    title: const Text(
                      'Delete Account',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                    onTap: _showDeleteAccountDialog,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
