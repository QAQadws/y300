import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/presentation/services/novel_html_chapter_render_preparer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_document_view.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

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

  testWidgets('forwards links through the HTML-first reader callback', (
    tester,
  ) async {
    final tappedLinks = <NovelReaderLink>[];

    await tester.pumpWidget(
      _host(
        theme: _lightTheme,
        preparer: const NovelHtmlChapterRenderPreparer(),
        rawHtml: '<a href="forum.php?mod=viewthread&tid=101">章节链接</a>',
        onLinkTap: tappedLinks.add,
      ),
    );
    await tester.pumpAndSettle();

    final renderer = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-episode-1')),
    );
    await renderer.onTapUrl?.call(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101',
    );

    expect(tappedLinks, hasLength(1));
    expect(
      tappedLinks.single.url,
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101',
    );
  });

  testWidgets('clips inline media on the first HTML reader frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        theme: _lightTheme,
        preparer: const NovelHtmlChapterRenderPreparer(),
        rawHtml:
            '<img src="data/attachment/forum/chapter-image.jpg" '
            'width="640" height="480">'
            '<img src="static/image/smiley/gexing/008.gif" '
            'width="24" height="24">',
        imageCacheService: _NoopImageCacheService(),
      ),
    );
    await tester.pumpAndSettle();

    final images = find.byType(CachedLibraryImage);
    expect(images, findsNWidgets(2));
    for (var index = 0; index < 2; index += 1) {
      final clip = tester.widget<ClipRRect>(
        find
            .ancestor(of: images.at(index), matching: find.byType(ClipRRect))
            .first,
      );
      expect(clip.borderRadius, const BorderRadius.all(Radius.circular(4)));
    }
  });
}

Widget _host({
  required ForumHtmlThemeContext theme,
  required NovelHtmlChapterPreparer preparer,
  NovelReaderPreferences? preferences,
  String rawHtml = '<p>待准备正文</p>',
  ValueChanged<NovelReaderLink>? onLinkTap,
  ImageCacheService? imageCacheService,
}) {
  return ProviderScope(
    overrides: [
      if (imageCacheService != null)
        imageCacheServiceProvider.overrideWithValue(imageCacheService),
    ],
    child: LocalizedTestApp(
      home: NovelReaderHtmlDocumentView(
        rawHtml: rawHtml,
        episode: _episode,
        preferences: preferences ?? NovelReaderPreferences.defaults(),
        typography: _typography,
        theme: theme,
        imageReferer: 'https://bbs.yamibo.com/thread-100-1-1.html',
        onLinkTap: onLinkTap,
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
  @override
  int get legacyMarkupNormalizerRevision => 0;

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

class _NoopImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(success: true, cacheKey: request.cacheKey);
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
    );
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async => 0;

  @override
  Future<void> clearUnprotected() async {}
}
