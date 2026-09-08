import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  Widget buildApp({
    String subject = 'fixture-title',
    bool reduceMotion = false,
    bool dark = false,
    double textScale = 1,
    Locale locale = const Locale('zh'),
  }) {
    final theme = dark ? AppTheme.dark() : AppTheme.light();
    return LocalizedTestApp(
      theme: theme,
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: ThreadDetailNativePalette.resolve(theme).background,
        appBar: AppBar(title: const Text('fixture-forum')),
        body: ThreadDetailLoading(subject: subject),
      ),
    );
  }

  testWidgets('unknown title stays a placeholder, not a fabricated subject', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(subject: ''));
    expect(
      find.byKey(const Key('thread-detail-first-post-summary')),
      findsNothing,
    );
    expect(find.byKey(const Key('thread-detail-loading')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps readable status without a ticker', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(buildApp(reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 300));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ThreadDetailLoading)),
      );
      expect(find.bySemanticsLabel(l10n.threadDetailLoading), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      final status = tester.widget<Text>(
        find.byKey(const Key('thread-detail-loading-label')),
      );
      expect(status.style!.color!.a, greaterThan(0));
    } finally {
      semantics.dispose();
    }
  });

  for (final dark in [false, true]) {
    testWidgets(
      'long title and large text fit a narrow ${dark ? 'dark' : 'light'} viewport',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(280, 400);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          buildApp(
            subject: List.filled(8, '這是一個很長的測試標題').join(),
            textScale: 2,
            dark: dark,
            locale: const Locale('zh', 'TW'),
          ),
        );
        final before = tester.getSize(
          find
              .descendant(
                of: find.byType(ThreadDetailLoading),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final after = tester.getSize(
          find
              .descendant(
                of: find.byType(ThreadDetailLoading),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(after, before);
        await tester.drag(
          find.byKey(const Key('thread-detail-loading')),
          const Offset(0, -1400),
        );
        await tester.pump();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ThreadDetailLoading)),
        );
        expect(
          find.text(l10n.threadDetailLoading).hitTestable(),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
