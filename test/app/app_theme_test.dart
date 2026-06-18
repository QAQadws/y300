import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/settings/app_appearance_settings_repository.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';
import 'package:y300/app/y300_app.dart';

void main() {
  test('AppTheme.light exposes the expected scaffold, app bar, and navigation bar colors', () {
    final theme = AppTheme.light();
    final expectedColorScheme = ColorScheme.fromSeed(
      seedColor: AppThemeTokens.seedColor,
      brightness: Brightness.light,
    );

    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppThemeTokens.scaffoldBackground);
    expect(theme.appBarTheme.backgroundColor, AppThemeTokens.appBarBackground);
    expect(theme.appBarTheme.foregroundColor, AppThemeTokens.appBarForeground);
    expect(
      theme.navigationBarTheme.backgroundColor,
      AppThemeTokens.navigationBarBackground,
    );
    expect(theme.colorScheme.primary, expectedColorScheme.primary);
  });

  test('AppTheme.dark exposes a valid dark Material theme', () {
    final theme = AppTheme.dark();

    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, isNot(AppThemeTokens.scaffoldBackground));
    expect(theme.appBarTheme.backgroundColor, isNot(AppThemeTokens.appBarBackground));
    expect(
      theme.navigationBarTheme.backgroundColor,
      isNot(AppThemeTokens.navigationBarBackground),
    );
  });

  testWidgets('Y300App wires AppTheme into MaterialApp with saved theme mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAppearanceSettingsRepositoryProvider.overrideWithValue(
            _FakeAppAppearanceSettingsRepository(
              settings: const AppAppearanceSettings(
                themePreference: AppThemePreference.dark,
              ),
            ),
          ),
        ],
        child: const Y300App(home: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = materialApp.theme!;

    expect(materialApp.themeMode, ThemeMode.dark);
    expect(theme.scaffoldBackgroundColor, AppThemeTokens.scaffoldBackground);
    expect(theme.appBarTheme.backgroundColor, AppThemeTokens.appBarBackground);
    expect(
      theme.navigationBarTheme.backgroundColor,
      AppThemeTokens.navigationBarBackground,
    );
    expect(materialApp.darkTheme!.colorScheme.brightness, Brightness.dark);
  });

  testWidgets('Y300App falls back to light while settings load', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAppearanceControllerProvider.overrideWith(
            () => _LoadingAppAppearanceController(),
          ),
        ],
        child: const Y300App(home: SizedBox.shrink()),
      ),
    );

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.light);
  });

  testWidgets('Y300App falls back to light when settings fail to load', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAppearanceControllerProvider.overrideWith(
            () => _FailingAppAppearanceController(),
          ),
        ],
        child: const Y300App(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.light);
  });
}

class _FakeAppAppearanceSettingsRepository
    implements AppAppearanceSettingsRepository {
  _FakeAppAppearanceSettingsRepository({
    required AppAppearanceSettings settings,
  }) : _settings = settings;

  AppAppearanceSettings _settings;

  @override
  Future<AppAppearanceSettings> load() async {
    return _settings;
  }

  @override
  Future<void> save(AppAppearanceSettings settings) async {
    _settings = settings;
  }
}

class _LoadingAppAppearanceController extends AppAppearanceController {
  @override
  Future<AppAppearanceSettings> build() {
    return Completer<AppAppearanceSettings>().future;
  }
}

class _FailingAppAppearanceController extends AppAppearanceController {
  @override
  Future<AppAppearanceSettings> build() {
    throw StateError('load failed');
  }
}
