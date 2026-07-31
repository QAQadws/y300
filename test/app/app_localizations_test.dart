import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/l10n/app_localizations.dart';

void main() {
  test('generated localizations expose both Chinese variants', () async {
    final simplified = await AppLocalizations.delegate.load(const Locale('zh'));
    final traditional = await AppLocalizations.delegate.load(
      const Locale('zh', 'TW'),
    );

    expect(simplified.appLanguageSectionTitle, '界面语言');
    expect(traditional.appLanguageSectionTitle, '介面語言');
    expect(simplified.appLanguageTraditionalChinese, '繁体中文');
    expect(traditional.appLanguageTraditionalChinese, '繁體中文');
  });
}
