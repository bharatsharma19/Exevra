import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/auth_provider.dart';

class PhoneOtpScreen extends ConsumerStatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  ConsumerState<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends ConsumerState<PhoneOtpScreen> {
  final _phoneController = TextEditingController(text: '+1');
  final _otpController = TextEditingController();
  final _phoneFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  bool _isOtpSent = false;
  int _resendCountdown = 60;
  Timer? _timer;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _resendCountdown = 60;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() {
          _resendCountdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendOtp() async {
    if (_phoneFormKey.currentState?.validate() ?? false) {
      AppHaptics.light();
      await ref.read(authNotifierProvider.notifier).sendPhoneOtp(_phoneController.text);
      final auth = ref.read(authNotifierProvider);
      if (auth.errorMessage == null) {
        setState(() {
          _isOtpSent = true;
        });
        _startCountdown();
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpFormKey.currentState?.validate() ?? false) {
      AppHaptics.light();
      await ref.read(authNotifierProvider.notifier).verifyPhoneOtp(
            _phoneController.text,
            _otpController.text,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryCyan.withValues(alpha: 0.15),
                      border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.3)),
                    ),
                    child: Icon(
                      _isOtpSent ? Icons.mark_email_read_rounded : Icons.phone_android_rounded,
                      size: 40,
                      color: AppColors.primaryCyan,
                    ),
                  ),
                ).animate().scale(duration: 350.ms),

                const SizedBox(height: 20),

                Text(
                  _isOtpSent ? 'Verify 6-Digit Code' : 'Phone Verification',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ).animate().fadeIn(),

                const SizedBox(height: 8),

                Text(
                  _isOtpSent
                      ? 'Enter the 6-digit SMS code sent to ${_phoneController.text}'
                      : 'We will send a one-time verification code via SMS to authenticate your device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ).animate().fadeIn(delay: 100.ms),

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

                if (!_isOtpSent) ...[
                  Form(
                    key: _phoneFormKey,
                    child: GlassCard(
                      borderRadius: 24,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _sendOtp(),
                            validator: Validators.validatePhone,
                            decoration: const InputDecoration(
                              labelText: 'Mobile Phone Number',
                              hintText: '+1 555 123 4567',
                              prefixIcon: Icon(Icons.phone_rounded),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: authState.isLoading ? null : _sendOtp,
                              child: authState.isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(Colors.black),
                                      ),
                                    )
                                  : const Text('Send Verification Code'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Form(
                    key: _otpFormKey,
                    child: GlassCard(
                      borderRadius: 24,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 28,
                              letterSpacing: 10,
                              fontWeight: FontWeight.w700,
                            ),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _verifyOtp(),
                            validator: Validators.validateOtp,
                            decoration: const InputDecoration(
                              labelText: '6-Digit OTP',
                              hintText: '123456',
                              counterText: '',
                              prefixIcon: Icon(Icons.key_rounded),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: authState.isLoading ? null : _verifyOtp,
                              child: authState.isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(Colors.black),
                                      ),
                                    )
                                  : const Text('Verify & Enter'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isOtpSent = false;
                                  });
                                },
                                child: const Text('Change Number'),
                              ),
                              TextButton(
                                onPressed: _resendCountdown == 0 ? _sendOtp : null,
                                child: Text(
                                  _resendCountdown > 0
                                      ? 'Resend in ${_resendCountdown}s'
                                      : 'Resend Code',
                                  style: TextStyle(
                                    color: _resendCountdown == 0
                                        ? AppColors.primaryCyan
                                        : AppColors.darkTextTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
