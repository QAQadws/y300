import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/localization/app_locale_resolution.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/startup/app_bootstrap.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_palette.dart';
import 'package:y300/app/y300_app.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/core/preferences/preferences_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('saved appearance is ready before the first visible home build', (
    tester,
  ) async {
    final ready = Completer<void>();
    final store = _Store(_savedAppearance())..readBarrier = ready.future;
    final frames = <_AppearanceFrame>[];
    ProviderContainer? mountedContainer;
    var completed = false;
    final preparing =
        bootstrapApplication(
          preferencesStore: store,
          child: _app(
            frames,
            onContainer: (container) => mountedContainer = container,
          ),
        ).then((app) {
          completed = true;
          return app;
        });

    await tester.pump();
    expect(completed, isFalse);
    expect(frames, isEmpty);

    ready.complete();
    final app = await preparing;
    // Preparing appearance must not wait for or read unrelated business data.
    expect(store.reads.toSet(), {
      PreferenceKeys.appThemeFamily.name,
      PreferenceKeys.appThemePreference.name,
      PreferenceKeys.appLanguagePreference.name,
    });
    expect(store.writes, isEmpty);
    await tester.pumpWidget(app);
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);
    expect(materialApp.locale, appTraditionalLocale);
    await tester.pumpAndSettle();

    expect(frames, isNotEmpty);
    for (final frame in frames) {
      expect(frame.brightness, Brightness.dark);
      expect(
        frame.scaffoldColor,
        AppThemePalette.resolve(
          AppThemeFamily.moonWhite,
          Brightness.dark,
        ).scaffoldBackground,
      );
      expect(frame.locale, appTraditionalLocale);
    }
    expect(mountedContainer!.read(preferencesStoreProvider), same(store));
    expect(
      mountedContainer!.read(appAppearanceControllerProvider).hasValue,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('saved settings remain editable and reload from the same store', (
    tester,
  ) async {
    final store = _Store(_savedAppearance());
    ProviderContainer? container;
    final frames = <_AppearanceFrame>[];
    final app = await bootstrapApplication(
      preferencesStore: store,
      child: _app(frames, onContainer: (value) => container = value),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final repository = container!.read(appAppearanceSettingsRepositoryProvider);
    final controller = container!.read(
      appAppearanceControllerProvider.notifier,
    );

    await controller.setThemeFamily(AppThemeFamily.plumPurple);
    await controller.setBrightnessPreference(AppBrightnessPreference.light);
    await controller.setLanguagePreference(AppLanguage.simplifiedChinese);
    container!.invalidate(appAppearanceControllerProvider);
    final loaded = await container!.read(
      appAppearanceControllerProvider.future,
    );
    await tester.pumpAndSettle();

    expect(loaded.themeFamily, AppThemeFamily.plumPurple);
    expect(loaded.brightnessPreference, AppBrightnessPreference.light);
    expect(loaded.languagePreference, AppLanguage.simplifiedChinese);
    expect(
      container!.read(appAppearanceSettingsRepositoryProvider),
      same(repository),
    );
    expect(container!.read(preferencesStoreProvider), same(store));
    expect(store.values[PreferenceKeys.appThemeFamily.name], 'plumPurple');
    expect(store.values[PreferenceKeys.appThemePreference.name], 'light');
    expect(
      frames.last.scaffoldColor,
      AppThemePalette.resolve(
        AppThemeFamily.plumPurple,
        Brightness.light,
      ).scaffoldBackground,
    );
    expect(frames.last.locale, appSimplifiedLocale);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'system appearance uses the initial $brightness platform frame',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final store = _Store({
          ..._savedAppearance(),
          PreferenceKeys.appThemePreference.name: 'system',
        });
        final frames = <_AppearanceFrame>[];
        final app = await bootstrapApplication(
          preferencesStore: store,
          child: _app(frames),
        );
        await tester.pumpWidget(app);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.system,
        );
        await tester.pumpAndSettle();

        expect(frames, isNotEmpty);
        expect(frames.first.brightness, brightness);
        expect(
          frames.first.scaffoldColor,
          AppThemePalette.resolve(
            AppThemeFamily.moonWhite,
            brightness,
          ).scaffoldBackground,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('an empty store starts with defaults without writing them', (
    tester,
  ) async {
    final store = _Store({});
    final frames = <_AppearanceFrame>[];
    final app = await bootstrapApplication(
      preferencesStore: store,
      child: _app(frames),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(frames.first.brightness, Brightness.light);
    expect(
      frames.first.scaffoldColor,
      AppThemePalette.resolve(
        AppThemeFamily.warmPaper,
        Brightness.light,
      ).scaffoldBackground,
    );
    expect(store.writes, isEmpty);
    expect(store.values, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed appearance read still mounts the default app', (
    tester,
  ) async {
    final store = _Store({})..failReads = true;
    final frames = <_AppearanceFrame>[];
    final app = await bootstrapApplication(
      preferencesStore: store,
      child: _app(frames),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(frames, isNotEmpty);
    expect(frames.first.brightness, Brightness.light);
    expect(store.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('replacing or unmounting the app releases its provider owner', (
    tester,
  ) async {
    var disposed = 0;
    final lifetime = Provider<Object>((ref) {
      ref.onDispose(() => disposed++);
      return Object();
    });
    final containers = <ProviderContainer>[];
    Widget child() => Consumer(
      builder: (context, ref, _) {
        ref.watch(lifetime);
        final container = ProviderScope.containerOf(context);
        if (!containers.contains(container)) containers.add(container);
        return const SizedBox.shrink();
      },
    );
    final first = await bootstrapApplication(
      preferencesStore: _Store(_savedAppearance()),
      child: child(),
    );
    await tester.pumpWidget(first);
    expect(disposed, 0);

    final second = await bootstrapApplication(
      preferencesStore: _Store({}),
      child: child(),
    );
    await tester.pumpWidget(second);
    expect(containers, hasLength(2));
    expect(disposed, 1);
    expect(
      () => containers.first.read(preferencesStoreProvider),
      throwsStateError,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposed, 2);
    expect(
      () => containers.last.read(preferencesStoreProvider),
      throwsStateError,
    );
  });
}

Map<String, Object> _savedAppearance() => {
  PreferenceKeys.appThemeFamily.name: 'moonWhite',
  PreferenceKeys.appThemePreference.name: 'dark',
  PreferenceKeys.appLanguagePreference.name: 'traditionalChinese',
};

Widget _app(
  List<_AppearanceFrame> frames, {
  ValueChanged<ProviderContainer>? onContainer,
}) => Y300App(
  enableAppUpdatePrompt: false,
  home: Builder(
    builder: (context) {
      onContainer?.call(ProviderScope.containerOf(context));
      frames.add(
        _AppearanceFrame(
          brightness: Theme.of(context).brightness,
          scaffoldColor: Theme.of(context).scaffoldBackgroundColor,
          locale: Localizations.localeOf(context),
        ),
      );
      return const Scaffold();
    },
  ),
);

final class _AppearanceFrame {
  const _AppearanceFrame({
    required this.brightness,
    required this.scaffoldColor,
    required this.locale,
  });

  final Brightness brightness;
  final Color scaffoldColor;
  final Locale locale;
}

final class _Store implements PreferencesStore {
  _Store(Map<String, Object> values) : values = Map.of(values);

  final Map<String, Object> values;
  final reads = <String>[];
  final writes = <String>[];
  Future<void>? readBarrier;
  bool failReads = false;

  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async {
    reads.add(key.name);
    await readBarrier;
    if (failReads) throw StateError('appearance storage unavailable');
    final value = values[key.name];
    return value is T ? value : null;
  }

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async =>
      values.containsKey(key.name);

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    writes.add(key.name);
    values[key.name] = value;
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async {
    values.remove(key.name);
  }
}
