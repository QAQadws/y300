import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_status_banner.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('uses localized retry fallback in both locales', (tester) async {
    Widget build(Locale locale) {
      return LocalizedTestApp(
        locale: locale,
        home: Scaffold(
          body: ComposerStatusBanner.error(
            text: 'raw diagnostic',
            onRetry: () {},
          ),
        ),
      );
    }

    await tester.pumpWidget(build(const Locale('zh')));
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('raw diagnostic'), findsOneWidget);

    await tester.pumpWidget(build(const Locale('zh', 'TW')));
    await tester.pump();
    expect(find.text('重試'), findsOneWidget);
    expect(find.text('raw diagnostic'), findsOneWidget);
  });
}
