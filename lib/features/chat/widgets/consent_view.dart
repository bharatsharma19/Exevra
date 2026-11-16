import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/loading_button.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../dashboard/widgets/feature_snackbar.dart';
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
      showFeatureSnackbar(
        context,
        context.l10n.chatConsentPrivacyFailed,
        kind: AppSnackbarKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
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
                l10n.chatConsentTitle(l10n.chatAssistantName),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            section(
              Icons.receipt_long_outlined,
              l10n.chatConsentWhatTitle,
              l10n.chatConsentWhatBody,
            ),
            section(
              Icons.cloud_outlined,
              l10n.chatConsentWhoTitle,
              l10n.chatConsentWhoBody,
            ),
            section(
              Icons.lightbulb_outline,
              l10n.chatConsentWhyTitle,
              l10n.chatConsentWhyBody,
            ),
            section(
              Icons.toggle_on_outlined,
              l10n.chatConsentOptionalTitle,
              l10n.chatConsentOptionalBody,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _openPrivacy,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(l10n.chatConsentPrivacy),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.chatDisclaimer,
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
            LoadingButton(
              label: l10n.chatConsentAllow,
              isLoading: _saving,
              onPressed: _allow,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : widget.onNotNow,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(l10n.chatConsentNotNow),
            ),
          ],
        ),
      ),
    );
  }
}
