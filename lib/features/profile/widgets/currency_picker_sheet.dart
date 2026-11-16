import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../../models/currency_info.dart';

/// Opens the currency picker and resolves to the chosen code, or null when
/// it was closed without a choice.
Future<String?> showCurrencyPicker(
  BuildContext context, {
  required String selected,
}) => showAppSheet<String>(
  context: context,
  builder: (_) => CurrencyPicker(selected: selected),
);

/// A searchable list of the supported currencies (code, symbol and name);
/// the current one is marked with a check and "Selected".
class CurrencyPicker extends StatefulWidget {
  const CurrencyPicker({super.key, required this.selected});

  /// Currently selected code.
  final String selected;

  @override
  State<CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<CurrencyPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<CurrencyInfo> get _matches {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return CurrencyInfo.all;
    return [
      for (final c in CurrencyInfo.all)
        if (c.code.toLowerCase().contains(q) ||
            c.name.toLowerCase().contains(q) ||
            c.symbol.toLowerCase() == q)
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final matches = _matches;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.settingsCurrencyPickerTitle,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: palette.textPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('currency-search'),
          controller: _query,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.settingsCurrencySearch,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (matches.isEmpty)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                l10n.settingsCurrencyNoMatch(_query.text.trim()),
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textSecondary),
              ),
            ),
          )
        else
          for (final c in matches)
            AppListTile(
              key: Key('currency-${c.code}'),
              title: '${c.code} (${c.symbol})',
              subtitle: c.name,
              selected: c.code == widget.selected,
              semanticLabel: c.code == widget.selected
                  ? '${c.code}, ${c.name}, ${l10n.settingsCurrencySelected}'
                  : '${c.code}, ${c.name}',
              trailing: c.code == widget.selected
                  ? Icon(Icons.check_rounded, color: palette.accent)
                  : null,
              onTap: () => Navigator.of(context).pop(c.code),
            ),
      ],
    );
  }
}
