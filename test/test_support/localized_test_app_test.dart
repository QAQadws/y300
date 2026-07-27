import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'localized_test_app.dart';

void main() {
  testWidgets('LocalizedTestApp provides the shared locale contract', (
    tester,
  ) async {
    await tester.pumpWidget(const LocalizedTestApp(home: SizedBox.shrink()));

    final app = tester.widget<LocalizedTestApp>(find.byType(LocalizedTestApp));
    expect(app.supportedLocales, AppLocalizations.supportedLocales);
    expect(app.locale, const Locale('zh'));
    expect(
      app.localizationsDelegates,
      containsAll(<LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ]),
    );
  });
}
