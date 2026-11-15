import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/legal_links.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_list_tile.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/loading_button.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/l10n.dart';

/// About and legal: app name, tagline, version and build, the credit line,
/// links to the privacy policy, terms, support and the account deletion
/// page, the open-source licenses, and (when signed in) Delete account.
///
/// Standalone: the caller owns navigation and account deletion. Pass
/// [onDeleteAccount] to show the Delete account button (for example the
/// signed-in profile flow, which confirms and deletes); leave it null to hide
/// it (for example when signed out).
class AboutScreen extends StatefulWidget {
  /// Creates the About screen.
  const AboutScreen({
    this.onDeleteAccount,
    this.links,
    this.launcher,
    super.key,
  });

  /// Starts account deletion. The button is hidden when null.
  final VoidCallback? onDeleteAccount;

  /// Link targets; defaults to [LegalLinks.current].
  final LegalLinks? links;

  /// Opens external links; defaults to the platform launcher. For tests.
  final ExternalUrlLauncher? launcher;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<PackageInfo?> _info = _loadInfo();

  static Future<PackageInfo?> _loadInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } on Object catch (error) {
      AppLogger.warn('Could not read the app version', error);
      return null;
    }
  }

  LegalLinks get _links => widget.links ?? LegalLinks.current;

  Future<void> _open(Uri uri, {String? failureMessage}) => openExternal(
    context,
    uri,
    failureMessage: failureMessage,
    launcher: widget.launcher,
  );

  /// Emails support; the body names the version and build ("1.0.0 (1)").
  Future<void> _emailSupport(PackageInfo? info) {
    final l10n = context.l10n;
    final links = _links;
    return _open(
      links.supportEmailUri(
        subject: l10n.supportEmailSubject,
        body: info == null
            ? null
            : l10n.supportEmailBody('${info.version} (${info.buildNumber})'),
      ),
      failureMessage: l10n.supportEmailOpenFailed(links.supportEmail),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: SafeArea(
        top: false,
        child: FutureBuilder<PackageInfo?>(
          future: _info,
          builder: (context, snapshot) {
            final info = snapshot.data;
            final version = info == null
                ? null
                : l10n.aboutVersion(info.version, info.buildNumber);
            return _AboutBody(
              version: version,
              links: _links,
              onOpen: (uri) => unawaited(_open(uri)),
              onEmailSupport: () => unawaited(_emailSupport(info)),
              onLicences: () => showLicensePage(
                context: context,
                applicationName: l10n.appName,
                applicationVersion: version,
                applicationLegalese: l10n.aboutLegalese,
              ),
              onDeleteAccount: widget.onDeleteAccount,
            );
          },
        ),
      ),
    );
  }
}

/// The About rows never cut their text off (WCAG 1.4.4): at 200% text on a
/// 320dp screen the deletion info subtitle alone needs four lines, and
/// translations run longer. AppListTile takes a number, so this is a limit
/// no row reaches.
const int _rowMaxLines = 100;

class _AboutBody extends StatelessWidget {
  const _AboutBody({
    required this.version,
    required this.links,
    required this.onOpen,
    required this.onEmailSupport,
    required this.onLicences,
    required this.onDeleteAccount,
  });

  final String? version;
  final LegalLinks links;
  final ValueChanged<Uri> onOpen;
  final VoidCallback onEmailSupport;
  final VoidCallback onLicences;
  final VoidCallback? onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final secondary = textTheme.bodyMedium?.copyWith(
      color: palette.textSecondary,
    );
    final external = Icon(
      Icons.open_in_new,
      size: AppSizes.iconSm,
      semanticLabel: l10n.opensInBrowser,
    );
    const sectionPadding = EdgeInsets.fromLTRB(
      AppSpacing.xs,
      AppSpacing.xl,
      AppSpacing.xs,
      AppSpacing.sm,
    );
    const groupPadding = EdgeInsets.all(AppSpacing.xs);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: Semantics(
            header: true,
            child: const BrandMark(size: 32, showTagline: true),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (version != null)
          Text(version!, textAlign: TextAlign.center, style: secondary),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.aboutCredit, textAlign: TextAlign.center, style: secondary),
        SectionHeader(title: l10n.aboutSupportSection, padding: sectionPadding),
        AppCard(
          padding: groupPadding,
          child: Column(
            children: [
              AppListTile(
                titleMaxLines: _rowMaxLines,
                subtitleMaxLines: _rowMaxLines,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: l10n.aboutPrivacyPolicy,
                trailing: external,
                onTap: () => onOpen(links.privacyPolicy),
              ),
              AppListTile(
                titleMaxLines: _rowMaxLines,
                subtitleMaxLines: _rowMaxLines,
                leading: const Icon(Icons.description_outlined),
                title: l10n.aboutTermsOfUse,
                trailing: external,
                onTap: () => onOpen(links.terms),
              ),
              AppListTile(
                titleMaxLines: _rowMaxLines,
                subtitleMaxLines: _rowMaxLines,
                leading: const Icon(Icons.support_agent_outlined),
                title: l10n.aboutHelpSupport,
                subtitle: links.supportEmail,
                trailing: const Icon(Icons.mail_outline, size: AppSizes.iconSm),
                onTap: onEmailSupport,
              ),
              AppListTile(
                titleMaxLines: _rowMaxLines,
                subtitleMaxLines: _rowMaxLines,
                leading: const Icon(Icons.article_outlined),
                title: l10n.aboutLicenses,
                trailing: const Icon(Icons.chevron_right),
                onTap: onLicences,
              ),
            ],
          ),
        ),
        SectionHeader(title: l10n.aboutAccountSection, padding: sectionPadding),
        AppCard(
          padding: groupPadding,
          child: AppListTile(
            titleMaxLines: _rowMaxLines,
            subtitleMaxLines: _rowMaxLines,
            leading: const Icon(Icons.manage_accounts_outlined),
            title: l10n.aboutDeleteAccountInfo,
            subtitle: l10n.aboutDeleteAccountInfoSubtitle,
            trailing: external,
            onTap: () => onOpen(links.deleteAccount),
          ),
        ),
        if (onDeleteAccount != null) ...[
          const SizedBox(height: AppSpacing.xl),
          LoadingButton(
            label: l10n.aboutDeleteAccount,
            icon: Icons.delete_forever_outlined,
            variant: LoadingButtonVariant.destructive,
            onPressed: onDeleteAccount,
          ),
        ],
      ],
    );
  }
}
