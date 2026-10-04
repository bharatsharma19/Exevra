import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/app_lock_provider.dart';

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
    final profile = ref.read(authNotifierProvider).profile;
    _nameController.text = profile?.displayName ?? '';
    _avatarUrlController.text =
        (profile?.avatarUrl != null &&
            !profile!.avatarUrl!.startsWith('preset:'))
        ? profile.avatarUrl!
        : '';
    String? currentPreset =
        (profile?.avatarUrl != null &&
            profile!.avatarUrl!.startsWith('preset:'))
        ? profile.avatarUrl!.replaceFirst('preset:', '')
        : '🚀';

    const presets = ['🚀', '⚛️', '💎', '🛡️', '🤖', '✨', '⚡', '🪐'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Profile & Avatar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Select Avatar Icon',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: presets.map((emoji) {
                    final isSelected = currentPreset == emoji;
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          currentPreset = emoji;
                          _avatarUrlController.clear();
                        });
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? AppColors.primaryCyan.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.05),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primaryCyan
                                : Colors.white12,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _avatarUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Or Custom Image URL',
                    prefixIcon: Icon(Icons.link_rounded),
                    hintText: 'https://...',
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty && currentPreset != null) {
                      setDialogState(() {
                        currentPreset = null;
                      });
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
            ElevatedButton(
              onPressed: () async {
                if (profile != null) {
                  final String? newAvatar =
                      _avatarUrlController.text.trim().isNotEmpty
                      ? _avatarUrlController.text.trim()
                      : (currentPreset != null
                            ? 'preset:$currentPreset'
                            : profile.avatarUrl);

                  final updated = profile.copyWith(
                    displayName: _nameController.text.trim(),
                    avatarUrl: newAvatar,
                  );
                  Navigator.of(ctx).pop();
                  await ref
                      .read(authNotifierProvider.notifier)
                      .updateProfile(updated);
                  AppHaptics.success();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Profile updated & synchronized with Supabase!',
                        ),
                        backgroundColor: AppColors.primaryEmerald,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } else {
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateGroupDialog() {
    _groupNameController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Household / Group'),
        content: TextField(
          controller: _groupNameController,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            hintText: 'e.g. Mercer Household',
            prefixIcon: Icon(Icons.group_add_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = _groupNameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(ctx).pop();
                await ref.read(expenseProvider.notifier).createGroup(name);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showJoinGroupDialog() {
    _inviteCodeController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join via Invite Code'),
        content: TextField(
          controller: _inviteCodeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Invite Code',
            hintText: 'e.g. INV-12345',
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
              String code = _inviteCodeController.text.trim();
              if (code.isNotEmpty) {
                Navigator.of(ctx).pop();
                if (code.contains('invite?token=')) {
                  final token = code
                      .split('invite?token=')
                      .last
                      .split('&')
                      .first
                      .split(' ')
                      .first;
                  try {
                    final normalizedToken = base64Url.normalize(token);
                    final decoded = utf8.decode(base64Url.decode(normalizedToken));
                    code = decoded.split('|')[0];
                  } catch (_) {}
                }
                await ref.read(expenseProvider.notifier).joinGroup(code);
              }
            },
            child: const Text('Join Group'),
          ),
        ],
      ),
    );
  }

  void _showInviteByEmailDialog() {
    final emailController = TextEditingController();
    String selectedRole = 'member';
    bool isSending = false;
    String? statusMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.email_outlined, color: AppColors.primaryCyan),
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
                  'Send an official invitation link directly to the recipient\'s email address.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Recipient Email',
                    hintText: 'member@example.com',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'member',
                      child: Text('Member (Add & Manage Expenses)'),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Admin (Full Control)'),
                    ),
                    DropdownMenuItem(
                      value: 'viewer',
                      child: Text('Viewer (Read Only)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedRole = val);
                    }
                  },
                ),
                if (statusMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    statusMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryEmerald,
                    ),
                  ),
                ],
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
                      final email = emailController.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a valid email address'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }

                      setDialogState(() {
                        isSending = true;
                        statusMessage = 'Dispatching invitation...';
                      });

                      final success = await ref
                          .read(expenseProvider.notifier)
                          .inviteMemberByEmail(
                            email: email,
                            role: selectedRole,
                          );

                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? 'Invitation dispatched to $email!'
                                  : 'Could not send invitation. Please try again.',
                            ),
                            backgroundColor: success
                                ? AppColors.primaryEmerald
                                : AppColors.error,
                          ),
                        );
                      }
                    },
                    child: const Text('Send Invitation'),
                  ),
          ],
        ),
      ),
    );
  }

  void _showSettleUpDialog({
    String? prefilledToUserId,
    double? prefilledAmount,
  }) {
    final expenseState = ref.read(expenseProvider);
    final authState = ref.read(authNotifierProvider);
    final currentUserId = authState.user?.id ?? 'demo-user-id';
    final currency =
        authState.profile?.currency ?? AppConstants.defaultCurrency;

    final otherMembers = expenseState.groupMembers
        .where((m) => m.userId != currentUserId)
        .toList();

    if (otherMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other members in this group to settle with.'),
          backgroundColor: AppColors.warning,
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
      text: prefilledAmount != null && prefilledAmount > 0
          ? prefilledAmount.toStringAsFixed(2)
          : '',
    );
    final notesController = TextEditingController(text: 'Settled via Exevra');
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.handshake_rounded, color: AppColors.primaryEmerald),
              SizedBox(width: 8),
              Text('Settle Up Debt'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Record a debt settlement payment between you and a group member.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRecipientId,
                  decoration: const InputDecoration(
                    labelText: 'Paid To',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                  items: otherMembers.map((m) {
                    final name = (m.displayName != null &&
                            m.displayName!.trim().isNotEmpty)
                        ? m.displayName!
                        : 'Member';
                    return DropdownMenuItem(value: m.userId, child: Text(name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedRecipientId = val);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount ($currency)',
                    prefixIcon: const Icon(Icons.payments_rounded),
                    hintText: '0.00',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Reference',
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
                      final amount =
                          double.tryParse(amountController.text.trim());
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a valid amount'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSubmitting = true);

                      final ok = await ref
                          .read(expenseProvider.notifier)
                          .recordSettlement(
                            toUserId: selectedRecipientId,
                            amount: amount,
                            notes: notesController.text.trim(),
                          );

                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Settlement payment recorded successfully!'
                                  : 'Failed to record settlement payment.',
                            ),
                            backgroundColor: ok
                                ? AppColors.primaryEmerald
                                : AppColors.error,
                          ),
                        );
                      }
                    },
                    child: const Text('Record Payment'),
                  ),
          ],
        ),
      ),
    );
  }

  void _showConfirmLeaveGroupDialog() {
    showDialog(
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
              ref.read(expenseProvider.notifier).leaveGroup();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Leave Group'),
          ),
        ],
      ),
    );
  }

  void _showConfirmDeleteGroupDialog() {
    showDialog(
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
              ref.read(expenseProvider.notifier).deleteGroup();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Group'),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog() {
    AppHaptics.medium();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to sign out of your account on this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authNotifierProvider.notifier).signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    AppHaptics.heavy();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Delete Account Permanently',
          style: TextStyle(color: AppColors.error),
        ),
        content: const Text(
          'This action is irreversible according to Store Compliance policies. '
          'All your personal expenses, records, profile metadata, and group associations will be permanently purged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authNotifierProvider.notifier).deleteAccount();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Permanently Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final expenseState = ref.watch(expenseProvider);
    final appLockState = ref.watch(appLockProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final profile = authState.profile;
    final resolvedDisplayName =
        (profile?.displayName != null && profile!.displayName.trim().isNotEmpty)
        ? profile.displayName
        : (authState.user?.userMetadata?['full_name'] as String? ??
              authState.user?.email?.split('@').first ??
              'User');
    final group = expenseState.currentGroup;
    final currentUserId = authState.user?.id ?? 'demo-user-id';
    final isGroupAdmin = group?.isAdmin(currentUserId) ?? false;

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
                            profile!.avatarUrl!.startsWith('preset:'))
                        ? Text(
                            profile.avatarUrl!.replaceFirst('preset:', ''),
                            style: const TextStyle(fontSize: 28),
                          )
                        : (profile?.avatarUrl != null &&
                              profile!.avatarUrl!.startsWith('http'))
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
                          profile?.email ??
                              authState.user?.email ??
                              'alex.mercer@antigravity.io',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                        ),
                        if (profile?.phone != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            profile!.phone!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkTextTertiary
                                  : AppColors.lightTextTertiary,
                            ),
                          ),
                        ],
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
                            'My Groups (${expenseState.userGroups.length})',
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
                        selected: expenseState.currentGroup == null,
                        avatar: expenseState.currentGroup == null
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
                        onSelected: (_) => ref
                            .read(expenseProvider.notifier)
                            .switchGroup(null),
                      ),
                      ...expenseState.userGroups.map((g) {
                        final isSelected =
                            expenseState.currentGroup?.id == g.id;
                        return ChoiceChip(
                          label: Text(g.name),
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
                          onSelected: (_) => ref
                              .read(expenseProvider.notifier)
                              .switchGroup(g.id),
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
                          group.inviteCode,
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
                            Clipboard.setData(
                              ClipboardData(text: group.inviteCode),
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
                    const SizedBox(height: 14),

                    // Invite Actions: Email vs Share Link
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showInviteByEmailDialog,
                            icon: const Icon(Icons.email_outlined, size: 16),
                            label: const Text('Invite by Email'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              AppHaptics.selection();
                              final exp = DateTime.now()
                                  .add(const Duration(days: 7))
                                  .millisecondsSinceEpoch;
                              final token = base64Url.encode(
                                utf8.encode('${group.inviteCode}|$exp'),
                              );
                              final shareText =
                                  'Join my group "${group.name}" on Exevra!\n\nClick this link to join:\nhttps://exevra.com/invite?token=$token';
                              Clipboard.setData(
                                ClipboardData(text: shareText),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Invite link copied to clipboard!',
                                  ),
                                  backgroundColor: AppColors.primaryCyan,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            },
                            icon: const Icon(Icons.share_rounded, size: 16),
                            label: const Text('Share Link'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Pending Invitations List (if any)
                    if (expenseState.pendingInvitations.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Pending Invitations (${expenseState.pendingInvitations.length})',
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
                        itemCount: expenseState.pendingInvitations.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final inv = expenseState.pendingInvitations[index];
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
                                        'Role: ${inv.role} • Expires: ${inv.expiresAt.day}/${inv.expiresAt.month}',
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
                                      .read(expenseProvider.notifier)
                                      .revokeInvitation(inv.id),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],

                    if (expenseState.groupMembers.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Group Members (${expenseState.groupMembers.length})',
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
                        itemCount: expenseState.groupMembers.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final m = expenseState.groupMembers[index];
                          final isViewer = m.isViewerOnly;
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
                                        m.displayName ?? 'User',
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
                                                  ? 'Viewer (Pending Review)'
                                                  : 'Member (Can Add)'),
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
                                        final ok = await ref
                                            .read(expenseProvider.notifier)
                                            .approveGroupMember(m.userId);
                                        if (ok && context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '${m.displayName ?? "Member"} approved! They can now record expenses.',
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
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.person_remove_rounded,
                                      size: 20,
                                      color: AppColors.error,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () async {
                                      final ok = await ref
                                          .read(expenseProvider.notifier)
                                          .removeGroupMember(m.userId);
                                      if (ok && context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${m.displayName ?? "Member"} removed from group.',
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
                        Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_rounded,
                              size: 18,
                              color: AppColors.primaryEmerald,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Group Balances & Debts',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () => _showSettleUpDialog(),
                          icon: const Icon(Icons.handshake_rounded, size: 16),
                          label: const Text('Settle Up'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (expenseState.settlements.isEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.primaryEmerald.withValues(alpha: 0.1),
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
                        itemCount: expenseState.settlements.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final debt = expenseState.settlements[index];
                          final iOwe = debt.fromUserId == currentUserId;
                          final owedToMe = debt.toUserId == currentUserId;

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
                                    ? AppColors.primaryRose.withValues(alpha: 0.4)
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
                                            ? 'You owe ${debt.toUserName}'
                                            : (owedToMe
                                                ? '${debt.fromUserName} owes you'
                                                : '${debt.fromUserName} owes ${debt.toUserName}'),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        CurrencyFormatter.format(
                                          debt.amount,
                                          currencyCode:
                                              authState.profile?.currency ??
                                              AppConstants.defaultCurrency,
                                        ),
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
                                      prefilledToUserId: debt.toUserId,
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

                    // Recent Settlements History
                    if (expenseState.settlementHistory.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Recent Settlement Payments (${expenseState.settlementHistory.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...expenseState.settlementHistory.take(3).map((s) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 14,
                                color: AppColors.primaryEmerald,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Payment of ${CurrencyFormatter.format(s.amount, currencyCode: authState.profile?.currency ?? AppConstants.defaultCurrency)}${s.notes != null ? " • ${s.notes}" : ""}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.lightTextTertiary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
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
                  // App Lock (Biometrics) Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(
                      Icons.fingerprint_rounded,
                      color: AppColors.primaryCyan,
                    ),
                    title: const Text(
                      'App Lock (Biometrics / PIN)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      appLockState.canCheckBiometrics
                          ? 'Protect application with Face ID, Fingerprint or Device PIN'
                          : 'Hardware biometric sensor not detected',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: appLockState.isBiometricsEnabled,
                    activeThumbColor: AppColors.primaryCyan,
                    onChanged: (val) async {
                      AppHaptics.selection();
                      if (val) {
                        final authenticated = await ref
                            .read(appLockProvider.notifier)
                            .authenticate(
                              customReason:
                                  'Authenticate to enable App Lock security',
                            );
                        if (authenticated) {
                          await ref
                              .read(appLockProvider.notifier)
                              .setBiometricsEnabled(true);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'App Lock enabled. Your data is secured.',
                                ),
                                backgroundColor: AppColors.primaryCyan,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      } else {
                        await ref
                            .read(appLockProvider.notifier)
                            .setBiometricsEnabled(false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('App Lock disabled.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
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
                      'Active Currency',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: DropdownButton<String>(
                      value: profile?.currency ?? AppConstants.defaultCurrency,
                      underline: const SizedBox(),
                      onChanged: (val) {
                        if (val != null) {
                          AppHaptics.selection();
                          ref
                              .read(authNotifierProvider.notifier)
                              .setCurrency(val);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Active currency updated to $val and synced with cloud.',
                              ),
                              backgroundColor: AppColors.primaryEmerald,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      items: AppConstants.currencies.entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.key} (${e.value})'),
                        );
                      }).toList(),
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
                    trailing: DropdownButton<String>(
                      value: profile?.themeMode ?? 'system',
                      underline: const SizedBox(),
                      onChanged: (val) {
                        if (val != null) {
                          AppHaptics.selection();
                          ref
                              .read(authNotifierProvider.notifier)
                              .setThemeMode(val);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Theme mode updated to $val and synced with cloud.',
                              ),
                              backgroundColor: AppColors.primaryEmerald,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      items: const [
                        DropdownMenuItem(
                          value: 'system',
                          child: Text('System'),
                        ),
                        DropdownMenuItem(
                          value: 'dark',
                          child: Text('Dark Space'),
                        ),
                        DropdownMenuItem(
                          value: 'light',
                          child: Text('Light Platinum'),
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
                    onChanged: (val) {
                      AppHaptics.selection();
                      ref
                          .read(authNotifierProvider.notifier)
                          .setHapticsEnabled(val);
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
                    onChanged: (val) {
                      AppHaptics.selection();
                      ref.read(authNotifierProvider.notifier).setAiConsent(val);
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
