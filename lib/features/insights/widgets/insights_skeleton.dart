import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';

/// Placeholders in the shape of the summary, the chart and the category
/// list while the first load runs. Read as "Loading…" by screen readers.
class InsightsSkeleton extends StatelessWidget {
  const InsightsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('insights-loading'),
      label: context.l10n.loading,
      container: true,
      child: const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 140, height: 16),
                  SizedBox(height: AppSpacing.md),
                  SkeletonBox(width: 200, height: 40),
                  SizedBox(height: AppSpacing.lg),
                  SkeletonBox(width: 240, height: 16),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.xl),
            SkeletonBox(width: 160, height: 18),
            SizedBox(height: AppSpacing.sm),
            AppCard(child: SkeletonBox(height: 200)),
            SizedBox(height: AppSpacing.xl),
            SkeletonBox(width: 160, height: 18),
            SizedBox(height: AppSpacing.sm),
            AppCard(child: SkeletonList(itemCount: 3)),
          ],
        ),
      ),
    );
  }
}
