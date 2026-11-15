import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../data/repositories/invitation_repository.dart';
import '../../../models/invitation.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/pending_invite_provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/router/navigation.dart';

class InviteScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteScreen({super.key, required this.token});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  bool _isAccepting = false;

  /// A failed accept or decline, shown on this screen.
  AppFailure? _actionFailure;

  String get _token => widget.token.trim();

  @override
  void initState() {
    super.initState();
    // Keep the invitation until a signed-in user has seen it, so it
    // survives signing in (and a restart while signed out).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(pendingInviteProvider.notifier);
      if (ref.read(currentUserIdProvider) == null) {
        pending.set(_token);
      } else {
        pending.clear();
      }
    });
  }

  /// Signed in with another address: sign out and keep the invitation
  /// for the next sign-in.
  Future<void> _switchAccount() async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (!mounted) return;
    ref.read(pendingInviteProvider.notifier).set(_token);
    setState(() => _actionFailure = null);
  }

  Future<void> _acceptInvitation() async {
    setState(() {
      _isAccepting = true;
      _actionFailure = null;
    });
    AppHaptics.light();
    final failure = await ref
        .read(groupsProvider.notifier)
        .acceptInvitation(_token);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _isAccepting = false;
        _actionFailure = failure;
      });
      return;
    }
    final name =
        ref.read(invitationDetailsProvider(_token)).value?.groupName ??
        'the group';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('You joined $name.')));
    context.go('/dashboard');
  }

  Future<void> _declineInvitation() async {
    setState(() {
      _isAccepting = true;
      _actionFailure = null;
    });
    try {
      await ref.read(invitationRepositoryProvider).decline(_token);
      if (mounted) context.go('/dashboard');
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isAccepting = false;
        _actionFailure = failure;
      });
      AppHaptics.error();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(currentUserIdProvider) != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Invitation'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close',
          onPressed: () {
            ref.read(pendingInviteProvider.notifier).clear();
            popOrGo(context, AppRoutes.root);
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _buildContent(context, isAuthenticated, isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    bool isAuthenticated,
    bool isDark,
  ) {
    // Details are only shown to the signed-in invitee (the server checks
    // the invitation email), so a signed-out visitor sees sign-in first.
    final AsyncValue<InvitationDetails?> async = _token.isEmpty
        ? const AsyncError(
            AppFailure.business('invite_not_found'),
            StackTrace.empty,
          )
        : isAuthenticated
        ? ref.watch(invitationDetailsProvider(_token))
        : const AsyncData(null);
    final details = async.value;
    final failure = _actionFailure ?? async.error;
    final String? error = failure == null
        ? null
        : friendlyMessage(
            failure is AppFailure ? failure : const AppFailure.unknown(),
          );
    final groupName = details?.groupName;
    final inviterName = details?.inviterName ?? 'A group admin';
    final status = details?.status;
    final expiresAt = details?.expiresAt.toLocal();
    // Invitations are bound to the invited address, which is the
    // signed-in user's own email once details load.
    final signedInEmail = ref.watch(authControllerProvider).user?.email;
    final recipientEmail = details == null ? null : signedInEmail;
    final isEmailMismatch =
        failure is AppFailure && failure.key == 'invite_email_mismatch';

    if (async.isLoading && details == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Verifying invitation details...',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      );
    }

    if (error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.error.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Invitation Issue',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(fontSize: 14, color: AppColors.error),
            textAlign: TextAlign.center,
          ),
          if (isEmailMismatch && signedInEmail != null) ...[
            const SizedBox(height: 8),
            Text(
              "You're signed in as $signedInEmail.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => unawaited(_switchAccount()),
              child: const Text('Sign out and use the invited address'),
            ),
          ],
          const SizedBox(height: 24),
          if (_actionFailure != null) ...[
            OutlinedButton(
              onPressed: () => setState(() => _actionFailure = null),
              child: const Text('Back'),
            ),
            const SizedBox(height: 8),
          ] else if (isAuthenticated && _token.isNotEmpty) ...[
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(invitationDetailsProvider(_token)),
              child: const Text('Retry'),
            ),
            const SizedBox(height: 8),
          ],
          ElevatedButton(
            onPressed: () => context.go('/dashboard'),
            child: const Text('Go to Dashboard'),
          ),
        ],
      );
    }

    final isExpired =
        status == InvitationStatus.expired ||
        (expiresAt != null && DateTime.now().isAfter(expiresAt));
    final isAlreadyAccepted = status == InvitationStatus.accepted;
    final isRevoked =
        status == InvitationStatus.revoked ||
        status == InvitationStatus.declined;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Glowing Icon
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isExpired || isRevoked
                    ? [Colors.orangeAccent, Colors.redAccent]
                    : [AppColors.primaryCyan, AppColors.primaryViolet],
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (isExpired || isRevoked
                              ? Colors.orange
                              : AppColors.primaryCyan)
                          .withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              isExpired || isRevoked
                  ? Icons.hourglass_disabled_rounded
                  : (isAlreadyAccepted
                        ? Icons.check_circle_rounded
                        : Icons.group_add_rounded),
              size: 40,
              color: Colors.white,
            ),
          ),
        ).animate().scale(duration: 350.ms, curve: Curves.easeOutBack),

        const SizedBox(height: 24),

        Text(
          isAlreadyAccepted
              ? 'Already Joined!'
              : (isExpired
                    ? 'Invitation Expired'
                    : (isRevoked
                          ? 'Invitation Revoked'
                          : "You're Invited to Join")),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        Text(
          isAlreadyAccepted
              ? 'You are already an active member of this group.'
              : (isExpired
                    ? 'This invitation link has expired. Please ask an admin or member to send a new invite.'
                    : (isRevoked
                          ? 'This invitation has been cancelled by the group admin.'
                          : '$inviterName has invited you to join their shared group on Exevra.')),
          style: TextStyle(
            fontSize: 14,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 24),

        // Group Details Glass Card
        GlassCard(
          borderRadius: 20,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryCyan.withValues(
                      alpha: 0.15,
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: AppColors.primaryCyan,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupName ?? 'Shared Group',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Invited by $inviterName',
                          style: TextStyle(
                            fontSize: 12,
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
              if (recipientEmail != null) ...[
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      size: 16,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Invited Email: $recipientEmail',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (expiresAt != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isExpired
                          ? 'Expired on ${expiresAt.day}/${expiresAt.month}/${expiresAt.year}'
                          : 'Valid until ${expiresAt.day}/${expiresAt.month}/${expiresAt.year}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isExpired
                            ? AppColors.error
                            : (isDark
                                  ? AppColors.darkTextTertiary
                                  : AppColors.lightTextTertiary),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 28),

        // Action Buttons
        if (isAlreadyAccepted) ...[
          ElevatedButton(
            onPressed: () => context.go('/dashboard'),
            child: const Text('Open Group Dashboard'),
          ),
        ] else if (isExpired || isRevoked) ...[
          ElevatedButton(
            onPressed: () => context.go('/dashboard'),
            child: const Text('Return to Dashboard'),
          ),
        ] else if (isAuthenticated) ...[
          _isAccepting
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton.icon(
                  onPressed: _acceptInvitation,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Accept & Join Group'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primaryCyan,
                    foregroundColor: Colors.black,
                  ),
                ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isAccepting ? null : _declineInvitation,
            child: const Text('Decline'),
          ),
        ] else ...[
          Text(
            'Sign in or register an account to join this group:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () {
              ref.read(pendingInviteProvider.notifier).set(_token);
              context.go(AppRoutes.login);
            },
            child: const Text('Sign In to Accept'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              ref.read(pendingInviteProvider.notifier).set(_token);
              context.go(AppRoutes.register);
            },
            child: const Text('Create New Account'),
          ),
        ],
      ],
    );
  }
}
