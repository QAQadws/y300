import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/reader_shared/domain/rich_text/typography/rich_text_typography.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/html_rendering/widgets/forum_collapse_block.dart';
import 'forum_html_test_theme.dart';

void main() {
  testWidgets('renders simple HTML text and inline formatting', (tester) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            html: '<p>普通 <strong>加粗</strong></p>',
            sourceId: 'unit',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-html-renderer-unit')), findsOneWidget);
    expect(find.textContaining('普通', findRichText: true), findsOneWidget);
    expect(find.textContaining('加粗', findRichText: true), findsOneWidget);
  });

  testWidgets('forwards link taps to callbacks', (tester) async {
    final tappedUrls = <String>[];
    var interactions = 0;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            html: '<a href="forum.php?mod=viewthread&tid=1">链接</a>',
            sourceId: 'link',
            callbacks: ForumHtmlRenderCallbacks(
              onInteraction: () => interactions += 1,
              onTapUrl: (url) async {
                tappedUrls.add(url);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('链接', findRichText: true));
    await tester.pumpAndSettle();

    expect(tappedUrls, <String>[
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1',
    ]);
    expect(interactions, 1);
  });

  testWidgets('passes reader preferences to HtmlWidget', (tester) async {
    final preferences = ForumHtmlReaderPreferences.defaults().copyWith(
      typography: const RichTextTypography(
        fontScale: 1.4,
        lineHeightScale: 1.9,
        paragraphSpacing: 22,
      ),
    );

    await tester.pumpWidget(
      LocalizedTestApp(
        theme: ThemeData(
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 10)),
        ),
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            html: '<p>段落</p>',
            sourceId: 'prefs',
            preferences: preferences,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final htmlWidget = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-prefs')),
    );
    expect(htmlWidget.textStyle?.fontSize, 14);
    expect(htmlWidget.textStyle?.height, 1.9);
    expect(htmlWidget.customStylesBuilder?.call(_elementFrom('<p>段落</p>')), {
      'margin': '0 0 22.0px',
    });
  });

  testWidgets('uses explicit render theme quote colors', (tester) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'quote-surface',
            html:
                '<div class="quote"><blockquote>'
                '<a href="space.php?uid=1">作者 发表于 2026-1-5</a><br>'
                '引用正文'
                '</blockquote></div>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final htmlWidget = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-quote-surface')),
    );
    final quoteStyles = htmlWidget.customStylesBuilder?.call(
      _elementFrom('<div class="quote">引用正文</div>'),
    );
    expect(
      quoteStyles,
      containsPair(
        'background-color',
        _cssHex(forumHtmlTestTheme.quoteSurface),
      ),
    );
    expect(
      quoteStyles,
      containsPair(
        'border-left',
        '3px solid ${_cssHex(forumHtmlTestTheme.link)}',
      ),
    );
    expect(find.textContaining('引用正文', findRichText: true), findsOneWidget);
  });

  testWidgets('renders adapted html when author font sizes are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            html:
                '<p style="font-size: 30px; color: red; '
                'background-color: yellow">正文</p>',
            sourceId: 'sanitized',
            preferences: ForumHtmlReaderPreferences.defaults().copyWith(
              preserveAuthorFontSize: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('正文', findRichText: true), findsOneWidget);
  });

  testWidgets('normalizes Discuz font size 3 to the base body size', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        theme: ThemeData(
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 20)),
        ),
        home: const Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'font-size-three',
            html: '默认<font size="3">三号</font>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final defaultSpan = _findTextSpanContaining(tester, '默认');
    final sizeThreeSpan = _findTextSpanContaining(tester, '三号');

    expect(defaultSpan?.style?.fontSize, 23);
    expect(sizeThreeSpan?.style?.fontSize, 23);
  });

  testWidgets('preserves Discuz font size ordering around the base size', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        theme: ThemeData(
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 20)),
        ),
        home: const Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'font-size-ordering',
            html:
                '默认'
                '<font size="2">二号</font>'
                '<font size="4">四号</font>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final defaultSize = _findTextSpanContaining(tester, '默认')?.style?.fontSize;
    final sizeTwo = _findTextSpanContaining(tester, '二号')?.style?.fontSize;
    final sizeFour = _findTextSpanContaining(tester, '四号')?.style?.fontSize;

    expect(defaultSize, 23);
    expect(sizeTwo, lessThan(defaultSize!));
    expect(sizeFour, greaterThan(defaultSize));
  });

  testWidgets('renders Discuz edit status smaller and quieter', (tester) async {
    const bodyColor = Color(0xFF203040);
    await tester.pumpWidget(
      LocalizedTestApp(
        theme: ThemeData(
          textTheme: const TextTheme(
            bodyMedium: TextStyle(fontSize: 20, color: bodyColor),
          ),
        ),
        home: const Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'pstatus',
            html:
                '<i class="pstatus"> 本帖最后由 INCSKY16 于 2026-7-3 13:56 编辑 </i>'
                '<br><i>普通斜体</i><p>正文</p>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editStatus = tester.widget<Text>(
      find.byKey(const Key('forum-html-discuz-edit-status')),
    );
    final ordinaryItalic = _findTextSpanContaining(tester, '普通斜体');

    expect(editStatus.data, '本帖最后由 INCSKY16 于 2026-7-3 13:56 编辑');
    expect(editStatus.style?.fontStyle, FontStyle.italic);
    expect(editStatus.style?.fontSize, lessThan(23));
    expect(editStatus.style?.color?.a, lessThan(bodyColor.a));
    expect(ordinaryItalic?.style?.fontStyle, FontStyle.italic);
    expect(ordinaryItalic?.style?.fontSize, 23);
    expect(ordinaryItalic?.style?.color?.a, bodyColor.a);
  });

  testWidgets('uses compact deterministic spacing after Discuz edit status', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'pstatus-spacing',
            html:
                '<i class="pstatus">本帖最后由作者编辑</i><br><br>'
                '<span>正文紧随编辑提示</span>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final htmlWidget = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-pstatus-spacing')),
    );
    final prepared = html_parser.parseFragment(htmlWidget.html);
    expect(prepared.querySelectorAll('br'), isEmpty);

    final statusRect = tester.getRect(
      find.byKey(const Key('forum-html-discuz-edit-status')),
    );
    final bodyFinder = find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains('正文紧随编辑提示'),
    );
    final bodyRect = tester.getRect(bodyFinder);
    expect(bodyRect.top - statusRect.bottom, inInclusiveRange(7, 10));
  });

  testWidgets('renders forum collapse blocks and expands nested content', (
    tester,
  ) async {
    final tappedUrls = <String>[];
    var interactions = 0;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'collapse',
            html:
                '<div id="toc" class="showcollapse_box">'
                '<div class="showcollapse_title">目录</div>'
                '<div class="showcollapse_content">'
                '<a href="thread.html">内容链接</a>'
                '<div id="inner" class="showcollapse_box">'
                '<div class="showcollapse_title">内层目录</div>'
                '<div class="showcollapse_content">内层内容</div>'
                '</div>'
                '<div class="showcollapse_gather">收起</div>'
                '</div>'
                '</div>',
            callbacks: ForumHtmlRenderCallbacks(
              onInteraction: () => interactions += 1,
              onTapUrl: (url) async {
                tappedUrls.add(url);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ForumCollapseBlock), findsOneWidget);
    expect(
      find.byKey(const Key('forum-html-collapse-collapse-toc')),
      findsOneWidget,
    );
    expect(find.textContaining('目录', findRichText: true), findsOneWidget);
    expect(find.textContaining('内容链接', findRichText: true), findsNothing);
    expect(find.text('收起', findRichText: true), findsNothing);

    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-collapse-toc')),
    );
    await tester.pumpAndSettle();

    expect(interactions, 1);
    expect(find.textContaining('内容链接', findRichText: true), findsOneWidget);
    expect(find.byType(ForumCollapseBlock), findsNWidgets(2));
    expect(
      find.byKey(const Key('forum-html-collapse-collapse-toc-content-inner')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const Key('forum-html-collapse-toggle-collapse-toc-content-inner'),
      ),
    );
    await tester.pumpAndSettle();
    expect(interactions, 2);

    await tester.tap(find.text('内容链接', findRichText: true));
    await tester.pumpAndSettle();

    expect(tappedUrls, <String>['https://bbs.yamibo.com/thread.html']);
    expect(interactions, 3);
  });

  testWidgets('starts active forum collapse blocks expanded', (tester) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'active',
            html:
                '<div id="toc" class="showcollapse_box showcollapse_active">'
                '<div class="showcollapse_title">目录</div>'
                '<div class="showcollapse_content">已展开内容</div>'
                '</div>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已展开内容', findRichText: true), findsOneWidget);
    expect(
      find.byKey(const Key('forum-html-collapse-content-active-toc')),
      findsOneWidget,
    );
  });

  testWidgets('keeps ruby rendering delegated to the html library', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'ruby',
            html: '<p>冒险者<ruby>特莉丝<rt>トリス</rt></ruby></p>',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('特莉丝', findRichText: true), findsOneWidget);
    expect(find.textContaining('トリス', findRichText: true), findsOneWidget);
    expect(find.textContaining('<rt>', findRichText: true), findsNothing);
  });

  testWidgets('maps tapped images to forum image requests', (tester) async {
    ForumHtmlImageRequest? tappedImage;
    var interactions = 0;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'image',
            html:
                '<img id="aimg_286401" '
                'src="data/attachment/forum/month_1110/pic.jpg" '
                'alt="预览图" title="图片标题" width="640" height="480">',
            callbacks: ForumHtmlRenderCallbacks(
              onInteraction: () => interactions += 1,
              onTapImage: (request) => tappedImage = request,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final htmlWidget = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-image')),
    );
    htmlWidget.onTapImage?.call(
      ImageMetadata(
        alt: '预览图',
        title: '图片标题',
        sources: const [
          ImageSource(
            'https://bbs.yamibo.com/data/attachment/forum/month_1110/pic.jpg',
            width: 640,
            height: 480,
          ),
        ],
      ),
    );

    expect(
      tappedImage?.url,
      endsWith('/data/attachment/forum/month_1110/pic.jpg'),
    );
    expect(tappedImage?.alt, '预览图');
    expect(tappedImage?.title, '图片标题');
    expect(tappedImage?.width, 640);
    expect(tappedImage?.height, 480);
    expect(tappedImage?.isSticker, isFalse);
    expect(tappedImage?.attachmentId, '286401');
    expect(interactions, 1);
  });

  testWidgets('cached thread image taps include readable sequence metadata', (
    tester,
  ) async {
    ForumHtmlImageRequest? tappedImage;
    var interactions = 0;
    final prepared = const DefaultForumHtmlRenderPreparer().prepare(
      html:
          '<img id="aimg_286401" '
          'src="data/attachment/forum/month_1110/pic.jpg" '
          'alt="预览图" title="图片标题" width="640" height="480">',
      preferences: ForumHtmlReaderPreferences.defaults(),
      theme: forumHtmlTestTheme,
      sourceId: 'p1',
      threadId: '573279',
      imageCacheOwnerId: '573279',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(
            _RecordingImageCacheService(),
          ),
        ],
        child: LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'p1',
              threadId: '573279',
              preparedDocument: prepared,
              html: prepared.preparedHtml,
              callbacks: ForumHtmlRenderCallbacks(
                onInteraction: () => interactions += 1,
                onTapImage: (request) => tappedImage = request,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('thread-post-html-first-readable-image-p1-0')),
    );

    expect(tappedImage?.readableIndex, 0);
    expect(tappedImage?.attachmentId, '286401');
    expect(tappedImage?.kind, ForumImageKind.threadInline);
    expect(interactions, 1);
    expect(
      tappedImage?.cacheKey,
      ForumImageCacheRequests.threadInline(
        tid: '573279',
        url: 'https://bbs.yamibo.com/data/attachment/forum/month_1110/pic.jpg',
        imageIndex: 0,
      ).cacheKey,
    );
  });

  testWidgets('detects a prepared document theme signature mismatch', (
    tester,
  ) async {
    final prepared = const DefaultForumHtmlRenderPreparer().prepare(
      html: '<p>正文</p>',
      preferences: ForumHtmlReaderPreferences.defaults(),
      theme: forumHtmlTestTheme,
      sourceId: 'theme-mismatch',
      threadId: '100',
      imageCacheOwnerId: '100',
    );

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            html: prepared.preparedHtml,
            theme: _darkTestTheme,
            sourceId: 'theme-mismatch',
            preparedDocument: prepared,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isA<AssertionError>());
  });

  testWidgets('renders thread images through project cache pipeline', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    const headerBuilder = _StaticImageHeaderBuilder();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'cached-thread-image',
              threadId: '573279',
              imageHeaderBuilder: headerBuilder,
              html:
                  '<img src="data/attachment/forum/page-1.jpg" '
                  'width="640" height="480">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<CachedLibraryImage>(
      find.byType(CachedLibraryImage).first,
    );

    expect(image.headerBuilder, same(headerBuilder));
    expect(image.showDelayedLoadingIndicator, isTrue);
    expect(image.loadingIndicatorDelay, const Duration(milliseconds: 300));
    expect(image.request?.role, ImageCacheRole.threadInline);
    expect(image.request?.ownerType, ImageCacheOwnerType.thread);
    expect(image.request?.ownerId, '573279');
    expect(image.request?.imageIndex, 0);
    expect(
      image.request?.sourceUrl,
      'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
    );
    expect(
      image.request?.cacheKey,
      ForumImageCacheRequests.threadInline(
        tid: '573279',
        url: 'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
        imageIndex: 0,
      ).cacheKey,
    );
    expect(cacheService.requests.single.cacheKey, image.request?.cacheKey);
  });

  testWidgets('clips attachment and smiley media at the HTML surface', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'html-media-radius',
              threadId: '573279',
              html:
                  '<img src="data/attachment/forum/page-1.jpg" '
                  'width="640" height="480">'
                  '<img src="static/image/smiley/gexing/008.gif" '
                  'width="24" height="24">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

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

    // The same clip must remain present after the cache miss reaches the
    // remote/error stage; it is owned by the HTML surface, not the cache
    // state.
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: images.first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ClipRRect &&
              widget.borderRadius == const BorderRadius.all(Radius.circular(4)),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('failed thread image offers a retry that reruns the cache flow', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'retryable-thread-image',
              threadId: '573279',
              html:
                  '<img src="data/attachment/forum/page-1.jpg" '
                  'width="640" height="480">',
            ),
          ),
        ),
      ),
    );
    // 测试环境的 HttpClient 对所有请求返回失败，图片必然走到失败占位。
    await tester.pumpAndSettle();

    expect(find.text('图片加载失败'), findsOneWidget);
    expect(cacheService.requests, hasLength(1));

    await tester.tap(find.widgetWithText(OutlinedButton, '重试'));
    await tester.pumpAndSettle();

    expect(cacheService.requests, hasLength(2));
  });

  testWidgets('builds image load specs before resolving cache requests', (
    tester,
  ) async {
    final resolver = _RecordingForumImageRequestResolver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(
            _RecordingImageCacheService(),
          ),
        ],
        child: LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'spec-thread-image',
              threadId: '573279',
              imageRequestResolver: resolver,
              html:
                  '<img src="data/attachment/forum/page-1.jpg" '
                  'width="640" height="480">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CachedLibraryImage), findsOneWidget);
    expect(resolver.specs, hasLength(1));
    expect(resolver.specs.single.kind, ForumImageKind.threadInline);
    expect(resolver.specs.single.ownerId, '573279');
    expect(resolver.specs.single.imageIndex, 0);
    expect(resolver.specs.single.htmlWidth, 640);
    expect(resolver.specs.single.htmlHeight, 480);
    expect(
      resolver.specs.single.sourceUrl,
      'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
    );
  });

  testWidgets('renders smiley images through long-lived smiley cache', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'cached-smiley',
              threadId: '573279',
              html: '<img src="static/image/smiley/gexing/008.gif" alt="">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<CachedLibraryImage>(
      find.byType(CachedLibraryImage).first,
    );

    expect(image.request?.role, ImageCacheRole.remoteSmiley);
    expect(image.showDelayedLoadingIndicator, isFalse);
    expect(image.request?.ownerType, ImageCacheOwnerType.sticker);
    expect(image.request?.effectiveRetentionClass, ImageRetentionClass.sticky);
    expect(
      image.request?.cacheKey,
      ImageCacheKeys.remoteSmiley(
        'https://bbs.yamibo.com/static/image/smiley/gexing/008.gif',
      ),
    );
    expect(cacheService.requests.single.role, ImageCacheRole.remoteSmiley);
  });

  testWidgets('does not force unsized smiley images to 24 square', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(
            _RecordingImageCacheService(),
          ),
        ],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'unsized-smiley',
              threadId: '573279',
              html: '<img src="static/image/smiley/gexing/008.gif" alt="">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final imageFinder = find.byType(CachedLibraryImage).first;
    final image = tester.widget<CachedLibraryImage>(imageFinder);

    expect(image.width, isNull);
    expect(image.height, isNull);
    expect(
      find.ancestor(
        of: imageFinder,
        matching: find.byWidgetPredicate((widget) {
          return widget is SizedBox &&
              widget.width == 24 &&
              widget.height == 24;
        }),
      ),
      findsNothing,
    );
  });

  testWidgets('uses html dimensions for smiley images when present', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(
            _RecordingImageCacheService(),
          ),
        ],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'sized-smiley',
              threadId: '573279',
              html:
                  '<img src="static/image/smiley/gexing/008.gif" '
                  'width="36" height="28" alt="">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final imageFinder = find.byType(CachedLibraryImage).first;
    final image = tester.widget<CachedLibraryImage>(imageFinder);
    final sizedBox = tester.widget<SizedBox>(
      find.ancestor(of: imageFinder, matching: find.byType(SizedBox)).first,
    );

    expect(image.width, 36);
    expect(image.height, 28);
    expect(sizedBox.width, 36);
    expect(sizedBox.height, 28);
  });

  testWidgets('uses cached dimensions for smiley images when html is unsized', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    final cacheKey = ImageCacheKeys.remoteSmiley(
      'https://bbs.yamibo.com/static/image/smiley/gexing/008.gif',
    );
    cacheService.cachedResults[cacheKey] = CachedImageResult(
      success: true,
      cacheKey: cacheKey,
      width: 40,
      height: 32,
      fromCache: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'cached-size-smiley',
              threadId: '573279',
              html: '<img src="static/image/smiley/gexing/008.gif" alt="">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final imageFinder = find.byType(CachedLibraryImage).first;
    final image = tester.widget<CachedLibraryImage>(imageFinder);
    final sizedBox = tester.widget<SizedBox>(
      find.ancestor(of: imageFinder, matching: find.byType(SizedBox)).first,
    );

    expect(image.width, 40);
    expect(image.height, 32);
    expect(sizedBox.width, 40);
    expect(sizedBox.height, 32);
  });

  testWidgets('uses legacy fallback aspect ratio for unsized thread images', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(
            _RecordingImageCacheService(),
          ),
        ],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'unsized-image',
              threadId: '573279',
              html: '<img src="data/attachment/forum/page-unsized.jpg">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final aspectRatio = tester.widget<AspectRatio>(
      find
          .ancestor(
            of: find.byType(CachedLibraryImage).first,
            matching: find.byType(AspectRatio),
          )
          .first,
    );

    expect(aspectRatio.aspectRatio, 0.7);
  });

  testWidgets('uses learned fallback ratio and reports decoded block size', (
    tester,
  ) async {
    final resolvedSizes = <Size>[];
    final resolvedCacheKeys = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(
            _RecordingImageCacheService(),
          ),
        ],
        child: LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'learned-ratio-image',
              threadId: '573279',
              html: '<img src="data/attachment/forum/page-learned.jpg">',
              imageFallbackAspectRatioFor: (spec, request) {
                expect(spec.htmlWidth, isNull);
                expect(spec.htmlHeight, isNull);
                resolvedCacheKeys.add(request.cacheKey);
                return 1.6;
              },
              onBlockImageResolved: (spec, request, size) {
                resolvedSizes.add(size);
                resolvedCacheKeys.add(request.cacheKey);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final aspectRatio = tester.widget<AspectRatio>(
      find
          .ancestor(
            of: find.byType(CachedLibraryImage).first,
            matching: find.byType(AspectRatio),
          )
          .first,
    );

    expect(aspectRatio.aspectRatio, 1.6);

    tester
        .widget<CachedLibraryImage>(find.byType(CachedLibraryImage).first)
        .onImageResolved
        ?.call(const Size(800, 400));
    await tester.pump();

    expect(resolvedSizes, <Size>[const Size(800, 400)]);
    expect(resolvedCacheKeys, hasLength(2));
    expect(resolvedCacheKeys.toSet(), hasLength(1));
  });

  testWidgets('promotes fallback thread image layout after decoded size', (
    tester,
  ) async {
    final shifts = <ForumHtmlImageLayoutShift>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(
            _RecordingImageCacheService(),
          ),
        ],
        child: LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'decoded-size-image',
              threadId: '573279',
              html: '<img src="data/attachment/forum/page-decoded.jpg">',
              callbacks: ForumHtmlRenderCallbacks(
                onImageLayoutShift: shifts.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    AspectRatio currentAspectRatio() {
      return tester.widget<AspectRatio>(
        find
            .ancestor(
              of: find.byType(CachedLibraryImage).first,
              matching: find.byType(AspectRatio),
            )
            .first,
      );
    }

    expect(currentAspectRatio().aspectRatio, 0.7);

    tester
        .widget<CachedLibraryImage>(find.byType(CachedLibraryImage).first)
        .onImageResolved
        ?.call(const Size(1600, 900));
    await tester.pump();

    expect(currentAspectRatio().aspectRatio, 1600 / 900);
    expect(shifts, hasLength(1));
    expect(shifts.single.oldAspectRatio, 0.7);
    expect(shifts.single.newAspectRatio, 1600 / 900);
    expect(shifts.single.deltaHeight, lessThan(0));
  });

  testWidgets(
    'uses the decoded ratio for small deltas without scroll compensation',
    (tester) async {
      final shifts = <ForumHtmlImageLayoutShift>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(
              _RecordingImageCacheService(),
            ),
          ],
          child: LocalizedTestApp(
            home: Scaffold(
              body: ForumHtmlWidgetPostRenderer(
                theme: forumHtmlTestTheme,
                sourceId: 'small-decoded-size-delta-image',
                threadId: '573279',
                html: '<img src="data/attachment/forum/page-small-delta.jpg">',
                callbacks: ForumHtmlRenderCallbacks(
                  onImageLayoutShift: shifts.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      AspectRatio currentAspectRatio() {
        return tester.widget<AspectRatio>(
          find
              .ancestor(
                of: find.byType(CachedLibraryImage).first,
                matching: find.byType(AspectRatio),
              )
              .first,
        );
      }

      ClipRRect currentClip() {
        return tester.widget<ClipRRect>(
          find
              .ancestor(
                of: find.byType(CachedLibraryImage).first,
                matching: find.byType(ClipRRect),
              )
              .first,
        );
      }

      expect(currentAspectRatio().aspectRatio, 0.7);
      expect(
        currentClip().borderRadius,
        const BorderRadius.all(Radius.circular(4)),
      );

      tester
          .widget<CachedLibraryImage>(find.byType(CachedLibraryImage).first)
          .onImageResolved
          ?.call(const Size(720, 1000));
      await tester.pump();

      expect(currentAspectRatio().aspectRatio, 0.72);
      expect(shifts, isEmpty);
      expect(
        currentClip().borderRadius,
        const BorderRadius.all(Radius.circular(4)),
      );
    },
  );

  testWidgets(
    'does not retain a tall trailing line box after consecutive attachment images',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(
              _RecordingImageCacheService(),
            ),
          ],
          child: const LocalizedTestApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    child: ForumHtmlWidgetPostRenderer(
                      theme: forumHtmlTestTheme,
                      sourceId: 'consecutive-attachment-images',
                      threadId: '573549',
                      html:
                          '<i class="pstatus">本帖最后编辑</i><br><br>'
                          '7月12日是辉夜的生日哦<br>辉夜生日快乐<br>'
                          '<a href="data/attachment/forum/first.jpg" '
                          'class="orange" />'
                          '<img src="data/attachment/forum/first.jpg">'
                          '</a>'
                          '<a href="data/attachment/forum/second.jpg" '
                          'class="orange" />'
                          '<img src="data/attachment/forum/second.jpg">'
                          '</a>'
                          '<a href="data/attachment/forum/third.jpg" '
                          'class="orange" />'
                          '<img src="data/attachment/forum/third.jpg">'
                          '</a><br><br>',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      const decodedSizes = <Size>[
        Size(1600, 1550),
        Size(1880, 3008),
        Size(1880, 3002),
      ];
      final imageWidgets = tester
          .widgetList<CachedLibraryImage>(find.byType(CachedLibraryImage))
          .toList(growable: false);
      expect(imageWidgets, hasLength(decodedSizes.length));
      for (var index = 0; index < imageWidgets.length; index++) {
        imageWidgets[index].onImageResolved?.call(decodedSizes[index]);
      }
      await tester.pump();

      final imageHeight = find
          .byType(AspectRatio)
          .evaluate()
          .map((element) => (element.renderObject! as RenderBox).size.height)
          .fold<double>(0, (sum, height) => sum + height);
      final rendererHeight = tester
          .getSize(
            find.byKey(
              const Key('forum-html-renderer-consecutive-attachment-images'),
            ),
          )
          .height;

      expect(rendererHeight - imageHeight, lessThan(160));
    },
  );

  testWidgets('keeps fallback layout for decoded sizes near the comic ratio', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(
            _RecordingImageCacheService(),
          ),
        ],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'decoded-comic-ratio-image',
              threadId: '573279',
              html: '<img src="data/attachment/forum/page-comic.jpg">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    tester
        .widget<CachedLibraryImage>(find.byType(CachedLibraryImage).first)
        .onImageResolved
        ?.call(const Size(700, 1000));
    await tester.pump();

    final aspectRatio = tester.widget<AspectRatio>(
      find
          .ancestor(
            of: find.byType(CachedLibraryImage).first,
            matching: find.byType(AspectRatio),
          )
          .first,
    );

    expect(aspectRatio.aspectRatio, 0.7);
  });

  testWidgets('uses cached aspect ratio for unsized thread images', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    final request = ForumImageCacheRequests.threadInline(
      tid: '573279',
      url: 'https://bbs.yamibo.com/data/attachment/forum/page-cached.jpg',
      imageIndex: 0,
    );
    cacheService.cachedResults[request.cacheKey] = CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      width: 320,
      height: 200,
      fromCache: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'cached-ratio-image',
              threadId: '573279',
              html: '<img src="data/attachment/forum/page-cached.jpg">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final aspectRatio = tester.widget<AspectRatio>(
      find
          .ancestor(
            of: find.byType(CachedLibraryImage).first,
            matching: find.byType(AspectRatio),
          )
          .first,
    );
    final image = tester.widget<CachedLibraryImage>(
      find.byType(CachedLibraryImage).first,
    );
    image.onImageResolved?.call(const Size(1600, 900));
    await tester.pump();
    final stableAspectRatio = tester.widget<AspectRatio>(
      find
          .ancestor(
            of: find.byType(CachedLibraryImage).first,
            matching: find.byType(AspectRatio),
          )
          .first,
    );

    expect(aspectRatio.aspectRatio, 1.6);
    expect(stableAspectRatio.aspectRatio, 1.6);
    expect(image.width, isNull);
    expect(image.height, isNull);
  });

  testWidgets('keeps html aspect ratio ahead of cached thread dimensions', (
    tester,
  ) async {
    final cacheService = _RecordingImageCacheService();
    final request = ForumImageCacheRequests.threadInline(
      tid: '573279',
      url: 'https://bbs.yamibo.com/data/attachment/forum/page-html.jpg',
      imageIndex: 0,
    );
    cacheService.cachedResults[request.cacheKey] = CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      width: 320,
      height: 200,
      fromCache: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'html-ratio-image',
              threadId: '573279',
              html:
                  '<img src="data/attachment/forum/page-html.jpg" '
                  'width="640" height="480">',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final aspectRatio = tester.widget<AspectRatio>(
      find
          .ancestor(
            of: find.byType(CachedLibraryImage).first,
            matching: find.byType(AspectRatio),
          )
          .first,
    );
    tester
        .widget<CachedLibraryImage>(find.byType(CachedLibraryImage).first)
        .onImageResolved
        ?.call(const Size(1600, 900));
    await tester.pump();
    final stableAspectRatio = tester.widget<AspectRatio>(
      find
          .ancestor(
            of: find.byType(CachedLibraryImage).first,
            matching: find.byType(AspectRatio),
          )
          .first,
    );

    expect(aspectRatio.aspectRatio, 640 / 480);
    expect(stableAspectRatio.aspectRatio, 640 / 480);
  });

  testWidgets('keeps non-network data images on the html library default path', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'data-image',
            threadId: '573279',
            html:
                '<img src="data:image/png;base64,'
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=">',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CachedLibraryImage), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    final clip = tester.widget<ClipRRect>(
      find
          .ancestor(of: find.byType(Image), matching: find.byType(ClipRRect))
          .first,
    );
    expect(clip.borderRadius, const BorderRadius.all(Radius.circular(4)));
  });

  testWidgets(
    'deduplicates repeated forum attachment images before rendering',
    (tester) async {
      await tester.pumpWidget(
        const LocalizedTestApp(
          home: Scaffold(
            body: ForumHtmlWidgetPostRenderer(
              theme: forumHtmlTestTheme,
              sourceId: 'dedupe',
              html:
                  '<p>正文</p>'
                  '<img id="aimg_1" src="data/attachment/forum/page-1.jpg">'
                  '<img id="aimg_2" src="data/attachment/forum/page-2.jpg">'
                  '<img id="aimg_1" src="data/attachment/forum/page-1.jpg">'
                  '<img id="aimg_2" src="data/attachment/forum/page-2.jpg">',
            ),
          ),
        ),
      );
      await tester.pump();

      final htmlWidget = tester.widget<HtmlWidget>(
        find.byKey(const Key('forum-html-renderer-dedupe')),
      );
      final fragment = html_parser.parseFragment(htmlWidget.html);

      expect(fragment.querySelectorAll('img'), hasLength(2));
      expect(
        htmlWidget.html.indexOf('page-1.jpg'),
        htmlWidget.html.lastIndexOf('page-1.jpg'),
      );
      expect(
        htmlWidget.html.indexOf('page-2.jpg'),
        htmlWidget.html.lastIndexOf('page-2.jpg'),
      );
    },
  );

  testWidgets('marks forum smiley images as stickers', (tester) async {
    ForumHtmlImageRequest? tappedImage;
    var interactions = 0;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: ForumHtmlWidgetPostRenderer(
            theme: forumHtmlTestTheme,
            sourceId: 'sticker',
            html: '<img src="static/image/smiley/gexing/008.gif" alt="">',
            callbacks: ForumHtmlRenderCallbacks(
              onInteraction: () => interactions += 1,
              onTapImage: (request) => tappedImage = request,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final htmlWidget = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-sticker')),
    );
    htmlWidget.onTapImage?.call(
      ImageMetadata(
        sources: const [
          ImageSource(
            'https://bbs.yamibo.com/static/image/smiley/gexing/008.gif',
          ),
        ],
      ),
    );

    expect(tappedImage?.isSticker, isTrue);
    expect(tappedImage?.attachmentId, isNull);
    expect(interactions, 1);
  });
}

const _darkTestTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.dark,
  surface: Color(0xFF141414),
  foreground: Color(0xFFE9E9E9),
  link: Color(0xFF8DB7FF),
  quoteSurface: Color(0xFF242424),
  quoteForeground: Color(0xFFAAA39A),
  codeSurface: Color(0xFF202020),
  codeForeground: Color(0xFFE9E9E9),
);

String _cssHex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

html_dom.Element _elementFrom(String html) {
  return html_parser
      .parseFragment(html)
      .nodes
      .whereType<html_dom.Element>()
      .first;
}

TextSpan? _findTextSpanContaining(WidgetTester tester, String text) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final span = _findTextSpanContainingIn(richText.text, text);
    if (span != null) {
      return span;
    }
  }
  return null;
}

TextSpan? _findTextSpanContainingIn(InlineSpan span, String text) {
  if (span is! TextSpan) {
    return null;
  }
  final value = span.text;
  if (value != null && value.contains(text)) {
    return span;
  }
  final children = span.children;
  if (children == null) {
    return null;
  }
  for (final child in children) {
    final found = _findTextSpanContainingIn(child, text);
    if (found != null) {
      return found;
    }
  }
  return null;
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{'Referer': 'https://bbs.yamibo.com/'};
  }
}

class _RecordingForumImageRequestResolver implements ForumImageRequestResolver {
  final specs = <ForumImageLoadSpec>[];
  final _delegate = const DefaultForumImageRequestResolver();

  @override
  ImageCacheRequest? resolveCacheRequest(ForumImageLoadSpec spec) {
    specs.add(spec);
    return _delegate.resolveCacheRequest(spec);
  }

  @override
  ForumImageRenderPolicy resolveRenderPolicy(ForumImageLoadSpec spec) {
    return _delegate.resolveRenderPolicy(spec);
  }
}

class _RecordingImageCacheService implements ImageCacheService {
  final requests = <ImageCacheRequest>[];
  final cachedResults = <String, CachedImageResult>{};

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    requests.add(request);
    return CachedImageResult(success: true, cacheKey: request.cacheKey);
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async =>
      cachedResults[cacheKey];

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
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}
