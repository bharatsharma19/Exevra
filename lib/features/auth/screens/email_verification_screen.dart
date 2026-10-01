import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/auth_provider.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends ConsumerState<EmailVerificationScreen> {
  int _cooldownSeconds = 60;
  Timer? _timer;
  bool _canResend = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    setState(() {
      _cooldownSeconds = 60;
      _canResend = false;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds > 1) {
        setState(() {
          _cooldownSeconds--;
        });
      } else {
        setState(() {
          _cooldownSeconds = 0;
          _canResend = true;
        });
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _handleRefreshStatus() async {
    setState(() {
      _isRefreshing = true;
    });
    AppHaptics.medium();

    final isVerified = await ref
        .read(authNotifierProvider.notifier)
        .refreshEmailVerificationStatus();

    if (!mounted) return;

    setState(() {
      _isRefreshing = false;
    });

    if (isVerified) {
      AppHaptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email confirmed! Unlocking your dashboard...'),
          backgroundColor: AppColors.primaryEmerald,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      AppHaptics.medium();
      _showPasswordSignInDialog();
    }
  }

  void _showPasswordSignInDialog() {
    final passwordController = TextEditingController();
    final authState = ref.read(authNotifierProvider);
    final email = authState.user?.email ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Verification Sign-In'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Once you click the link in your email, enter your password below to finalize sign-in and save your session.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authNotifierProvider.notifier).signOut();
            },
            child: const Text('Back to Login'),
          ),
          ElevatedButton(
            onPressed: () async {
              final pwd = passwordController.text.trim();
              if (pwd.isNotEmpty) {
                Navigator.of(ctx).pop();
                await ref.read(authNotifierProvider.notifier).signInWithEmail(email, pwd);
              }
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleResendEmail() async {
    if (!_canResend) return;

    AppHaptics.light();
    await ref.read(authNotifierProvider.notifier).resendVerificationEmail();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Verification link dispatched. Please check your inbox and spam.'),
        backgroundColor: AppColors.primaryCyan,
        duration: Duration(seconds: 3),
      ),
    );

    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppAuthState>(authNotifierProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppColors.primaryRose,
          ),
        );
      }
    });

    final authState = ref.watch(authNotifierProvider);
    final userEmail = authState.user?.email ?? 'your email address';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated Glowing Email Icon
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryCyan.withValues(alpha: 0.2),
                        AppColors.primaryViolet.withValues(alpha: 0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: AppColors.primaryCyan.withValues(alpha: 0.4),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryCyan.withValues(alpha: 0.25),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_rounded,
                    size: 48,
                    color: AppColors.primaryCyan,
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat(reverse: true))
                    .scale(
                      begin: const Offset(0.96, 0.96),
                      end: const Offset(1.04, 1.04),
                      duration: 1600.ms,
                      curve: Curves.easeInOut,
                    ),

                const SizedBox(height: 28),

                // Title
                Text(
                  'Verify Your Email',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),

                const SizedBox(height: 12),

                // Description
                Text(
                  'We sent a confirmation link to your registered email address:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

                const SizedBox(height: 12),

                // Highlighted User Email Badge
                GlassCard(
                  borderRadius: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.alternate_email_rounded, size: 18, color: AppColors.primaryCyan),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          userEmail,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryCyan,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                const SizedBox(height: 18),

                Text(
                  'Click the activation link inside the email to immediately unlock your dashboard, expense tracking, and group telemetry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                  ),
                ).animate().fadeIn(delay: 250.ms, duration: 400.ms),

                const SizedBox(height: 32),

                // Primary Action: Refresh Status / "I've Verified My Email"
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isRefreshing ? null : _handleRefreshStatus,
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline_rounded, size: 20),
                    label: Text(
                      _isRefreshing ? 'Checking Confirmation...' : "I've Verified My Email",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryCyan,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),

                const SizedBox(height: 16),

                // Secondary Action: Resend Verification Email with Cooldown
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _canResend ? _handleResendEmail : null,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      _canResend
                          ? 'Resend Verification Email'
                          : 'Resend Email ($_cooldownSeconds s)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide(
                        color: _canResend ? AppColors.primaryCyan : Colors.white24,
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1, end: 0),

                const SizedBox(height: 12),

                // Already verified? Direct password sign-in
                TextButton.icon(
                  onPressed: () {
                    AppHaptics.selection();
                    _showPasswordSignInDialog();
                  },
                  icon: const Icon(Icons.vpn_key_rounded, size: 16, color: AppColors.primaryCyan),
                  label: const Text(
                    'Already confirmed in browser? Enter Password to Sign In',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryCyan,
                    ),
                  ),
                ).animate().fadeIn(delay: 380.ms),

                const SizedBox(height: 16),

                // Sign Out / Back to Login
                TextButton.icon(
                  onPressed: () {
                    AppHaptics.light();
                    ref.read(authNotifierProvider.notifier).signOut();
                  },
                  icon: const Icon(Icons.logout_rounded, size: 16, color: AppColors.darkTextSecondary),
                  label: const Text(
                    'Sign Out / Back to Login',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkTextSecondary,
                    ),
                  ),
                ).animate().fadeIn(delay: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
