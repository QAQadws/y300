import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_palette.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';
import 'package:y300/features/more/presentation/more_text_resolver.dart';

class AppearanceSettingsSheet extends ConsumerWidget {
  const AppearanceSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(appAppearanceControllerProvider);
    final settings =
        settingsState.asData?.value ?? AppAppearanceSettings.defaults();
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: ListView(
        key: const Key('appearance-settings-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(
            l10n.moreColorThemeSectionTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _AppearanceOptionStrip(
            scrollViewKey: const Key('appearance-theme-family-options-scroll'),
            children: [
              for (final family in AppThemeFamily.values)
                _AppearanceThemeFamilyChoice(
                  family: family,
                  selected: settings.themeFamily == family,
                  onPressed: () => _setThemeFamily(context, ref, family),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            l10n.moreAppearanceModeSectionTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _AppearanceOptionStrip(
            scrollViewKey: const Key('appearance-brightness-options-scroll'),
            children: [
              for (final preference in AppBrightnessPreference.values)
                _AppearanceBrightnessChoice(
                  preference: preference,
                  selected: settings.brightnessPreference == preference,
                  onPressed: () =>
                      _setBrightnessPreference(context, ref, preference),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            l10n.appLanguageSectionTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _AppearanceOptionStrip(
            scrollViewKey: const Key('appearance-language-options-scroll'),
            children: [
              for (final language in AppLanguage.values)
                _AppearanceLanguageChoice(
                  language: language,
                  label: _languageLabel(l10n, language),
                  selected: settings.languagePreference == language,
                  onPressed: () =>
                      _setLanguagePreference(context, ref, language),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _languageLabel(AppLocalizations l10n, AppLanguage language) {
    return switch (language) {
      AppLanguage.system => l10n.appLanguageSystem,
      AppLanguage.simplifiedChinese => l10n.appLanguageSimplifiedChinese,
      AppLanguage.traditionalChinese => l10n.appLanguageTraditionalChinese,
    };
  }

  Future<void> _setThemeFamily(
    BuildContext context,
    WidgetRef ref,
    AppThemeFamily family,
  ) async {
    try {
      await ref
          .read(appAppearanceControllerProvider.notifier)
          .setThemeFamily(family);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      showTransientSnackBar(
        context,
        AppLocalizations.of(context).moreThemeSaveFailed('$error'),
      );
    }
  }

  Future<void> _setBrightnessPreference(
    BuildContext context,
    WidgetRef ref,
    AppBrightnessPreference preference,
  ) async {
    try {
      await ref
          .read(appAppearanceControllerProvider.notifier)
          .setBrightnessPreference(preference);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      showTransientSnackBar(
        context,
        AppLocalizations.of(context).moreThemeSaveFailed('$error'),
      );
    }
  }

  Future<void> _setLanguagePreference(
    BuildContext context,
    WidgetRef ref,
    AppLanguage language,
  ) async {
    try {
      await ref
          .read(appAppearanceControllerProvider.notifier)
          .setLanguagePreference(language);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context);
      showTransientSnackBar(context, l10n.appLanguageSaveFailed('$error'));
    }
  }
}

class _AppearanceOptionStrip extends StatelessWidget {
  const _AppearanceOptionStrip({
    required this.scrollViewKey,
    required this.children,
  });

  final Key scrollViewKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: scrollViewKey,
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _AppearanceThemeFamilyChoice extends StatelessWidget {
  const _AppearanceThemeFamilyChoice({
    required this.family,
    required this.selected,
    required this.onPressed,
  });

  final AppThemeFamily family;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = MoreTextResolver.themeFamilyLabel(l10n, family);
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label${l10n.moreColorThemeSectionTitle}',
      child: Tooltip(
        message: MoreTextResolver.themeFamilyDescription(l10n, family),
        child: OutlinedButton(
          key: Key('appearance-theme-family-${family.name}'),
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            backgroundColor: selected ? scheme.primaryContainer : null,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(
              color: selected ? Colors.transparent : scheme.outlineVariant,
              width: selected ? 0 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThemeFamilySwatch(family: family),
              const SizedBox(width: 9),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeFamilySwatch extends StatelessWidget {
  const _ThemeFamilySwatch({required this.family});

  final AppThemeFamily family;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemePalette.resolve(
      family,
      Theme.of(context).brightness,
    );
    return Container(
      key: Key('appearance-theme-family-swatch-${family.name}'),
      width: 30,
      height: 18,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              key: Key('appearance-theme-family-swatch-${family.name}-primary'),
              color: palette.primary,
            ),
          ),
          Expanded(
            child: ColoredBox(
              key: Key('appearance-theme-family-swatch-${family.name}-page'),
              color: palette.surfaceContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceBrightnessChoice extends StatelessWidget {
  const _AppearanceBrightnessChoice({
    required this.preference,
    required this.selected,
    required this.onPressed,
  });

  final AppBrightnessPreference preference;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final label = MoreTextResolver.brightnessLabel(l10n, preference);

    return Semantics(
      button: true,
      selected: selected,
      label: '$label${l10n.moreAppearanceModeSectionTitle}',
      child: Tooltip(
        message: MoreTextResolver.brightnessDescription(l10n, preference),
        child: OutlinedButton.icon(
          key: Key('appearance-brightness-option-${preference.name}'),
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground,
            backgroundColor: selected ? scheme.primaryContainer : null,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(
              color: selected ? Colors.transparent : scheme.outlineVariant,
              width: selected ? 0 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          icon: Icon(
            _icon,
            key: Key('appearance-brightness-icon-${preference.name}'),
            size: 18,
          ),
          label: Text(label, maxLines: 1, softWrap: false),
        ),
      ),
    );
  }

  IconData get _icon {
    return switch (preference) {
      AppBrightnessPreference.light => Icons.light_mode_outlined,
      AppBrightnessPreference.dark => Icons.dark_mode_outlined,
      AppBrightnessPreference.system => Icons.brightness_auto_outlined,
    };
  }
}

class _AppearanceLanguageChoice extends StatelessWidget {
  const _AppearanceLanguageChoice({
    required this.language,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final AppLanguage language;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: OutlinedButton.icon(
        key: Key('appearance-language-option-${language.name}'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: selected ? scheme.primaryContainer : null,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(
            color: selected ? Colors.transparent : scheme.outlineVariant,
            width: selected ? 0 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        icon: Icon(
          Icons.language_outlined,
          key: Key('appearance-language-icon-${language.name}'),
          size: 18,
        ),
        label: Text(label, maxLines: 1, softWrap: false),
      ),
    );
  }
}
