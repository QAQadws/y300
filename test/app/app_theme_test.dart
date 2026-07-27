import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/settings/app_appearance_settings_repository.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_palette.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';
import 'package:y300/app/y300_app.dart';
import 'package:y300/features/forum/presentation/webview/theme/forum_webview_theme_palette_resolver.dart';

void main() {
  test(
    'AppTheme.light exposes the expected scaffold, app bar, and navigation bar colors',
    () {
      final theme = AppTheme.light();
      final palette = AppThemePalette.light();

      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, AppThemeTokens.scaffoldBackground);
      expect(
        theme.appBarTheme.backgroundColor,
        AppThemeTokens.appBarBackground,
      );
      expect(
        theme.appBarTheme.foregroundColor,
        AppThemeTokens.appBarForeground,
      );
      expect(
        theme.navigationBarTheme.backgroundColor,
        AppThemeTokens.navigationBarBackground,
      );
      _expectColorSchemeMatchesPalette(theme.colorScheme, palette);
      _expectComponentThemesMatchScheme(theme);
      expect(theme.extension<Y300ThemeExtension>(), isNotNull);
    },
  );

  test('AppTheme.dark exposes a valid dark Material theme', () {
    final theme = AppTheme.dark();
    final palette = AppThemePalette.dark();

    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.brightness, Brightness.dark);
    expect(
      theme.scaffoldBackgroundColor,
      isNot(AppThemeTokens.scaffoldBackground),
    );
    expect(
      theme.appBarTheme.backgroundColor,
      isNot(AppThemeTokens.appBarBackground),
    );
    expect(
      theme.navigationBarTheme.backgroundColor,
      isNot(AppThemeTokens.navigationBarBackground),
    );
    _expectColorSchemeMatchesPalette(theme.colorScheme, palette);
    _expectComponentThemesMatchScheme(theme);
    expect(theme.extension<Y300ThemeExtension>(), isNotNull);
  });

  test('AppThemePalette.light preserves the shell baseline tokens', () {
    final palette = AppThemePalette.light();

    expect(palette.brightness, Brightness.light);
    expect(palette.seedColor, AppThemeTokens.seedColor);
    expect(palette.scaffoldBackground, AppThemeTokens.scaffoldBackground);
    expect(palette.appBarBackground, AppThemeTokens.appBarBackground);
    expect(palette.appBarForeground, AppThemeTokens.appBarForeground);
    expect(
      palette.navigationBarBackground,
      AppThemeTokens.navigationBarBackground,
    );
  });

  test('AppThemePalette.dark exposes dark shell colors', () {
    final palette = AppThemePalette.dark();

    expect(palette.brightness, Brightness.dark);
    expect(
      palette.scaffoldBackground,
      isNot(AppThemeTokens.scaffoldBackground),
    );
    expect(palette.appBarBackground, isNot(AppThemeTokens.appBarBackground));
    expect(
      palette.navigationBarBackground,
      isNot(AppThemeTokens.navigationBarBackground),
    );
  });

  test('Y300ThemeExtension copyWith and lerp preserve semantic colors', () {
    final light = Y300ThemeExtension.light(AppThemePalette.light());
    final dark = Y300ThemeExtension.dark(AppThemePalette.dark());
    const replacement = Color(0xFF123456);

    final copied = light.copyWith(readerProgressTrackBackground: replacement);

    expect(copied.readerProgressTrackBackground, replacement);
    expect(copied.readerChromeBackground, light.readerChromeBackground);
    expect(
      light.lerp(dark, 0).readerChromeBackground,
      light.readerChromeBackground,
    );
    expect(
      light.lerp(dark, 1).readerChromeBackground,
      dark.readerChromeBackground,
    );
  });

  test(
    'Y300ThemeExtension exposes shelf semantic colors for light and dark themes',
    () {
      final light = Y300ThemeExtension.light(AppThemePalette.light());
      final dark = Y300ThemeExtension.dark(AppThemePalette.dark());

      expect(light.shelfCategoryBarBackground, isNot(Colors.transparent));
      expect(light.shelfCategorySelectedBackground, isNot(Colors.transparent));
      expect(light.coverPlaceholderBackground, isNot(Colors.transparent));
      expect(dark.shelfCategoryBarBackground, isNot(Colors.white));
      expect(dark.coverPlaceholderBackground, isNot(Colors.white));
    },
  );

  test('AppTheme.dark component themes avoid light default surfaces', () {
    final theme = AppTheme.dark();
    final scheme = theme.colorScheme;

    expect(theme.popupMenuTheme.color, scheme.surfaceContainer);
    expect(
      theme.bottomSheetTheme.modalBackgroundColor,
      scheme.surfaceContainer,
    );
    expect(
      theme.sliderTheme.inactiveTrackColor,
      scheme.surfaceContainerHighest,
    );
    expect(theme.sliderTheme.trackHeight, 4);
    expect(theme.sliderTheme.overlayColor, Colors.transparent);
    expect(theme.sliderTheme.overlayShape, SliderComponentShape.noOverlay);
    expect(theme.sliderTheme.showValueIndicator, ShowValueIndicator.never);
    expect(theme.inputDecorationTheme.fillColor, scheme.surfaceContainer);
    expect(theme.popupMenuTheme.color, isNot(Colors.white));
    expect(theme.bottomSheetTheme.modalBackgroundColor, isNot(Colors.white));
  });

  test('AppTheme light and dark can resolve WebView palettes', () {
    const resolver = ForumWebViewThemePaletteResolver();

    final light = resolver.resolve(AppTheme.light());
    final dark = resolver.resolve(AppTheme.dark());

    expect(light.brightness, Brightness.light);
    expect(light.colorScheme, 'light');
    expect(light.pageBackground, AppThemeTokens.scaffoldBackground);
    expect(dark.brightness, Brightness.dark);
    expect(dark.colorScheme, 'dark');
    expect(dark.pageBackground, isNot(AppThemeTokens.scaffoldBackground));
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
        child: const Y300App(
          home: SizedBox.shrink(),
          enableAppUpdatePrompt: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = materialApp.theme!;

    expect(materialApp.themeMode, ThemeMode.dark);
    expect(
      materialApp.supportedLocales,
      const <Locale>[Locale('zh', 'CN'), Locale('zh', 'TW')],
    );
    expect(theme.scaffoldBackgroundColor, AppThemeTokens.scaffoldBackground);
    expect(theme.appBarTheme.backgroundColor, AppThemeTokens.appBarBackground);
    expect(
      theme.navigationBarTheme.backgroundColor,
      AppThemeTokens.navigationBarBackground,
    );
    expect(materialApp.darkTheme!.colorScheme.brightness, Brightness.dark);
    expect(materialApp.darkTheme!.extension<Y300ThemeExtension>(), isNotNull);
  });

  testWidgets('AppTheme.dark builds common Material controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              PopupMenuButton<String>(
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(value: 'refresh', child: Text('刷新')),
                ],
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(value: 0, label: Text('A')),
                  ButtonSegment<int>(value: 1, label: Text('B')),
                ],
                selected: const {0},
                onSelectionChanged: (_) {},
              ),
              Slider(value: 0.5, onChanged: (_) {}),
              const TextField(decoration: InputDecoration(labelText: '搜索')),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Y300App falls back to light while settings load', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAppearanceControllerProvider.overrideWith(
            () => _LoadingAppAppearanceController(),
          ),
        ],
        child: const Y300App(
          home: SizedBox.shrink(),
          enableAppUpdatePrompt: false,
        ),
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
        child: const Y300App(
          home: SizedBox.shrink(),
          enableAppUpdatePrompt: false,
        ),
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

void _expectColorSchemeMatchesPalette(
  ColorScheme scheme,
  AppThemePalette palette,
) {
  expect(scheme.brightness, palette.brightness);
  expect(scheme.primary, palette.primary);
  expect(scheme.onPrimary, palette.onPrimary);
  expect(scheme.surface, palette.surface);
  expect(scheme.onSurface, palette.onSurface);
  expect(scheme.surfaceContainerLowest, palette.surfaceContainerLowest);
  expect(scheme.surfaceContainer, palette.surfaceContainer);
  expect(scheme.surfaceContainerHighest, palette.surfaceContainerHighest);
  expect(scheme.onSurfaceVariant, palette.onSurfaceVariant);
  expect(scheme.outlineVariant, palette.outlineVariant);
  expect(scheme.secondaryContainer, palette.secondaryContainer);
  expect(scheme.onSecondaryContainer, palette.onSecondaryContainer);
}

void _expectComponentThemesMatchScheme(ThemeData theme) {
  final scheme = theme.colorScheme;

  expect(
    theme.menuTheme.style?.backgroundColor?.resolve(const <WidgetState>{}),
    scheme.surfaceContainer,
  );
  expect(
    theme.dropdownMenuTheme.menuStyle?.backgroundColor?.resolve(
      const <WidgetState>{},
    ),
    scheme.surfaceContainer,
  );
  expect(theme.popupMenuTheme.color, scheme.surfaceContainer);
  expect(theme.popupMenuTheme.textStyle?.color, scheme.onSurface);
  expect(theme.bottomSheetTheme.backgroundColor, scheme.surfaceContainer);
  expect(theme.bottomSheetTheme.modalBackgroundColor, scheme.surfaceContainer);
  expect(theme.dialogTheme.backgroundColor, scheme.surfaceContainer);
  expect(theme.snackBarTheme.backgroundColor, scheme.inverseSurface);
  expect(
    theme.segmentedButtonTheme.style?.backgroundColor?.resolve(
      const <WidgetState>{WidgetState.selected},
    ),
    scheme.secondaryContainer,
  );
  expect(theme.sliderTheme.activeTrackColor, scheme.primary);
  expect(theme.sliderTheme.thumbColor, scheme.primary);
  expect(theme.sliderTheme.inactiveTrackColor, scheme.surfaceContainerHighest);
  expect(theme.sliderTheme.trackHeight, 4);
  expect(theme.sliderTheme.overlayColor, Colors.transparent);
  expect(theme.sliderTheme.overlayShape, SliderComponentShape.noOverlay);
  expect(theme.sliderTheme.showValueIndicator, ShowValueIndicator.never);
  expect(theme.listTileTheme.textColor, scheme.onSurface);
  expect(theme.dividerTheme.color, scheme.outlineVariant);
  expect(theme.inputDecorationTheme.fillColor, scheme.surfaceContainer);
  expect(theme.chipTheme.backgroundColor, scheme.surfaceContainer);
  expect(theme.cardTheme.color, scheme.surfaceContainer);
}
