import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_messages.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/router/navigation.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/repositories/invitation_repository.dart';
import '../../../l10n/l10n.dart';
import '../../../models/invitation.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/group_detail_providers.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/pending_invite_provider.dart';
import '../widgets/invite_views.dart';
import '../../../core/utils/app_clock.dart';

/// Landing page of an invitation link (`/invite/<token>`).
///
/// Signed out, it asks to sign in (the invitation is kept for after). Signed
/// in, it shows the group, the inviter, the role and the expiry, with Join
/// and Decline (Decline asks first). An invitation for another address
/// explains that and offers to switch account.
class InviteScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteScreen({super.key, required this.token});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  InviteBusy _busy = InviteBusy.none;

  /// A failed accept or decline, shown on this screen.
  AppFailure? _actionFailure;

  String get _token => widget.token.trim();

  @override
  void initState() {
    super.initState();
    // Keep the invitation until a signed-in user has seen it, so it
    // survives signing in (and a restart while signed out).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(pendingInviteProvider.notifier);
      if (ref.read(currentUserIdProvider) == null) {
        pending.set(_token);
      } else {
        pending.clear();
      }
    });
  }

  /// Signed in with another address: sign out and keep the invitation
  /// for the next sign-in.
  Future<void> _switchAccount() async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (!mounted) return;
    ref.read(pendingInviteProvider.notifier).set(_token);
    setState(() => _actionFailure = null);
  }

  Future<void> _accept(String groupName) async {
    setState(() {
      _busy = InviteBusy.accepting;
      _actionFailure = null;
    });
    AppHaptics.light();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final joined = context.l10n.inviteJoined(groupName);
    final failure = await ref
        .read(groupsProvider.notifier)
        .acceptInvitation(_token);
    if (!mounted) return;
    if (failure != null) {
      AppHaptics.error();
      setState(() {
        _busy = InviteBusy.none;
        _actionFailure = failure;
      });
      return;
    }
    AppSnackbar.showSuccess(joined, messenger: messenger);
    context.go(AppRoutes.dashboard);
  }

  Future<void> _decline(String groupName) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.inviteDeclineTitle,
      message: l10n.inviteDeclineMessage(groupName),
      confirmLabel: l10n.inviteDecline,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = InviteBusy.declining;
      _actionFailure = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(invitationRepositoryProvider).decline(_token);
      if (!mounted) return;
      AppSnackbar.showInfo(l10n.inviteDeclined, messenger: messenger);
      context.go(AppRoutes.dashboard);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      AppHaptics.error();
      setState(() {
        _busy = InviteBusy.none;
        _actionFailure = failure;
      });
    }
  }

  void _close() {
    ref.read(pendingInviteProvider.notifier).clear();
    popOrGo(context, AppRoutes.root);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAuthenticated = ref.watch(currentUserIdProvider) != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inviteTitle),
        leading: AppIconButton(
          icon: Icons.close_rounded,
          tooltip: l10n.inviteClose,
          onPressed: _close,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _content(context, isAuthenticated),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, bool isAuthenticated) {
    final l10n = context.l10n;
    // Details are only shown to the signed-in invitee (the server checks
    // the invitation email), so a signed-out visitor sees sign-in first.
    final AsyncValue<InvitationDetails?> async = _token.isEmpty
        ? const AsyncError(
            AppFailure.business('invite_not_found'),
            StackTrace.empty,
          )
        : isAuthenticated
        ? ref.watch(invitationDetailsProvider(_token))
        : const AsyncData(null);
    final details = async.value;
    final failure = _actionFailure ?? async.error;

    if (async.isLoading && details == null) return const InviteLoadingView();
    if (failure != null) return _problem(context, failure, isAuthenticated);
    if (details == null) return _signedOut(context);

    final now = AppClock.now();
    final isExpired =
        details.status == InvitationStatus.expired ||
        !now.isBefore(details.expiresAt);
    final inviter = details.inviterName?.trim().isNotEmpty ?? false
        ? details.inviterName!
        : l10n.inviteSomeone;
    final group = details.groupName;

    final (hero, actions) = switch (details.status) {
      InvitationStatus.accepted => (
        InviteHero(
          icon: Icons.check_circle_outline_rounded,
          tone: InviteTone.success,
          title: l10n.inviteAcceptedTitle(group),
          message: l10n.inviteAcceptedMessage,
        ),
        <Widget>[
          LoadingButton(
            label: l10n.inviteOpenGroup,
            onPressed: () => context.go(AppRoutes.dashboard),
          ),
        ],
      ),
      InvitationStatus.revoked || InvitationStatus.declined => (
        InviteHero(
          icon: Icons.block_rounded,
          tone: InviteTone.danger,
          title: l10n.inviteCancelledTitle,
          message: l10n.inviteCancelledMessage,
        ),
        <Widget>[_goHome(context)],
      ),
      _ when isExpired => (
        InviteHero(
          icon: Icons.hourglass_disabled_rounded,
          tone: InviteTone.warning,
          title: l10n.inviteExpiredTitle,
          message: l10n.inviteExpiredMessage,
        ),
        <Widget>[_goHome(context)],
      ),
      _ => (
        InviteHero(
          icon: Icons.group_add_rounded,
          title: l10n.invitePendingTitle(group),
          message: l10n.invitePendingMessage(inviter),
        ),
        <Widget>[
          LoadingButton(
            key: const Key('invite-accept'),
            label: l10n.inviteAccept,
            icon: Icons.check_rounded,
            isLoading: _busy == InviteBusy.accepting,
            onPressed: _busy == InviteBusy.none
                ? () => unawaited(_accept(group))
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          LoadingButton(
            key: const Key('invite-decline'),
            label: l10n.inviteDecline,
            variant: LoadingButtonVariant.secondary,
            isLoading: _busy == InviteBusy.declining,
            onPressed: _busy == InviteBusy.none
                ? () => unawaited(_decline(group))
                : null,
          ),
        ],
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hero,
        const SizedBox(height: AppSpacing.xl),
        InviteDetailsCard(
          details: details,
          inviterName: inviter,
          isExpired: isExpired,
        ),
        const SizedBox(height: AppSpacing.xl),
        ...actions,
      ],
    );
  }

  Widget _goHome(BuildContext context) => LoadingButton(
    key: const Key('invite-home'),
    label: context.l10n.inviteGoHome,
    variant: LoadingButtonVariant.secondary,
    onPressed: () => context.go(AppRoutes.dashboard),
  );

  Widget _signedOut(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InviteHero(
          icon: Icons.mail_outline_rounded,
          title: l10n.inviteSignedOutTitle,
          message: l10n.inviteSignedOutMessage,
        ),
        const SizedBox(height: AppSpacing.xl),
        LoadingButton(
          key: const Key('invite-sign-in'),
          label: l10n.inviteSignIn,
          onPressed: () {
            ref.read(pendingInviteProvider.notifier).set(_token);
            context.go(AppRoutes.login);
          },
        ),
        const SizedBox(height: AppSpacing.md),
        LoadingButton(
          key: const Key('invite-register'),
          label: l10n.inviteCreateAccount,
          variant: LoadingButtonVariant.secondary,
          onPressed: () {
            ref.read(pendingInviteProvider.notifier).set(_token);
            context.go(AppRoutes.register);
          },
        ),
      ],
    );
  }

  Widget _problem(BuildContext context, Object error, bool isAuthenticated) {
    final l10n = context.l10n;
    final failure = error is AppFailure ? error : const AppFailure.unknown();
    final signedInEmail = ref.watch(authControllerProvider).user?.email;
    final wrongEmail =
        failure.key == 'invite_email_mismatch' && signedInEmail != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InviteHero(
          icon: wrongEmail
              ? Icons.alternate_email_rounded
              : Icons.error_outline_rounded,
          tone: InviteTone.danger,
          title: l10n.inviteProblemTitle,
          message: friendlyMessage(failure),
        ),
        if (wrongEmail) ...[
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            key: const Key('invite-wrong-email'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.inviteSignedInAs(signedInEmail),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.inviteWrongEmailHelp(signedInEmail)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LoadingButton(
            key: const Key('invite-switch-account'),
            label: l10n.inviteSwitchAccount,
            onPressed: () => unawaited(_switchAccount()),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (_actionFailure != null) ...[
          LoadingButton(
            label: l10n.inviteBack,
            variant: LoadingButtonVariant.secondary,
            onPressed: () => setState(() => _actionFailure = null),
          ),
          const SizedBox(height: AppSpacing.md),
        ] else if (isAuthenticated && _token.isNotEmpty && !wrongEmail) ...[
          LoadingButton(
            key: const Key('invite-retry'),
            label: l10n.retry,
            icon: Icons.refresh_rounded,
            onPressed: () => ref.invalidate(invitationDetailsProvider(_token)),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _goHome(context),
      ],
    );
  }
}
