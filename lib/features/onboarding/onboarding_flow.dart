import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility/reduce_motion.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/system_ui.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/loading_button.dart';
import '../../l10n/l10n.dart';
import 'onboarding_store.dart';

/// The three-page introduction shown once per device.
///
/// Every page has Skip; the last page has Get started. Pages change by
/// swiping, by the Next button, or with the system back gesture (which goes
/// to the previous page). Both Skip and Get started mark the introduction as
/// done through [onboardingCompletedProvider] and then call [onFinished],
/// where the caller navigates on (for example to the sign-in screen).
///
/// With reduced motion, page changes jump instead of sliding.
class OnboardingFlow extends ConsumerStatefulWidget {
  /// Creates the introduction.
  const OnboardingFlow({required this.onFinished, super.key});

  /// Called once after the introduction was finished or skipped and the
  /// completion was recorded. It must navigate away from the introduction.
  final VoidCallback onFinished;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  static const int _pageCount = 3;

  final PageController _controller = PageController();
  int _page = 0;

  /// Saving the completion flag; the Get started button shows a spinner.
  bool _saving = false;

  /// Finished or skipped; the buttons stay disabled until [onFinished]
  /// navigates away, so it is called only once.
  bool _finishing = false;

  bool get _isLast => _page == _pageCount - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _saving = _finishing = true);
    await ref.read(onboardingCompletedProvider.notifier).markCompleted();
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onFinished();
  }

  void _goTo(int page) {
    if (!_controller.hasClients) return;
    if (context.reduceMotion) {
      _controller.jumpToPage(page);
    } else {
      unawaited(
        _controller.animateToPage(
          page,
          duration: AppDurations.slow,
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _next() {
    if (_isLast) {
      unawaited(_finish());
    } else {
      _goTo(_page + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final pages = [
      _PageContent(
        icon: Icons.account_balance_wallet_outlined,
        satellites: const [
          Icons.person_outline,
          Icons.groups_outlined,
          Icons.currency_exchange,
        ],
        title: l10n.onboardingTrackTitle,
        body: l10n.onboardingTrackBody,
      ),
      _PageContent(
        icon: Icons.call_split,
        satellites: const [
          Icons.groups_outlined,
          Icons.handshake_outlined,
          Icons.verified_outlined,
        ],
        title: l10n.onboardingSplitTitle,
        body: l10n.onboardingSplitBody,
      ),
      _PageContent(
        icon: Icons.auto_awesome_outlined,
        satellites: const [
          Icons.chat_bubble_outline,
          Icons.insights_outlined,
          Icons.lock_outline,
        ],
        title: l10n.onboardingAssistantTitle,
        body: l10n.onboardingAssistantBody,
      ),
    ];
    assert(pages.length == _pageCount, 'Update _pageCount');
    final onSkip = _finishing ? null : () => unawaited(_finish());

    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page > 0) _goTo(_page - 1);
      },
      // No app bar here, so the region gives the status and navigation bar
      // icons the right brightness for the theme.
      child: SystemUiRegion(
        child: Scaffold(
          backgroundColor: palette.background,
          body: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    // The button keeps its own semantics node (focusable, with
                    // the focus action keyboard and switch users rely on); only
                    // its label is replaced by the fuller tooltip text.
                    child: Tooltip(
                      message: l10n.onboardingSkipTooltip,
                      excludeFromSemantics: true,
                      child: TextButton(
                        onPressed: onSkip,
                        child: Text(
                          l10n.onboardingSkip,
                          semanticsLabel: l10n.onboardingSkipTooltip,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (page) => setState(() => _page = page),
                    children: [
                      for (final page in pages) _OnboardingPage(content: page),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OnboardingPageIndicator(
                        current: _page,
                        count: _pageCount,
                        title: pages[_page].title,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: LoadingButton(
                          label: _isLast
                              ? l10n.onboardingGetStarted
                              : l10n.onboardingNext,
                          icon: _isLast ? null : Icons.arrow_forward,
                          isLoading: _saving && _isLast,
                          onPressed: _finishing ? null : _next,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dots showing the current introduction page, read by screen readers as
/// "Page 1 of 3: Track every expense" and announced when the page changes,
/// so screen reader users hear the new page without leaving the Next button.
///
/// The current dot is wider as well as accent-coloured, so the position does
/// not rely on colour alone.
class OnboardingPageIndicator extends StatelessWidget {
  /// Creates the indicator. [current] is zero-based.
  const OnboardingPageIndicator({
    required this.current,
    required this.count,
    this.title,
    super.key,
  });

  /// Zero-based index of the current page.
  final int current;

  /// Number of pages.
  final int count;

  /// Title of the current page, included in the announcement.
  final String? title;

  static const double _dot = 8;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final duration = context.reduceMotion ? Duration.zero : AppDurations.fast;
    return Semantics(
      container: true,
      liveRegion: true,
      label: title == null
          ? context.l10n.onboardingPageIndicator(current + 1, count)
          : context.l10n.onboardingPageAnnouncement(current + 1, count, title!),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                width: i == current ? _dot * 3 : _dot,
                height: _dot,
                decoration: BoxDecoration(
                  color: i == current ? palette.accent : palette.outline,
                  borderRadius: AppRadius.pillAll,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PageContent {
  const _PageContent({
    required this.icon,
    required this.satellites,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final List<IconData> satellites;
  final String title;
  final String body;
}

class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage({required this.content});

  final _PageContent content;

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage> {
  /// Text scale from which the scrollbar always shows, so readers can see
  /// that more text follows below the fold.
  static const double _largeTextScale = 1.5;

  /// Below this size the art is left out to give the text the room.
  static const double _minArt = 72;

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The art shrinks on short screens and with the text size, so the
        // text keeps most of the room, and it is left out once it would be
        // too small to read. The page scrolls if it still does not fit.
        final art =
            math.min(
              200.0,
              math.min(constraints.maxWidth * 0.6, constraints.maxHeight * 0.4),
            ) /
            math.max(1.0, textScale);
        final showArt = art >= _minArt;
        return Scrollbar(
          controller: _scroll,
          thumbVisibility: textScale >= _largeTextScale,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showArt) ...[
                        _Illustration(
                          size: art,
                          icon: content.icon,
                          satellites: content.satellites,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      Semantics(
                        header: true,
                        child: Text(
                          content.title,
                          textAlign: TextAlign.center,
                          style: textTheme.headlineSmall?.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        content.body,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Decorative art built from icons and palette tokens: a large icon in an
/// accent disc with three small badges around it.
class _Illustration extends StatelessWidget {
  const _Illustration({
    required this.size,
    required this.icon,
    required this.satellites,
  });

  final double size;
  final IconData icon;
  final List<IconData> satellites;

  static const List<Alignment> _positions = [
    Alignment(-0.95, -0.7),
    Alignment(0.95, -0.45),
    Alignment(0.7, 0.95),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final badgeColors = [palette.accent, palette.secondary, palette.success];
    final badge = size * 0.26;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Center(
              child: Container(
                width: size * 0.72,
                height: size * 0.72,
                decoration: BoxDecoration(
                  color: palette.accentContainer,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.accent, width: 2),
                ),
                child: Icon(
                  icon,
                  size: size * 0.34,
                  color: palette.onAccentContainer,
                ),
              ),
            ),
            for (var i = 0; i < math.min(satellites.length, 3); i++)
              Align(
                alignment: _positions[i],
                child: Container(
                  width: badge,
                  height: badge,
                  decoration: BoxDecoration(
                    color: palette.surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.outline),
                  ),
                  child: Icon(
                    satellites[i],
                    size: badge * 0.5,
                    color: badgeColors[i],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
