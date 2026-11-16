import '../../l10n/l10n.dart';
import '../../models/insights.dart';

/// "Last 7 days", "Last 30 days" or "Last 12 months".
String timeframePeriod(AppLocalizations l10n, InsightTimeframe timeframe) =>
    switch (timeframe) {
      InsightTimeframe.week => l10n.insightsPeriodWeek,
      InsightTimeframe.month => l10n.insightsPeriodMonth,
      InsightTimeframe.year => l10n.insightsPeriodYear,
    };

/// "Week", "Month" or "Year" (segment labels).
String timeframeName(AppLocalizations l10n, InsightTimeframe timeframe) =>
    switch (timeframe) {
      InsightTimeframe.week => l10n.insightsTimeframeWeek,
      InsightTimeframe.month => l10n.insightsTimeframeMonth,
      InsightTimeframe.year => l10n.insightsTimeframeYear,
    };
