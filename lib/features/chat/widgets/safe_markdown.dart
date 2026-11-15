import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL outside the app. Overridden in tests.
final externalLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Markdown for assistant answers, rendered defensively:
///
/// * images are never fetched (the alt text is shown at most);
/// * raw HTML is never rendered (it stays plain text);
/// * links open only after a dialog that shows the full URL;
/// * text is selectable.
class SafeMarkdown extends ConsumerWidget {
  const SafeMarkdown({super.key, required this.data, this.textColor});

  final String data;
  final Color? textColor;

  /// GitHub-flavoured block syntax with only harmless inline extensions
  /// (no inline HTML, emoji or colour swatches).
  static final md.ExtensionSet extensions = md.ExtensionSet(
    md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    [md.StrikethroughSyntax(), md.AutolinkExtensionSyntax()],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.bodyMedium?.copyWith(
      color: textColor ?? scheme.onSurface,
      height: 1.45,
    );
    final mono = base?.copyWith(
      fontFamily: 'monospace',
      fontSize: (base.fontSize ?? 14) * 0.92,
      color: scheme.onSurface,
      backgroundColor: scheme.surfaceContainerHighest,
    );
    return MarkdownBody(
      data: data,
      selectable: true,
      extensionSet: extensions,
      imageBuilder: (uri, title, alt) => _ImagePlaceholder(alt: alt),
      onTapLink: (text, href, title) => confirmAndOpenLink(
        context,
        href,
        ref.read(externalLinkLauncherProvider),
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        listBullet: base,
        tableBody: base,
        a: base?.copyWith(
          color: scheme.primary,
          decoration: TextDecoration.underline,
        ),
        code: mono,
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        blockquoteDecoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border(left: BorderSide(color: scheme.outline, width: 3)),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.alt});

  final String? alt;

  @override
  Widget build(BuildContext context) {
    final text = alt?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontStyle: FontStyle.italic,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Shows the full URL and opens it only when the user confirms. Only
/// `https` links can be opened.
Future<void> confirmAndOpenLink(
  BuildContext context,
  String? href,
  Future<bool> Function(Uri) launch,
) async {
  final uri = href == null ? null : Uri.tryParse(href.trim());
  final url = href?.trim() ?? '';
  if (url.isEmpty) return;
  final canOpen =
      uri != null && uri.scheme.toLowerCase() == 'https' && uri.host.isNotEmpty;
  final choice = await showDialog<_LinkChoice>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(canOpen ? 'Open this link?' : "This link can't be opened"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              canOpen
                  ? 'It will open outside Exevra. Check the address first:'
                  : 'Only secure (https) links can be opened. The address is:',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SelectableText(url, style: TextStyle(color: scheme.onSurface)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LinkChoice.copy),
            child: const Text('Copy link'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LinkChoice.cancel),
            child: const Text('Cancel'),
          ),
          if (canOpen)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_LinkChoice.open),
              child: const Text('Open'),
            ),
        ],
      );
    },
  );
  if (!context.mounted) return;
  switch (choice) {
    case _LinkChoice.open:
      final opened = await launch(uri!).catchError((Object _) => false);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the link.")),
        );
      }
    case _LinkChoice.copy:
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Link copied')));
      }
    case _LinkChoice.cancel || null:
      break;
  }
}

enum _LinkChoice { open, copy, cancel }
