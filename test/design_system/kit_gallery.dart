import 'package:expense_manager/core/theme/app_palette.dart';
import 'package:expense_manager/core/theme/app_tokens.dart';
import 'package:expense_manager/core/widgets/widgets.dart';
import 'package:flutter/material.dart';

/// Renders [child] in [theme] on the page background, with animations
/// disabled so skeletons are static and goldens are deterministic.
class ThemedFrame extends StatelessWidget {
  const ThemedFrame({
    required this.theme,
    required this.child,
    this.disableAnimations = true,
    super.key,
  });

  final ThemeData theme;
  final Widget child;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: Theme(
        data: theme,
        child: Builder(
          builder: (context) => Material(
            color: context.palette.background,
            child: DefaultTextStyle.merge(
              style: TextStyle(color: context.palette.textPrimary),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// One of every kit widget, stacked vertically.
class KitGallery extends StatelessWidget {
  const KitGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OfflineBanner(),
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: BrandMark(showTagline: true),
        ),
        SectionHeader(
          title: 'Buttons',
          actionLabel: 'See all',
          onAction: () {},
        ),
        Padding(
          padding: AppSpacing.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LoadingButton(label: 'Save expense', onPressed: () {}),
              const SizedBox(height: AppSpacing.sm),
              LoadingButton(
                label: 'Save expense',
                onPressed: () {},
                isLoading: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              LoadingButton(
                label: 'Invite member',
                onPressed: () {},
                variant: LoadingButtonVariant.secondary,
                icon: Icons.person_add_alt,
              ),
              const SizedBox(height: AppSpacing.sm),
              LoadingButton(
                label: 'Delete group',
                onPressed: () {},
                variant: LoadingButtonVariant.destructive,
              ),
              const SizedBox(height: AppSpacing.sm),
              const LoadingButton(label: 'Disabled', onPressed: null),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  AppIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit expense',
                    onPressed: () {},
                  ),
                  AppIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete expense',
                    onPressed: () {},
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () {},
                      child: const Text('Text'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'Cards'),
        Padding(
          padding: AppSpacing.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                onTap: () {},
                child: const Column(
                  children: [
                    KeyValueRow(label: 'Paid by', value: 'Priya'),
                    KeyValueRow.custom(
                      label: 'You are owed',
                      valueWidget: AmountText(
                        '₹1,250.00',
                        sign: AmountSign.positive,
                      ),
                    ),
                    KeyValueRow.custom(
                      label: 'You owe',
                      valueWidget: AmountText(
                        '₹300.00',
                        sign: AmountSign.negative,
                      ),
                    ),
                    KeyValueRow(
                      label: 'Total',
                      value: '₹950.00',
                      emphasize: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const AppCard.glass(child: Text('Glass hero surface')),
            ],
          ),
        ),
        const SectionHeader(title: 'Inputs'),
        const Padding(
          padding: AppSpacing.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmountField(
                label: 'Amount',
                currencySymbol: '₹',
                initialValue: '1250.00',
                helperText: 'Split equally between 3 people',
              ),
              SizedBox(height: AppSpacing.md),
              AmountField(
                label: 'Your share',
                currencySymbol: '₹',
                errorText: 'Enter an amount above zero',
              ),
              SizedBox(height: AppSpacing.md),
              AppPasswordField(label: 'Password'),
              SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  AppAvatar(name: 'Priya Sharma'),
                  SizedBox(width: AppSpacing.sm),
                  AppAvatar(name: 'Arjun'),
                  SizedBox(width: AppSpacing.sm),
                  AppAvatar(name: 'Meera Iyer'),
                ],
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'List'),
        AppListTile(
          leading: const Icon(Icons.restaurant),
          title: 'Dinner at the station café',
          subtitle: 'Food · Today',
          trailing: const AmountText('₹480.00', sign: AmountSign.negative),
          onTap: () {},
        ),
        AppListTile(
          leading: const Icon(Icons.payments_outlined),
          title: 'Settlement from Arjun',
          subtitle: 'Yesterday',
          trailing: const StatusBadge(StatusBadgeKind.pending),
          onTap: () {},
        ),
        AppListTile(
          leading: const Icon(Icons.group_outlined),
          title: 'Flatmates',
          subtitle: 'Selected group',
          selected: true,
          onTap: () {},
        ),
        const SectionHeader(title: 'Badges'),
        const Padding(
          padding: AppSpacing.page,
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusBadge(StatusBadgeKind.pending),
              StatusBadge(StatusBadgeKind.confirmed),
              StatusBadge(StatusBadgeKind.voided),
              StatusBadge(StatusBadgeKind.admin),
              StatusBadge(StatusBadgeKind.member),
              StatusBadge(StatusBadgeKind.viewer),
            ],
          ),
        ),
        const SectionHeader(title: 'Snackbars'),
        Padding(
          padding: AppSpacing.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final kind in AppSnackbarKind.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppSnackbarPreview('Expense saved', kind: kind),
                ),
            ],
          ),
        ),
        const SectionHeader(title: 'States'),
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No expenses yet',
          message: 'Add your first expense to see it here.',
          actionLabel: 'Add expense',
          onAction: () {},
        ),
        ErrorState(
          message: 'We could not load your expenses. Check your connection.',
          onRetry: () {},
        ),
        const SizedBox(height: 220, child: SkeletonList(itemCount: 3)),
      ],
    );
  }
}
