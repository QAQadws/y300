import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'reader controls use Traditional Chinese fallbacks and semantics',
    (tester) async {
      final l10n = AppLocalizationsZhTw();
      await tester.pumpWidget(
        LocalizedTestApp(
          locale: const Locale('zh', 'TW'),
          home: Scaffold(
            body: ReaderProgressControl(
              config: ReaderProgressConfig(
                current: 3,
                total: 12,
                onChanged: (_) {},
                onChangeEnd: (_) {},
              ),
            ),
          ),
        ),
      );

      final previous = tester.widget<IconButton>(
        find.byKey(const Key('shared-reader-prev-button')),
      );
      final next = tester.widget<IconButton>(
        find.byKey(const Key('shared-reader-next-button')),
      );
      final slider = tester.widget<Slider>(
        find.byKey(const Key('shared-reader-progress-slider')),
      );

      expect(previous.tooltip, l10n.readerPrevious);
      expect(next.tooltip, l10n.readerNext);
      expect(
        slider.semanticFormatterCallback?.call(2),
        l10n.readerProgressSemantics('3', '12'),
      );
    },
  );

  testWidgets('reader controls preserve explicit tooltip overrides', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: ReaderProgressControl(
            config: ReaderProgressConfig(
              current: 1,
              total: 2,
              previousTooltip: 'Raw Previous Override',
              nextTooltip: 'Raw Next Override',
              onChanged: (_) {},
              onChangeEnd: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shared-reader-prev-button')),
          )
          .tooltip,
      'Raw Previous Override',
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shared-reader-next-button')),
          )
          .tooltip,
      'Raw Next Override',
    );
  });

  testWidgets('reader top bar localizes back and keeps raw titles', (
    tester,
  ) async {
    final l10n = AppLocalizationsZhTw();
    await tester.pumpWidget(
      LocalizedTestApp(
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          body: ReaderTopOverlayBar(
            config: ReaderTopBarConfig(
              title: 'Raw Work 标题',
              subtitle: 'Raw Chapter 章節',
              actions: const <ReaderToolbarAction>[],
              onBack: () {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('shared-reader-top-back-button')),
          )
          .tooltip,
      l10n.readerBack,
    );
    expect(find.text('Raw Work 标题'), findsOneWidget);
    expect(find.text('Raw Chapter 章節'), findsOneWidget);
  });

  testWidgets('reader segmented control localizes selected semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final l10n = AppLocalizationsZhTw();
    await tester.pumpWidget(
      LocalizedTestApp(
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          body: ReaderSegmentControl<String>(
            label: '模式',
            value: 'raw-mode',
            values: const <String>['raw-mode', 'other-mode'],
            labelBuilder: (value) => value,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(l10n.readerSelectedSemantics('raw-mode')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
