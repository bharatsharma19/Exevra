import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../data/repositories/ai_report_repository.dart';
import '../../../providers/auth_provider.dart';
import '../models/chat_message.dart';

/// Asks why [message] is being reported and sends the report. Shows a
/// confirmation snack bar when it was saved.
Future<void> showReportSheet(BuildContext context, ChatMessage message) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ReportSheet(message: message),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks. Your report was sent.')),
    );
  }
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.message});

  final ChatMessage message;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _note = TextEditingController();
  AiReportReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    final uid = ref.read(currentUserIdProvider);
    if (reason == null || _sending) return;
    if (uid == null) {
      setState(
        () => _error = friendlyMessage(const AppFailure.sessionExpired()),
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(aiReportRepositoryProvider)
          .submit(
            AiReport(
              userId: uid,
              reason: reason,
              messageExcerpt: widget.message.text,
              provider: widget.message.provider?.name,
              note: _note.text,
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppFailure catch (failure) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = friendlyMessage(failure);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report response', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Tell us what was wrong. The answer text is sent with your '
              'report so we can review it.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            RadioGroup<AiReportReason>(
              groupValue: _reason,
              onChanged: (value) {
                if (!_sending) setState(() => _reason = value);
              },
              child: Column(
                children: [
                  for (final reason in AiReportReason.values)
                    RadioListTile<AiReportReason>(
                      value: reason,
                      title: Text(reason.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _note,
              enabled: !_sending,
              maxLength: AiReport.maxNoteLength,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Add a note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _sending
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _reason == null || _sending ? null : _submit,
                  child: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send report'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
