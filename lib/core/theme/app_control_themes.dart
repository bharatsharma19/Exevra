part of 'app_theme.dart';

/// Shared state-layer and focus helpers, and the themes of the interactive
/// controls (buttons, segments, toggles). Split out of [AppTheme._build].
class _Controls {
  _Controls(this.p, TextTheme text)
    : buttonText = text.labelLarge!.copyWith(fontSize: 16),
      text = text,
      focusRing = AppTheme.focusRingSide(p),
      focusBorder = AppTheme.focusBorderSide(p);

  final AppPalette p;
  final TextTheme text;

  static const buttonShape = RoundedRectangleBorder(
    borderRadius: AppRadius.mdAll,
  );
  static const buttonPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
    vertical: 14,
  );
  static const minButton = Size(AppSizes.minTapTarget, AppSizes.minTapTarget);

  final TextStyle buttonText;

  // Keyboard and D-pad focus (WCAG 2.4.7): Material's focus overlay is a
  // faint tint, so the themed components get a solid indicator in
  // AppPalette.focusRing (at least 3:1 against the page, see
  // contrast_test). Filled controls get a ring with a gap ([focusRingSide]),
  // outlined controls a thicker border ([focusBorderSide]), toggles
  // (switch, checkbox, radio) a solid halo with their marks redrawn in
  // textOnAccent on top of it, segments an underline, and snackbar actions
  // an inverted fill. Material only reports the focused state while the
  // keyboard drives focus, so touch users never see it.
  //
  // Not covered by the theme: InkWell-based widgets (ListTile, InkWell,
  // the rows of Flutter's licence page) only get the [ThemeData.focusColor]
  // tint, which cannot reach 3:1 against the page without pushing
  // textSecondary on it under 4.5:1. Kit widgets built on them (AppListTile,
  // AppCard, AppNavigationDestination) add a FocusOutline; screens should
  // use those instead of the raw widgets. Screens built by Flutter (the
  // licence page) are wrapped in a FocusRingOverlay.
  final BorderSide focusRing;
  final BorderSide focusBorder;

  bool focused(Set<WidgetState> states) =>
      states.contains(WidgetState.focused) &&
      !states.contains(WidgetState.disabled);

  late final WidgetStateProperty<BorderSide?> focusSide =
      WidgetStateProperty.resolveWith<BorderSide?>(
        (states) => focused(states) ? focusRing : null,
      );

  // Radial focus halo of switches, checkboxes and radios. Pressed and
  // hovered overlays keep the Material defaults (null falls through).
  late final WidgetStateProperty<Color?> toggleOverlay =
      WidgetStateProperty.resolveWith<Color?>(
        (states) => focused(states) ? p.focusRing : null,
      );

  // State layer of accent-filled controls. Material's default is the
  // foreground colour, which pulls the fill toward the label: white text on
  // the light accent fell to 4.4:1 when focused and 3.7:1 when pressed (the
  // highlight and splash stack). onAccentContainer moves the fill away from
  // the label in both themes (darker under white text, lighter under the
  // dark text of the dark theme).
  Color get accentOverlay => p.onAccentContainer;

  // Accent text of text and outlined buttons. Any state layer behind it
  // takes the light accent under 4.5:1 (4.5 on the page, 4.9 on
  // surfaceVariant at rest), so while hovered, focused or pressed the label
  // deepens to onAccentContainer.
  late final WidgetStateProperty<Color?> accentText =
      WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.disabled)
            ? p.textTertiary
            : states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.pressed)
            ? p.onAccentContainer
            : p.accent,
      );

  ElevatedButtonThemeData get elevatedButtonTheme {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.textOnAccent,
        overlayColor: accentOverlay,
        disabledBackgroundColor: p.surfaceVariant,
        disabledForegroundColor: p.textTertiary,
        elevation: 0,
        shadowColor: Colors.transparent,
        minimumSize: minButton,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
        tapTargetSize: MaterialTapTargetSize.padded,
      ).copyWith(side: focusSide),
    );
  }

  FilledButtonThemeData get filledButtonTheme {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        overlayColor: accentOverlay,
        disabledBackgroundColor: p.surfaceVariant,
        disabledForegroundColor: p.textTertiary,
        minimumSize: minButton,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: buttonText,
        tapTargetSize: MaterialTapTargetSize.padded,
      ).copyWith(side: focusSide),
    );
  }

  OutlinedButtonThemeData get outlinedButtonTheme {
    return OutlinedButtonThemeData(
      style:
          ButtonStyle(
            foregroundColor: accentText,
            side: WidgetStateBorderSide.resolveWith(
              (states) => focused(states)
                  ? focusBorder
                  : BorderSide(
                      color: states.contains(WidgetState.disabled)
                          ? p.outlineVariant
                          : p.accent,
                      width: 1.2,
                    ),
            ),
          ).merge(
            // Its foregroundColor only seeds the accent state layer; the
            // label colour is accentText above.
            OutlinedButton.styleFrom(
              foregroundColor: p.accent,
              disabledForegroundColor: p.textTertiary,
              minimumSize: minButton,
              padding: buttonPadding,
              shape: buttonShape,
              textStyle: buttonText,
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
    );
  }

  TextButtonThemeData get textButtonTheme {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        disabledForegroundColor: p.textTertiary,
        minimumSize: minButton,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: buttonShape,
        textStyle: text.labelLarge,
        tapTargetSize: MaterialTapTargetSize.padded,
      ).copyWith(side: focusSide, foregroundColor: accentText),
    );
  }

  IconButtonThemeData get iconButtonTheme {
    return IconButtonThemeData(
      // A selected (toggled) icon button gets a filled accent container with
      // an accent outline, so the state shows even without a selectedIcon.
      // Otherwise the foreground is left to the variant: the theme style
      // applies to IconButton.filled, .filledTonal and .outlined too, and a
      // fixed textSecondary would put the send button's icon on the accent
      // fill at 1.4:1. The scheme's variant defaults (onSurfaceVariant =
      // textSecondary for the standard button, onPrimary on the fill) all
      // meet 3:1.
      style:
          IconButton.styleFrom(
            minimumSize: minButton,
            tapTargetSize: MaterialTapTargetSize.padded,
          ).copyWith(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? p.textTertiary
                  : states.contains(WidgetState.selected)
                  ? p.onAccentContainer
                  : null,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => !states.contains(WidgetState.selected)
                  ? null
                  : states.contains(WidgetState.disabled)
                  ? p.surfaceVariant
                  : p.accentContainer,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => focused(states)
                  ? focusRing
                  : states.contains(WidgetState.selected) &&
                        !states.contains(WidgetState.disabled)
                  ? BorderSide(color: p.accent)
                  : null,
            ),
          ),
    );
  }

  SegmentedButtonThemeData get segmentedButtonTheme {
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(minButton),
        // Segments cannot draw their own ring (SegmentedButton forces a
        // plain shape on them), and a solid focus fill would look more
        // selected than the selected segment. So a focused segment keeps
        // its fill and colours, its label gets a thick focusRing underline,
        // and the group border turns into the focus colour.
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.accentContainer
              : p.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? p.textTertiary
              : states.contains(WidgetState.selected)
              ? p.onAccentContainer
              : p.textPrimary,
        ),
        textStyle: WidgetStateProperty.resolveWith(
          (states) => focused(states)
              ? text.labelLarge!.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: p.focusRing,
                  decorationThickness: 3,
                )
              : text.labelLarge,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => focused(states)
              ? BorderSide(color: p.focusRing, width: AppTheme.focusRingWidth)
              : BorderSide(color: p.outline),
        ),
      ),
    );
  }

  SwitchThemeData get switchTheme {
    return SwitchThemeData(
      overlayColor: toggleOverlay,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return p.outlineVariant;
        if (focused(states)) return p.textOnAccent;
        return states.contains(WidgetState.selected)
            ? p.textOnAccent
            : p.outlineStrong;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return p.surfaceVariant;
        return states.contains(WidgetState.selected)
            ? p.accent
            : p.surfaceVariant;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (focused(states)) {
          // On the accent track the outline must contrast with the track.
          return states.contains(WidgetState.selected)
              ? p.textOnAccent
              : p.focusRing;
        }
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return states.contains(WidgetState.disabled)
            ? p.outlineVariant
            : p.outline;
      }),
    );
  }

  CheckboxThemeData get checkboxTheme {
    return CheckboxThemeData(
      overlayColor: toggleOverlay,
      // While focused the box sits on the focusRing halo, so it is redrawn
      // in textOnAccent (at least 4.5:1 against the halo).
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? (states.contains(WidgetState.disabled)
                  ? p.outlineVariant
                  : focused(states)
                  ? p.textOnAccent
                  : p.accent)
            : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.resolveWith(
        (states) => focused(states) ? p.focusRing : p.textOnAccent,
      ),
      // A WidgetStateBorderSide is also resolved for selected boxes; null
      // keeps the default (no border) there.
      side: WidgetStateBorderSide.resolveWith(
        (states) => focused(states) && !states.contains(WidgetState.selected)
            ? BorderSide(color: p.textOnAccent, width: 2)
            : states.contains(WidgetState.selected)
            ? null
            : BorderSide(color: p.outline, width: 2),
      ),
    );
  }

  RadioThemeData get radioTheme {
    return RadioThemeData(
      overlayColor: toggleOverlay,
      fillColor: WidgetStateProperty.resolveWith(
        (states) => focused(states)
            ? p.textOnAccent
            : states.contains(WidgetState.selected)
            ? p.accent
            : p.outline,
      ),
    );
  }
}
