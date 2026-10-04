import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../services/supabase_service.dart';

class InviteScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteScreen({super.key, required this.token});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  bool _isLoading = true;
  bool _isAccepting = false;
  String? _error;

  String? _groupName;
  String? _inviterName;
  String? _recipientEmail;
  String? _status;
  DateTime? _expiresAt;
  bool _isLegacyCode = false;
  String? _legacyCode;

  @override
  void initState() {
    super.initState();
    _loadInvitationDetails();
  }

  Future<void> _loadInvitationDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final token = widget.token.trim();
    if (token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Invitation link is missing a security token.';
      });
      return;
    }

    try {
      // 1. First attempt to query cryptographic token via RPC / table
      final details =
          await SupabaseService.instance.getInvitationDetails(token);

      if (details != null) {
        final expiresAtStr = details['expires_at'] as String?;
        final expiresAt =
            expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;
        final isExpired = details['is_expired'] == true ||
            (expiresAt != null && DateTime.now().isAfter(expiresAt));

        setState(() {
          _groupName = details['group_name'] as String? ?? 'Shared Group';
          _inviterName = details['inviter_name'] as String? ?? 'A member';
          _recipientEmail = details['email'] as String?;
          _status = isExpired ? 'expired' : (details['status'] as String? ?? 'pending');
          _expiresAt = expiresAt;
          _isLoading = false;
        });
        return;
      }

      // 2. If not found in invitations table, fallback to legacy base64 format (code|exp)
      _tryLegacyToken(token);
    } catch (e) {
      _tryLegacyToken(token);
    }
  }

  void _tryLegacyToken(String rawToken) {
    try {
      final normalizedToken = base64Url.normalize(rawToken);
      final decoded = utf8.decode(base64Url.decode(normalizedToken));
      final parts = decoded.split('|');

      if (parts.length >= 2) {
        final code = parts[0];
        final exp = int.tryParse(parts[1]) ?? 0;
        final isExpired = DateTime.now().millisecondsSinceEpoch > exp;

        setState(() {
          _isLegacyCode = true;
          _legacyCode = code;
          _groupName = 'Expense Group ($code)';
          _inviterName = 'A group member';
          _status = isExpired ? 'expired' : 'pending';
          _expiresAt = DateTime.fromMillisecondsSinceEpoch(exp);
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    setState(() {
      _isLoading = false;
      _error = 'This invitation link is invalid or has expired.';
    });
  }

  Future<void> _acceptInvitation() async {
    setState(() => _isAccepting = true);
    AppHaptics.light();

    try {
      bool success = false;

      if (_isLegacyCode && _legacyCode != null) {
        success = await ref
            .read(expenseProvider.notifier)
            .joinGroup(_legacyCode!);
      } else {
        success = await ref
            .read(expenseProvider.notifier)
            .acceptInvitation(widget.token.trim());
      }

      if (success && mounted) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully joined ${_groupName ?? "the group"}!',
            ),
            backgroundColor: AppColors.primaryEmerald,
          ),
        );
        context.go('/dashboard');
      } else if (mounted) {
        setState(() {
          _isAccepting = false;
          _error = 'Could not accept invitation. It may have expired or already been accepted.';
        });
        AppHaptics.error();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAccepting = false;
          _error = e.toString().replaceAll('Exception:', '').trim();
        });
        AppHaptics.error();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isAuthenticated = authState.isAuthenticated;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Invitation'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
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
    if (_isLoading) {
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

    if (_error != null) {
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
            _error!,
            style: const TextStyle(fontSize: 14, color: AppColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/dashboard'),
            child: const Text('Go to Dashboard'),
          ),
        ],
      );
    }

    final isExpired = _status == 'expired';
    final isAlreadyAccepted = _status == 'accepted';
    final isRevoked = _status == 'revoked';

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
                  color: (isExpired || isRevoked
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
                      : '$_inviterName has invited you to join their shared group on Exevra.')),
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
                    backgroundColor:
                        AppColors.primaryCyan.withValues(alpha: 0.15),
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
                          _groupName ?? 'Shared Group',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Invited by $_inviterName',
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
              if (_recipientEmail != null) ...[
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
                        'Invited Email: $_recipientEmail',
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
              if (_expiresAt != null) ...[
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
                          ? 'Expired on ${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}'
                          : 'Valid until ${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}',
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
            onPressed: () => context.go('/dashboard'),
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
              final returnTo =
                  Uri.encodeComponent('/invite?token=${widget.token}');
              context.go('/login?returnTo=$returnTo');
            },
            child: const Text('Sign In to Accept'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              final returnTo =
                  Uri.encodeComponent('/invite?token=${widget.token}');
              context.go('/register?returnTo=$returnTo');
            },
            child: const Text('Create New Account'),
          ),
        ],
      ],
    );
  }
}
