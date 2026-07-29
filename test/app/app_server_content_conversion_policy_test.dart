import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/localization/app_locale_resolution.dart';
import 'package:y300/app/localization/app_server_content_conversion_policy.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';

void main() {
  group('AppServerContentConversionPolicy', () {
    const policy = AppServerContentConversionPolicy();

    test('keeps server content raw when app language follows the system', () {
      expect(policy.resolve(AppLanguage.system), TextConversionMode.none);
    });

    test('maps explicit simplified Chinese to simplified conversion', () {
      expect(
        policy.resolve(AppLanguage.simplifiedChinese),
        TextConversionMode.toSimplified,
      );
    });

    test('maps explicit traditional Chinese to traditional conversion', () {
      expect(
        policy.resolve(AppLanguage.traditionalChinese),
        TextConversionMode.toTraditional,
      );
    });
  });

  group('appServerContentConversionModeProvider', () {
    test('returns none while appearance settings are loading', () {
      final container = ProviderContainer(
        overrides: [
          appAppearanceControllerProvider.overrideWith(
            () => _LoadingAppAppearanceController(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appServerContentConversionModeProvider),
        TextConversionMode.none,
      );
    });

    test('returns none when appearance settings fail to load', () async {
      final container = ProviderContainer(
        overrides: [
          appAppearanceControllerProvider.overrideWith(
            () => _FailingAppAppearanceController(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appServerContentConversionModeProvider),
        TextConversionMode.none,
      );
      await expectLater(
        container.read(appAppearanceControllerProvider.future),
        throwsStateError,
      );
      expect(
        container.read(appServerContentConversionModeProvider),
        TextConversionMode.none,
      );
    });

    test(
      'does not infer B-class conversion from a traditional device locale',
      () async {
        expect(
          resolveAppLocale(const [Locale('zh', 'TW')]),
          appTraditionalLocale,
        );
        final container = ProviderContainer(
          overrides: [
            appAppearanceControllerProvider.overrideWith(
              () => _FixedAppAppearanceController(
                const AppAppearanceSettings(
                  themePreference: AppThemePreference.light,
                  languagePreference: AppLanguage.system,
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(appAppearanceControllerProvider.future);

        expect(
          container.read(appServerContentConversionModeProvider),
          TextConversionMode.none,
        );
      },
    );

    test('exposes the explicit simplified conversion mode', () async {
      final container = _containerFor(AppLanguage.simplifiedChinese);
      addTearDown(container.dispose);

      await container.read(appAppearanceControllerProvider.future);

      expect(
        container.read(appServerContentConversionModeProvider),
        TextConversionMode.toSimplified,
      );
    });

    test('exposes the explicit traditional conversion mode', () async {
      final container = _containerFor(AppLanguage.traditionalChinese);
      addTearDown(container.dispose);

      await container.read(appAppearanceControllerProvider.future);

      expect(
        container.read(appServerContentConversionModeProvider),
        TextConversionMode.toTraditional,
      );
    });
  });
}

ProviderContainer _containerFor(AppLanguage language) {
  return ProviderContainer(
    overrides: [
      appAppearanceControllerProvider.overrideWith(
        () => _FixedAppAppearanceController(
          AppAppearanceSettings(
            themePreference: AppThemePreference.light,
            languagePreference: language,
          ),
        ),
      ),
    ],
  );
}

class _FixedAppAppearanceController extends AppAppearanceController {
  _FixedAppAppearanceController(this.settings);

  final AppAppearanceSettings settings;

  @override
  Future<AppAppearanceSettings> build() async => settings;
}

class _LoadingAppAppearanceController extends AppAppearanceController {
  @override
  Future<AppAppearanceSettings> build() =>
      Completer<AppAppearanceSettings>().future;
}

class _FailingAppAppearanceController extends AppAppearanceController {
  @override
  Future<AppAppearanceSettings> build() async {
    throw StateError('settings failed');
  }
}
