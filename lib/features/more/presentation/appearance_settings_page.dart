import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(appAppearanceControllerProvider);
    final settings =
        settingsState.asData?.value ?? AppAppearanceSettings.defaults();
    return Scaffold(
      appBar: AppBar(title: const Text('外观与文字')),
      body: ListView(
        children: [
          const _SettingsSectionHeader(title: '主题'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AppThemePreference>(
              key: const Key('appearance-theme-segmented-button'),
              segments: AppThemePreference.values
                  .map(
                    (preference) => ButtonSegment<AppThemePreference>(
                      value: preference,
                      label: Text(
                        preference.displayLabel,
                        key: Key(
                          'appearance-theme-option-${preference.name}',
                        ),
                      ),
                      tooltip: _themeDescription(preference),
                    ),
                  )
                  .toList(growable: false),
              selected: {settings.themePreference},
              onSelectionChanged: (selected) {
                if (selected.isEmpty) {
                  return;
                }
                _setThemePreference(context, ref, selected.first);
              },
              expandedInsets: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
    );
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('主题设置保存失败：$error')),
        );
    }
  }

  String _themeDescription(AppThemePreference preference) {
    return switch (preference) {
      AppThemePreference.light => '保持当前浅色暖色系外观',
      AppThemePreference.dark => '使用基础深色外观',
      AppThemePreference.system => '跟随系统浅色或深色设置',
    };
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
