import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/messages/presentation/widgets/message_preview_text.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  late _PendingConverter converter;
  late _PendingConverter traditional;
  late ProviderContainer container;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    converter = _PendingConverter();
    traditional = _PendingConverter(mode: TextConversionMode.toTraditional);
    container = ProviderContainer.test(
      overrides: [
        textConverterProvider(
          TextConversionMode.none,
        ).overrideWithValue(converter),
        textConverterProvider(
          TextConversionMode.toTraditional,
        ).overrideWithValue(traditional),
      ],
    );
  });

  Future<void> pumpPreview(WidgetTester tester, String markup) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Scaffold(body: MessagePreviewText(markup: markup)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'preview keeps block separators and literal text without loading images',
    (tester) async {
      await pumpPreview(
        tester,
        '<p>你好 <b>A&amp;B</b></p><div>第二行<br>末尾 &lt;tag&gt;</div><script>SECRET</script><style>SECRET</style><img src="https://example.org/private.png">',
      );
      expect(converter.sources.single, '你好 A&B 第二行 末尾 <tag>');
      expect(find.text('你好 A&B 第二行 末尾 <tag>'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      converter.results.single.complete('你好 A&B 第二行 末尾 <tag>');
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'late conversion cannot overwrite a replaced preview and failures retain source',
    (tester) async {
      await pumpPreview(tester, '<p>旧消息</p>');
      await pumpPreview(tester, '<p>新消息</p>');
      converter.results.first.complete('舊訊息');
      await tester.pump();
      expect(find.text('新消息'), findsOneWidget);
      expect(find.text('舊訊息'), findsNothing);
      converter.results.last.completeError(StateError('fixture'));
      await tester.pumpAndSettle();
      expect(find.text('新消息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'thread font and conversion preference update preview without converting identity',
    (tester) async {
      await pumpPreview(tester, '<p>消息正文</p>');
      final preferences = container.read(
        forumHtmlReaderPreferencesControllerProvider.notifier,
      );
      await preferences.setFontScale(1.8);
      await preferences.setConversionMode(TextConversionMode.toTraditional);
      await tester.pump();
      expect(traditional.sources.single, '消息正文');
      traditional.results.single.complete('訊息正文');
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.text('訊息正文'));
      final theme = Theme.of(tester.element(find.byType(MessagePreviewText)));
      expect(text.style!.fontSize, theme.textTheme.bodyMedium!.fontSize! * 1.8);
      converter.results.single.complete('stale');
      await tester.pump();
      expect(find.text('stale'), findsNothing);
    },
  );
}

class _PendingConverter implements TextConverter {
  _PendingConverter({this.mode = TextConversionMode.none});
  @override
  final TextConversionMode mode;
  @override
  String get id => mode.name;
  final sources = <String>[];
  final results = <Completer<String>>[];
  @override
  Future<String> convertHtml(String html) {
    sources.add(html);
    final result = Completer<String>();
    results.add(result);
    return result.future;
  }
}
