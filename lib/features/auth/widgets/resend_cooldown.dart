import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../l10n/l10n.dart';

/// A "Resend email" / "Resend code" button that stays disabled until
/// [availableAt], with a "You can resend in 0:42" countdown under it.
///
/// The countdown is not a live region (it would be read every second);
/// screen readers get "Resend available in 42 seconds" when they reach it,
/// and "You can send a new email now." is announced once the wait ends.
class ResendCooldownButton extends StatefulWidget {
  const ResendCooldownButton({
    super.key,
    required this.label,
    required this.availableAt,
    required this.onResend,
    this.busy = false,
    this.now = DateTime.now,
  });

  /// Button label ("Resend email").
  final String label;

  /// When the next email may be sent; null or past means now.
  final DateTime? availableAt;

  /// Sends the email again.
  final VoidCallback onResend;

  /// Disables the button while another request runs.
  final bool busy;

  /// Clock (tests pass their own).
  final DateTime Function() now;

  @override
  State<ResendCooldownButton> createState() => _ResendCooldownButtonState();
}

class _ResendCooldownButtonState extends State<ResendCooldownButton> {
  Timer? _ticker;

  int get _remaining {
    final at = widget.availableAt;
    if (at == null) return 0;
    final ms = at.difference(widget.now()).inMilliseconds;
    return math.max(0, (ms / 1000).ceil());
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ResendCooldownButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.availableAt != widget.availableAt) _sync();
  }

  void _sync() {
    if (_remaining <= 0) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (_remaining > 0) return;
    _ticker?.cancel();
    _ticker = null;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        context.l10n.authResendReady,
        Directionality.of(context),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final remaining = _remaining;
    final waiting = remaining > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: waiting || widget.busy ? null : widget.onResend,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(widget.label),
        ),
        if (waiting)
          Semantics(
            label: l10n.authResendInSemantics(remaining),
            child: ExcludeSemantics(
              child: Text(
                l10n.authResendIn(_clock(remaining)),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.palette.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        if (waiting) const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}
