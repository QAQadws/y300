import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';

import '../../../test_support/localized_test_app.dart';
import '../../../test_support/native_body_finders.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('compact flow shapes short and wrapped text at its real width', (
    tester,
  ) async {
    final links = <String>[];
    await _pump(
      tester,
      '<p dir="rtl"><a href="forum.php?mod=viewthread&amp;tid=42">Link</a></p>',
      onOpenLink: links.add,
    );
    final short = tester.getSize(findNativeBody('compact'));
    expect(short.width, inExclusiveRange(0, 100));
    expect(find.byType(IntrinsicWidth), findsNothing);
    await tapNativeBodyText(tester, 'Link');
    expect(links, ['https://bbs.yamibo.com/forum.php?mod=viewthread&tid=42']);

    await _pump(tester, '<p>${'足够长的消息' * 38}</p>');
    final long = tester.getSize(findNativeBody('compact'));
    expect(long.width, 240);
    expect(long.height, greaterThan(short.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact paragraphs keep interior spacing and author widths', (
    tester,
  ) async {
    await _pump(
      tester,
      '<div><p style="width:180px;margin-bottom:27px">First</p><p>Second</p></div>',
    );
    final body = tester.getRect(findNativeBody('compact'));
    final first = tester.getRect(findNativeBodyText('First'));
    final second = tester.getRect(findNativeBodyText('Second'));
    expect(body.width, closeTo(180, 0.01));
    expect(first.top, closeTo(body.top, 0.01));
    expect(second.top - first.bottom, closeTo(27, 0.01));
    expect(second.bottom, closeTo(body.bottom, 0.01));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  String html, {
  ValueChanged<String>? onOpenLink,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
          const _Preferences(),
        ),
      ],
      child: LocalizedTestApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: ForumHtmlContentView(
                html: html,
                sourceId: 'compact',
                contentLayout: ForumHtmlContentLayout.compact,
                onOpenLink: onOpenLink,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Preferences implements ForumHtmlReaderPreferencesRepository {
  const _Preferences();

  @override
  Future<ForumHtmlReaderPreferences> load() async =>
      ForumHtmlReaderPreferences.defaults().copyWith(
        typography: const RichTextTypography(
          fontScale: 1,
          lineHeightScale: 1.5,
          paragraphSpacing: 18,
        ),
      );

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {}
}
