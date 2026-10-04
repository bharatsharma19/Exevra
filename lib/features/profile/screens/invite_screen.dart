import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/expense_provider.dart';

class InviteScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteScreen({super.key, required this.token});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  bool _isLoading = false;
  String? _error;
  String? _inviteCode;

  @override
  void initState() {
    super.initState();
    _validateToken();
  }

  void _validateToken() {
    try {
      final normalizedToken = base64Url.normalize(widget.token);
      final decoded = utf8.decode(base64Url.decode(normalizedToken));
      final parts = decoded.split('|');
      if (parts.length != 2) throw Exception('Invalid token format');

      final code = parts[0];
      final exp = int.parse(parts[1]);

      if (DateTime.now().millisecondsSinceEpoch > exp) {
        setState(() {
          _error = 'This invite link has expired.';
        });
        return;
      }

      setState(() {
        _inviteCode = code;
      });

      // If user is already authenticated, join automatically
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final authState = ref.read(authNotifierProvider);
        if (authState.isAuthenticated && authState.isEmailVerified) {
          _joinGroup();
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Invalid invite link.';
      });
    }
  }

  Future<void> _joinGroup() async {
    if (_inviteCode == null) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final success = await ref
          .read(expenseProvider.notifier)
          .joinGroup(_inviteCode!);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully joined group!'),
            backgroundColor: AppColors.primaryEmerald,
          ),
        );
        context.go('/dashboard');
      } else if (mounted) {
        setState(() {
          _error = 'Failed to join group or already a member.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isAuthenticated =
        authState.isAuthenticated && authState.isEmailVerified;

    return Scaffold(
      appBar: AppBar(title: const Text('Group Invite')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.group_add_rounded,
                size: 64,
                color: AppColors.primaryCyan,
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 16),
                  textAlign: TextAlign.center,
                )
              else if (_inviteCode != null) ...[
                Text(
                  'You have been invited to join a group!',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (isAuthenticated)
                  _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _joinGroup,
                          child: const Text('Accept Invite'),
                        )
                else ...[
                  const Text('Please log in or sign up to accept this invite.'),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final returnTo = Uri.encodeComponent(
                        '/invite?token=${widget.token}',
                      );
                      context.go('/login?returnTo=$returnTo');
                    },
                    child: const Text('Log In'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      final returnTo = Uri.encodeComponent(
                        '/invite?token=${widget.token}',
                      );
                      context.go('/register?returnTo=$returnTo');
                    },
                    child: const Text('Sign Up'),
                  ),
                ],
              ] else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
