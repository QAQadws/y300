import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/transient_feedback.dart';

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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '外观与文字',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const Key('appearance-settings-close-button'),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '主题',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preference in AppThemePreference.values)
                _AppearanceThemeChoice(
                  preference: preference,
                  selected: settings.themePreference == preference,
                  onPressed: () =>
                      _setThemePreference(context, ref, preference),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
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

  Future<void> _setThemePreference(
    BuildContext context,
    WidgetRef ref,
    AppThemePreference preference,
  ) async {
    try {
      await ref
          .read(appAppearanceControllerProvider.notifier)
          .setThemePreference(preference);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      showTransientSnackBar(context, '主题设置保存失败：$error');
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

class _AppearanceThemeChoice extends StatelessWidget {
  const _AppearanceThemeChoice({
    required this.preference,
    required this.selected,
    required this.onPressed,
  });

  final AppThemePreference preference;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: '${preference.displayLabel}主题',
      child: Tooltip(
        message: _description,
        child: OutlinedButton.icon(
          key: Key('appearance-theme-option-${preference.name}'),
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
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Icon(
              selected ? Icons.check : _icon,
              key: Key(
                selected
                    ? 'appearance-theme-selected-${preference.name}'
                    : 'appearance-theme-unselected-${preference.name}',
              ),
              size: 18,
            ),
          ),
          label: Text(preference.displayLabel),
        ),
      ),
    );
  }

  IconData get _icon {
    return switch (preference) {
      AppThemePreference.light => Icons.light_mode_outlined,
      AppThemePreference.dark => Icons.dark_mode_outlined,
      AppThemePreference.system => Icons.brightness_auto_outlined,
    };
  }

  String get _description {
    return switch (preference) {
      AppThemePreference.light => '保持浅色外观',
      AppThemePreference.dark => '使用深色外观',
      AppThemePreference.system => '跟随系统浅色或深色设置',
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
          selected ? Icons.check : Icons.language_outlined,
          key: Key(
            selected
                ? 'appearance-language-selected-${language.name}'
                : 'appearance-language-unselected-${language.name}',
          ),
          size: 18,
        ),
        label: Text(label),
      ),
    );
  }
}
