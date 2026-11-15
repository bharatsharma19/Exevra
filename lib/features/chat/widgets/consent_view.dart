import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/profile_provider.dart';
import '../chat_copy.dart';
import 'safe_markdown.dart';

/// Explains what the assistant sends and to whom, and asks for consent.
/// Saving goes through `profileProvider.setAiConsent`; the server is the
/// source of truth.
///
/// Used in the chat tab and, full screen, by `AiConsentScreen` when the
/// assistant is turned on in Settings.
class ChatConsentView extends ConsumerStatefulWidget {
  const ChatConsentView({super.key, required this.onNotNow, this.onAllowed});

  final VoidCallback onNotNow;

  /// Called once consent was saved on the server.
  final VoidCallback? onAllowed;

  static Uri get privacyPolicy =>
      Uri.https(AppConfig.environment.appLinkHost, '/privacy');

  @override
  ConsumerState<ChatConsentView> createState() => _ChatConsentViewState();
}

class _ChatConsentViewState extends ConsumerState<ChatConsentView> {
  bool _saving = false;
  String? _error;

  Future<void> _allow() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final failure = await ref.read(profileProvider.notifier).setAiConsent(true);
    if (!mounted) return;
    if (failure == null) {
      ref.read(chatProvider.notifier).consentGranted();
    }
    setState(() {
      _saving = false;
      _error = failure == null ? null : friendlyMessage(failure);
    });
    if (failure == null) widget.onAllowed?.call();
  }

  Future<void> _openPrivacy() async {
    final launch = ref.read(externalLinkLauncherProvider);
    final opened = await launch(
      ChatConsentView.privacyPolicy,
    ).catchError((Object _) => false);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the privacy policy.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    Widget section(IconData icon, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: scheme.primary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(text, style: body),
              ],
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Before you use ${ChatCopy.assistantName}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            section(
              Icons.receipt_long_outlined,
              'What is sent',
              'Your spending totals by category and month, your 15 most '
                  'recent expenses (title, category, amount and date; for '
                  'group expenses only your share), the names of your groups, '
                  "your currency, time zone, language and today's date, and "
                  'the messages you write, including earlier messages in '
                  'this chat.',
            ),
            section(
              Icons.cloud_outlined,
              'Who receives it',
              "Anthropic's Claude answers your questions. If it is "
                  "unavailable, Google's Gemini is used as a backup.",
            ),
            section(
              Icons.lightbulb_outline,
              'Why',
              'So the assistant can answer questions about your own '
                  'spending, budgets and ways to save.',
            ),
            section(
              Icons.toggle_on_outlined,
              "It's optional",
              'You can use Exevra without the assistant and turn it off '
                  'at any time in Settings. Turning it off also deletes this '
                  'conversation from this device.',
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _openPrivacy,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Read the privacy policy'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ChatCopy.disclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _allow,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Allow and continue'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : widget.onNotNow,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
