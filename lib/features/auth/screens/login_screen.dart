import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submitLogin() {
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(authNotifierProvider.notifier).signInWithEmail(
            _emailController.text,
            _passwordController.text,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background ambient gradient glow
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryCyan.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryViolet.withValues(alpha: 0.12),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Brand Header
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryCyan.withValues(alpha: 0.3),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.auto_graph_rounded,
                            size: 40,
                            color: Colors.black,
                          ),
                        ),
                      ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),

                      const SizedBox(height: 20),
                      Text(
                        'ANTIGRAVITY',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                          color: AppColors.primaryCyan,
                        ),
                      ).animate().fadeIn(delay: 150.ms),

                      const SizedBox(height: 6),
                      Text(
                        'Welcome Back',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),

                      const SizedBox(height: 8),
                      Text(
                        'Sign in to manage personal & shared finances',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ).animate().fadeIn(delay: 250.ms),

                      const SizedBox(height: 32),

                      if (authState.errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  authState.errorMessage!,
                                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ).animate().shake(duration: 350.ms),
                        const SizedBox(height: 18),
                      ],

                      // Glass Form Container
                      GlassCard(
                        borderRadius: 24,
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              validator: Validators.validateEmail,
                              decoration: const InputDecoration(
                                labelText: 'Email Address',
                                hintText: 'alex.mercer@antigravity.io',
                                prefixIcon: Icon(Icons.alternate_email_rounded),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submitLogin(),
                              validator: Validators.validatePassword,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  AppHaptics.selection();
                                  context.push('/forgot-password');
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: authState.isLoading ? null : _submitLogin,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: authState.isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(Colors.black),
                                        ),
                                      )
                                    : const Text(
                                        'Sign In',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),

                      const SizedBox(height: 20),

                      // Phone Auth Shortcut
                      OutlinedButton.icon(
                        onPressed: () {
                          AppHaptics.selection();
                          context.push('/phone-auth');
                        },
                        icon: const Icon(Icons.phone_iphone_rounded, size: 20),
                        label: const Text('Continue with Phone OTP'),
                      ).animate().fadeIn(delay: 350.ms),

                      const SizedBox(height: 24),

                      // Social Sign-In Divider
                      Row(
                        children: [
                          Expanded(child: Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'OR CONNECT WITH',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Google & Apple Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: authState.isLoading
                                  ? null
                                  : () => ref.read(authNotifierProvider.notifier).signInWithGoogle(),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(
                                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.g_mobiledata_rounded, size: 28, color: Colors.redAccent),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Google',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: authState.isLoading
                                  ? null
                                  : () => ref.read(authNotifierProvider.notifier).signInWithApple(),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(
                                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.apple,
                                    size: 22,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Apple',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 400.ms),

                      const SizedBox(height: 28),

                      // Sign Up Footer Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account?",
                            style: TextStyle(
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
                              if (returnTo != null) {
                                context.push('/register?returnTo=${Uri.encodeComponent(returnTo)}');
                              } else {
                                context.push('/register');
                              }
                            },
                            child: Text(
                              'Sign Up',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 450.ms),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
