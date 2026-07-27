import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/localization/app_locale_resolution.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';

void main() {
  group('localeForAppLanguage', () {
    test('maps explicit language preferences to supported locales', () {
      expect(localeForAppLanguage(AppLanguage.system), isNull);
      expect(
        localeForAppLanguage(AppLanguage.simplifiedChinese),
        appSimplifiedLocale,
      );
      expect(
        localeForAppLanguage(AppLanguage.traditionalChinese),
        appTraditionalLocale,
      );
    });
  });

  group('resolveAppLocale', () {
    final cases = <String, List<Locale>?>{
      'simplified Chinese device': const [
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'CN',
        ),
      ],
      'traditional Taiwan device': const [
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
      ],
      'traditional Hong Kong device': const [
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'HK',
        ),
      ],
      'traditional Macau device': const [
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'MO',
        ),
      ],
      'traditional country without script': const [Locale('zh', 'TW')],
      'bare Chinese device': const [Locale('zh')],
      'unsupported device': const [Locale('en', 'US')],
      'unsupported first preference then traditional Chinese': const [
        Locale('en', 'US'),
        Locale('zh', 'TW'),
      ],
      'empty device list': const [],
      'missing device list': null,
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final expected = entry.key.contains('traditional')
            ? appTraditionalLocale
            : appSimplifiedLocale;
        expect(resolveAppLocale(entry.value), expected);
      });
    }
  });
}
