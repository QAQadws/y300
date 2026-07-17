import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_document_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_adapter.dart';

void main() {
  testWidgets(
    'theme changes prepare a new document and ignore the old late future',
    (tester) async {
      final preparer = _DeferredNovelHtmlChapterPreparer();

      await tester.pumpWidget(_host(theme: _lightTheme, preparer: preparer));
      expect(preparer.calls, hasLength(1));
      expect(
        find.byKey(const Key('novel-reader-html-loading')),
        findsOneWidget,
      );

      await tester.pumpWidget(_host(theme: _darkTheme, preparer: preparer));
      expect(preparer.calls, hasLength(2));
      expect(preparer.calls.last.themeSignature, _darkTheme.signature);

      preparer.calls.first.completer.complete(
        _prepared(theme: _lightTheme, text: '旧主题正文'),
      );
      await tester.pump();

      expect(find.textContaining('旧主题正文'), findsNothing);
      expect(
        find.byKey(const Key('novel-reader-html-loading')),
        findsOneWidget,
      );

      preparer.calls.last.completer.complete(
        _prepared(theme: _darkTheme, text: '新主题正文'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('新主题正文', findRichText: true), findsOneWidget);
      expect(find.textContaining('旧主题正文', findRichText: true), findsNothing);
      final htmlWidget = tester.widget<HtmlWidget>(
        find.byKey(const Key('forum-html-renderer-episode-1')),
      );
      expect(htmlWidget.textStyle?.color, _darkTheme.foreground);
    },
  );

  testWidgets('does not submit retained data from the previous theme', (
    tester,
  ) async {
    final preparer = _DeferredNovelHtmlChapterPreparer();

    await tester.pumpWidget(_host(theme: _lightTheme, preparer: preparer));
    preparer.calls.single.completer.complete(
      _prepared(theme: _lightTheme, text: '浅色正文'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('浅色正文', findRichText: true), findsOneWidget);

    await tester.pumpWidget(_host(theme: _darkTheme, preparer: preparer));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('浅色正文', findRichText: true), findsNothing);
    expect(find.byKey(const Key('novel-reader-html-loading')), findsOneWidget);

    preparer.calls.last.completer.complete(
      _prepared(theme: _darkTheme, text: '深色正文'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('深色正文', findRichText: true), findsOneWidget);
  });

  testWidgets(
    'reuses equal preparation identity and invalidates on font size',
    (tester) async {
      final preparer = _DeferredNovelHtmlChapterPreparer();
      final preferences = NovelReaderPreferences.defaults();

      await tester.pumpWidget(
        _host(theme: _lightTheme, preparer: preparer, preferences: preferences),
      );
      expect(preparer.calls, hasLength(1));

      await tester.pumpWidget(
        _host(
          theme: _lightTheme,
          preparer: preparer,
          preferences: preferences.copyWith(),
        ),
      );
      expect(preparer.calls, hasLength(1));

      await tester.pumpWidget(
        _host(
          theme: _lightTheme,
          preparer: preparer,
          preferences: preferences.copyWith(fontSize: 22),
        ),
      );
      expect(preparer.calls, hasLength(2));
    },
  );
}

Widget _host({
  required ForumHtmlThemeContext theme,
  required NovelHtmlChapterPreparer preparer,
  NovelReaderPreferences? preferences,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: NovelReaderHtmlDocumentView(
        rawHtml: '<p>待准备正文</p>',
        episode: _episode,
        preferences: preferences ?? NovelReaderPreferences.defaults(),
        typography: _typography,
        theme: theme,
        imageReferer: 'https://bbs.yamibo.com/thread-100-1-1.html',
        preparer: preparer,
      ),
    ),
  );
}

NovelHtmlPreparedChapter _prepared({
  required ForumHtmlThemeContext theme,
  required String text,
}) {
  final html = '<p>$text</p>';
  final document = const DefaultForumHtmlRenderPreparer().prepare(
    html: html,
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: theme,
    themeAdaptationMode: ForumHtmlThemeAdaptationMode.enabled,
    sourceId: _episode.episodeId,
    threadId: _episode.sourceTid,
    imageCacheOwnerId: _episode.sourceTid,
  );
  return NovelHtmlPreparedChapter(
    html: html,
    document: document,
    convertedTextNodeCount: 0,
  );
}

const _episode = NovelEpisodeItem(
  episodeId: 'episode-1',
  novelId: 'novel-1',
  sourceTid: '100',
  sourcePid: '200',
  sourcePage: 1,
  episodeTitle: '第一章',
  orderIndex: 0,
);

const _typography = NovelReaderTypography(
  body: TextStyle(fontSize: 18),
  chapterTitle: TextStyle(fontSize: 22),
  quote: TextStyle(fontSize: 18),
  link: TextStyle(fontSize: 18),
  textAlign: TextAlign.start,
  firstLineIndent: 0,
  contentMaxWidth: 720,
);

const _lightTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFFFFFFF),
  foreground: Color(0xFF202020),
  link: Color(0xFF1565C0),
  quoteSurface: Color(0xFFF1F1F1),
  quoteForeground: Color(0xFF424242),
  codeSurface: Color(0xFFF5F5F5),
  codeForeground: Color(0xFF202020),
);

const _darkTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.dark,
  surface: Color(0xFF141414),
  foreground: Color(0xFFE9E9E9),
  link: Color(0xFF8DB7FF),
  quoteSurface: Color(0xFF242424),
  quoteForeground: Color(0xFFAAA39A),
  codeSurface: Color(0xFF202020),
  codeForeground: Color(0xFFE9E9E9),
);

final class _DeferredNovelHtmlChapterPreparer
    implements NovelHtmlChapterPreparer {
  final calls = <_DeferredPrepareCall>[];

  @override
  Future<NovelHtmlPreparedChapter> prepare({
    required String rawHtml,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    final call = _DeferredPrepareCall(theme.signature);
    calls.add(call);
    return call.completer.future;
  }
}

final class _DeferredPrepareCall {
  _DeferredPrepareCall(this.themeSignature);

  final String themeSignature;
  final Completer<NovelHtmlPreparedChapter> completer =
      Completer<NovelHtmlPreparedChapter>();
}
