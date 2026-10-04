import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

void main() {
  testWidgets('linked images switch between current link and image callbacks', (
    tester,
  ) async {
    const html =
        '<p><a href="https://example.test/linked-image">'
        '<img id="aimg_9" src="https://example.test/image.jpg" '
        'width="120" height="80"></a></p>';
    final host = _Images();
    final events = <String>[];
    Widget build(String label, {bool image = false}) => _host(
      html: html,
      imageHost: host,
      callbacks: ForumHtmlRenderCallbacks(
        onTapUrl: (url) {
          events.add('$label:url:$url');
          return true;
        },
        onTapImage: image
            ? (request) => events.add('$label:image:${request.url}')
            : null,
      ),
    );
    await tester.pumpWidget(build('initial'));
    await tester.pumpAndSettle();
    final bodyElement = tester.element(_body());
    await tester.tap(_image);
    await tester.pump();
    expect(events, ['initial:url:https://example.test/linked-image']);

    events.clear();
    await tester.pumpWidget(build('enabled', image: true));
    await tester.pumpAndSettle();
    expect(tester.element(_body()), same(bodyElement));
    await tester.tap(_image);
    await tester.pump();
    expect(events, ['enabled:image:https://example.test/image.jpg']);

    events.clear();
    await tester.pumpWidget(build('disabled'));
    await tester.pumpAndSettle();
    expect(tester.element(_body()), same(bodyElement));
    await tester.tap(_image);
    await tester.pump();
    expect(events, ['disabled:url:https://example.test/linked-image']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached root and nested interactions use current callbacks', (
    tester,
  ) async {
    const html =
        '<p><a href="https://example.test/root">Root link</a></p>'
        '<div id="fold" class="showcollapse_box">'
        '<div class="showcollapse_title">Details</div>'
        '<div class="showcollapse_content">'
        '<p><a href="https://example.test/nested">Nested link</a></p>'
        '<img id="aimg_9" src="https://example.test/image.jpg" '
        'width="120" height="80"></div></div>';
    final host = _Images();
    final events = <String>[];
    ForumHtmlRenderCallbacks callbacks(String label, {bool image = true}) =>
        ForumHtmlRenderCallbacks(
          onInteraction: () => events.add('$label:interaction'),
          onTapUrl: (url) {
            events.add('$label:url:$url');
            return true;
          },
          onTapImage: image
              ? (request) => events.add('$label:image:${request.url}')
              : null,
        );
    Widget build(String label, {bool image = true}) => _host(
      html: html,
      imageHost: host,
      callbacks: callbacks(label, image: image),
    );
    await tester.pumpWidget(build('old', image: false));
    await tester.pumpAndSettle();
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    final bodyElement = tester.element(_body());
    final nestedElement = tester.element(_body('rebind-fold-content'));
    events.clear();

    await tester.pumpWidget(build('new'));
    await tester.pumpAndSettle();
    expect(tester.element(_body()), same(bodyElement));
    expect(tester.element(_body('rebind-fold-content')), same(nestedElement));
    await _tapLink(tester, 'Root link');
    await _tapLink(tester, 'Nested link');
    await tester.tap(_image);
    await tester.pump();
    expect(events, [
      'new:interaction',
      'new:url:https://example.test/root',
      'new:interaction',
      'new:url:https://example.test/nested',
      'new:interaction',
      'new:image:https://example.test/image.jpg',
    ]);

    events.clear();
    await tester.pumpWidget(build('disabled', image: false));
    await tester.pumpAndSettle();
    await tester.tap(_image);
    await tester.pump();
    expect(events, isEmpty);

    await tester.pumpWidget(build('enabled'));
    await tester.pumpAndSettle();
    await tester.tap(_image);
    await tester.pump();
    expect(events, [
      'enabled:interaction',
      'enabled:image:https://example.test/image.jpg',
    ]);
    expect(tester.element(_body()), same(bodyElement));
    expect(tester.element(_body('rebind-fold-content')), same(nestedElement));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached fallback fold labels update without losing expansion', (
    tester,
  ) async {
    const html =
        '<div id="fold" class="showcollapse_box">'
        '<div class="showcollapse_content"><p>Expanded content</p></div></div>';
    final semantics = tester.ensureSemantics();
    try {
      final presentation = ForumHtmlBodyPresentation();
      addTearDown(presentation.dispose);
      Widget build(Locale locale) =>
          _host(html: html, locale: locale, bodyPresentation: presentation);
      AppLocalizations labels() =>
          AppLocalizations.of(tester.element(find.byType(Scaffold)));
      await tester.pumpWidget(build(const Locale('zh')));
      await tester.pumpAndSettle();
      final firstLabels = labels();
      expect(
        find.text(firstLabels.threadHtmlCollapseContent, findRichText: true),
        findsOneWidget,
      );
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      final bodyElement = tester.element(_body());
      final nestedElement = tester.element(_body('rebind-fold-content'));

      await tester.pumpWidget(build(const Locale('zh', 'TW')));
      await tester.pumpAndSettle();
      final currentLabels = labels();
      expect(
        currentLabels.threadHtmlCollapseContent,
        isNot(firstLabels.threadHtmlCollapseContent),
      );
      expect(
        find.text(currentLabels.threadHtmlCollapseContent, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text(firstLabels.threadHtmlCollapseContent, findRichText: true),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape(currentLabels.threadHtmlCollapseExpanded)),
        ),
        findsOneWidget,
      );
      expect(find.text('Expanded content', findRichText: true), findsOneWidget);
      expect(tester.element(_body()), same(bodyElement));
      expect(tester.element(_body('rebind-fold-content')), same(nestedElement));
      expect(presentation.collapseExpansion, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'paragraph spacing updates the cached visual gap and body height',
    (tester) async {
      const html = '<p>First paragraph</p><p>Second paragraph</p>';
      final defaults = ForumHtmlReaderPreferences.defaults();
      Widget build(double spacing) => _host(
        html: html,
        contentLayout: ForumHtmlContentLayout.compact,
        preferences: defaults.copyWith(
          typography: defaults.typography.copyWith(paragraphSpacing: spacing),
        ),
      );
      double gap() =>
          tester
              .getTopLeft(find.text('Second paragraph', findRichText: true))
              .dy -
          tester
              .getBottomLeft(find.text('First paragraph', findRichText: true))
              .dy;
      await tester.pumpWidget(build(4));
      await tester.pumpAndSettle();
      final firstGap = gap();
      final firstHeight = tester.getSize(_body()).height;
      await tester.pumpWidget(build(28));
      await tester.pumpAndSettle();

      expect(gap(), greaterThan(firstGap + 10));
      expect(tester.getSize(_body()).height, greaterThan(firstHeight + 10));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('quote palette changes update the cached painted surface', (
    tester,
  ) async {
    const html =
        '<div class="quote"><blockquote>Quoted body</blockquote></div>';
    const nextColor = Color(0xFFEEDDCC);
    final nextTheme = ForumHtmlThemeContext(
      brightness: forumHtmlTestTheme.brightness,
      surface: forumHtmlTestTheme.surface,
      foreground: forumHtmlTestTheme.foreground,
      link: forumHtmlTestTheme.link,
      quoteSurface: nextColor,
      quoteForeground: forumHtmlTestTheme.quoteForeground,
      codeSurface: forumHtmlTestTheme.codeSurface,
      codeForeground: forumHtmlTestTheme.codeForeground,
    );
    Finder surface(Color color) => find.descendant(
      of: _body(),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == color,
      ),
    );
    await tester.pumpWidget(_host(html: html));
    await tester.pumpAndSettle();
    expect(surface(forumHtmlTestTheme.quoteSurface), findsOneWidget);
    await tester.pumpWidget(_host(html: html, theme: nextTheme));
    await tester.pumpAndSettle();

    expect(surface(nextColor), findsOneWidget);
    expect(surface(forumHtmlTestTheme.quoteSurface), findsNothing);
    expect(find.text('Quoted body', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final _appTheme = ThemeData.light();
final _toggle = find.byKey(const Key('forum-html-collapse-toggle-rebind-fold'));
final _image = find.byKey(const Key('rebind-fake-image'));
Finder _body([String sourceId = 'rebind']) =>
    find.byKey(Key('forum-html-renderer-$sourceId'));

Future<void> _tapLink(WidgetTester tester, String text) async {
  final rect = tester.getRect(find.text(text, findRichText: true));
  // RichText can fill the paragraph width; hit the actual leading glyphs.
  await tester.tapAt(rect.topLeft + Offset(10, rect.height / 2));
  await tester.pump();
}

Widget _host({
  required String html,
  ForumHtmlThemeContext theme = forumHtmlTestTheme,
  ForumHtmlReaderPreferences? preferences,
  ForumHtmlRenderCallbacks callbacks = const ForumHtmlRenderCallbacks(),
  ForumHtmlImageHost? imageHost,
  ForumHtmlBodyPresentation? bodyPresentation,
  ForumHtmlContentLayout contentLayout = ForumHtmlContentLayout.document,
  Locale locale = const Locale('zh'),
}) => LocalizedTestApp(
  theme: _appTheme,
  themeAnimationDuration: Duration.zero,
  locale: locale,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: ForumHtmlWidgetPostRenderer(
            html: html,
            sourceId: 'rebind',
            theme: theme,
            preferences: preferences,
            callbacks: callbacks,
            imageHost: imageHost,
            bodyPresentation: bodyPresentation,
            contentLayout: contentLayout,
            buildAsync: false,
            enableCaching: true,
          ),
        ),
      ),
    ),
  ),
);

final class _Images implements ForumHtmlImageHost {
  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _Image(url.toString(), isSticker, htmlSize);

  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) async => null;

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {}

  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {}

  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) => const ColoredBox(
    key: Key('rebind-fake-image'),
    color: Color(0xFF445566),
    child: SizedBox.expand(),
  );
}

final class _Image implements ForumHtmlDisplayImage {
  const _Image(this.sourceUrl, this.isSticker, this.htmlSize);

  @override
  final String sourceUrl;
  @override
  final bool isSticker;
  @override
  final Size? htmlSize;
  @override
  String get cacheKey => 'fake:$sourceUrl';
  @override
  Object get identity => (sourceUrl, isSticker, htmlSize);
  @override
  ForumHtmlImageLayout get initialLayout =>
      ForumHtmlImageLayout(aspectRatio: htmlSize?.aspectRatio ?? 0.7);
}
