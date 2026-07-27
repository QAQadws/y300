import 'package:flutter/material.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';

const appSimplifiedLocale = Locale('zh');
const appTraditionalLocale = Locale('zh', 'TW');

Locale? localeForAppLanguage(AppLanguage language) {
  return switch (language) {
    AppLanguage.system => null,
    AppLanguage.simplifiedChinese => appSimplifiedLocale,
    AppLanguage.traditionalChinese => appTraditionalLocale,
  };
}

Locale resolveAppLocale(List<Locale>? deviceLocales) {
  for (final locale in deviceLocales ?? const <Locale>[]) {
    if (locale.languageCode != 'zh') {
      continue;
    }
    if (locale.scriptCode == 'Hant' ||
        const {'TW', 'HK', 'MO'}.contains(locale.countryCode)) {
      return appTraditionalLocale;
    }
    return appSimplifiedLocale;
  }
  return appSimplifiedLocale;
}
