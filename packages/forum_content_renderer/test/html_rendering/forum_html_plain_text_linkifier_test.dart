import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import 'render_test_support.dart';

void main() {
  test(
    'default keeps prepared HTML unchanged and opt-in changes cache identity',
    () {
      const html = '<p>https://bbs.yamibo.com/thread-123-2-1.html</p>';
      final original = prepareRenderTestDocument(html);
      final enabled = prepareRenderTestDocument(html, options: _options);
      expect(original.preparedHtml, html);
      expect(_fragment(original.preparedHtml).querySelector('a'), isNull);
      expect(
        _fragment(enabled.preparedHtml).querySelector('a')?.attributes['href'],
        _url,
      );
      expect(_options, isNot(renderTestOptions));
      expect({_options, renderTestOptions}, hasLength(2));
      expect(_options.copyWith(enablePlainTextLinks: false), renderTestOptions);
      expect(_options.copyWith(), _options);
    },
  );

  test(
    'only display preparation changes; decoded text and inline styles survive',
    () {
      const html =
          '<p>😀看这里：<strong><span style="font-size:24px;color:#b00020">'
          'https://bbs.yamibo.com/thread-123-2-1.html</span></strong>，谢谢。</p>';
      final original = _fragment(prepareRenderTestDocument(html).preparedHtml);
      final enabled = _fragment(
        prepareRenderTestDocument(html, options: _options).preparedHtml,
      );
      expect(enabled.text, original.text);
      expect(
        enabled.querySelector('span')?.attributes,
        original.querySelector('span')?.attributes,
      );
      expect(enabled.querySelector('strong span a')?.attributes['href'], _url);
      expect(
        enabled.querySelector('a')?.attributes['style'],
        contains(_color(original.querySelector('span')!.attributes['style']!)),
      );
      expect(
        html,
        contains('https://bbs.yamibo.com/thread-123-2-1.html</span>'),
      );
    },
  );

  test(
    'existing anchors, code, hidden ancestors and non-content text are untouched',
    () {
      const html =
          '<a href="$_url"><b>$_url</b></a>'
          '<code>$_url</code><pre>$_url</pre><div class="blockcode"><span>$_url</span></div>'
          '<div hidden><span>$_url</span></div>'
          '<span style="display: none !important">$_url</span>'
          '<div style="visibility: hidden"><b>$_url</b></div>'
          '<span style="opacity:0">$_url</span>'
          '<script>$_url</script><style>$_url</style><textarea>$_url</textarea>'
          '<p>$_url</p>';
      final fragment = _fragment(
        prepareRenderTestDocument(html, options: _options).preparedHtml,
      );
      expect(fragment.querySelectorAll('a'), hasLength(2));
      expect(fragment.querySelector('a a'), isNull);
      for (final selector in [
        'code',
        'pre',
        '.blockcode',
        '[hidden]',
        'script',
        'style',
        'textarea',
      ]) {
        expect(fragment.querySelector(selector)?.querySelector('a'), isNull);
      }
      expect(fragment.querySelector('p a')?.attributes['href'], _url);
    },
  );

  test(
    'does not create valid-looking prefixes from URLs split by inline markup',
    () {
      const html =
          '<p>https://bbs.yamibo.com/thread-<b>123-2-1.html</b></p>'
          '<p>https://bbs.<span>yamibo.com</span>/thread-123-2-1.html</p>'
          '<p>https://<i>example.com</i>/page</p>'
          '<p><span>$_url</span> 和 <em>https://example.net/a</em>。</p>';
      final fragment = _fragment(
        prepareRenderTestDocument(html, options: _options).preparedHtml,
      );
      expect(
        fragment.querySelectorAll('a').map((link) => link.attributes['href']),
        [_url, 'https://example.net/a'],
      );
      expect(fragment.text, _fragment(html).text);
    },
  );

  test(
    'long text runs link later URLs without silently truncating body content',
    () {
      final html = '<p>${'正文 ' * 25000} $_url</p>';
      final fragment = _fragment(
        prepareRenderTestDocument(html, options: _options).preparedHtml,
      );
      expect(fragment.querySelector('a')?.attributes['href'], _url);
      expect(fragment.text, _fragment(html).text);
    },
  );

  test(
    'excluded inline contents only reject crossing URLs and never supply new links',
    () {
      const html =
          '<p>https://bbs.yamibo.com/thread-<code>123-2-1.html</code></p>'
          '<p>https://bbs.yamibo.com/thread-<a href="https://example.com">123-2-1.html</a></p>'
          '<p>https://bbs.yamibo.com/thread-<span hidden>123-2-1.html</span></p>'
          '<p><code>javaScript:</code>https://example.com/embedded</p>'
          '<p><code>prefix</code>https://example.com/word-embedded</p>'
          '<p>$_url <code>example code</code> https://example.net/valid</p>'
          '<p>$_url</p><pre>https://example.org/code-only</pre>';
      final fragment = _fragment(
        prepareRenderTestDocument(html, options: _options).preparedHtml,
      );
      expect(
        fragment.querySelectorAll('a').map((link) => link.attributes['href']),
        [
          'https://example.com', // Existing anchor preserved as-is.
          _url,
          'https://example.net/valid',
          _url,
        ],
      );
      expect(fragment.querySelectorAll('code a, pre a, [hidden] a'), isEmpty);
      expect(fragment.text, _fragment(html).text);
    },
  );

  test(
    'empty excluded inline nodes cannot expose a valid-looking URL prefix',
    () {
      final deepNonEmpty = '${'<span>' * 40}123-2-1.html${'</span>' * 40}';
      final html =
          '<p>https://bbs.yamibo.com/thread-<code></code>123-2-1.html</p>'
          '<p>https://bbs.yamibo.com/thread-<span hidden></span>123-2-1.html</p>'
          '<p>https://bbs.yamibo.com/thread-<code><b></b></code>123-2-1.html</p>'
          '<p>https://bbs.yamibo.com/thread-<code>$deepNonEmpty</code></p>'
          '<p>$_url<code></code></p><p>中文下一段。</p>'
          '<p>$_url<span hidden></span></p>';
      final fragment = _fragment(
        prepareRenderTestDocument(html, options: _options).preparedHtml,
      );
      expect(
        fragment.querySelectorAll('a').map((link) => link.attributes['href']),
        [_url, _url],
      );
      expect(fragment.text, _fragment(html).text);
    },
  );

  test(
    'hard DOM breaks do not turn obvious URL prefixes into separate destinations',
    () {
      const html =
          '<p>https://bbs.yamibo.com/<br>thread-123-2-1.html</p>'
          '<p>https://bbs.yamibo.com</p><p>/forum.php?mod=viewthread&amp;tid=123</p>'
          '<p>https://bbs.yamibo.com/thread-123-<br><b>2-1.html</b></p>'
          '<p>https://example.com/<br>https://example.net/a</p>'
          '<p>$_url</p><p>中文正文继续。</p>';
      final fragment = _fragment(
        prepareRenderTestDocument(html, options: _options).preparedHtml,
      );
      expect(
        fragment.querySelectorAll('a').map((link) => link.attributes['href']),
        ['https://example.com/', 'https://example.net/a', _url],
      );
      expect(fragment.text, _fragment(html).text);
    },
  );

  testWidgets(
    'native fold can reveal URLs behind Discuz display:none while ordinary hidden remains skipped',
    (tester) async {
      const html =
          '<div class="showcollapse_box" id="real-fold">'
          '<div class="showcollapse_title">fold title</div>'
          '<div class="showcollapse_content" style="display:none"><p>$_url</p>'
          '<div class="showcollapse_gather">https://example.com/gather</div></div></div>'
          '<div class="showcollapse_content" style="display:none">https://example.com/ordinary-hidden</div>'
          '<div hidden>https://example.com/hidden</div>';
      final document = prepareRenderTestDocument(html, options: _options);
      expect(
        _fragment(
          document.preparedHtml,
        ).querySelectorAll('a').map((link) => link.attributes['href']),
        [_url],
      );
      final taps = <String>[];
      await tester.pumpWidget(
        _app(
          document,
          options: _options,
          onTapUrl: (url) {
            taps.add(url);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().contains(_url),
        ),
        findsNothing,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('fold title'),
        ),
      );
      await tester.pumpAndSettle();
      (_spanFor(_paragraph(tester, _url).text, _url)!.recognizer!
              as TapGestureRecognizer)
          .onTap!();
      expect(taps, [_url]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'plain and existing links each open once with unchanged typography',
    (tester) async {
      final taps = <String>[];
      const html =
          '<p><strong style="font-size:24px;color:#b00020">$_url</strong></p>'
          '<p><a href="https://example.com">existing</a></p>';
      final original = prepareRenderTestDocument(html);
      await tester.pumpWidget(_app(original));
      await tester.pumpAndSettle();
      final originalParagraph = _paragraph(tester, _url);
      final originalStyle = _spanFor(originalParagraph.text, _url)!.style;
      final originalHeight = tester
          .getSize(find.byWidget(originalParagraph))
          .height;

      await tester.pumpWidget(
        _app(
          prepareRenderTestDocument(html, options: _options),
          options: _options,
          onTapUrl: (url) {
            taps.add(url);
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = _paragraph(tester, _url);
      final span = _spanFor(paragraph.text, _url)!;
      expect(span.style?.fontSize, originalStyle?.fontSize);
      expect(span.style?.fontWeight, originalStyle?.fontWeight);
      expect(span.style?.height, originalStyle?.height);
      expect(span.style?.color, originalStyle?.color);
      expect(tester.getSize(find.byWidget(paragraph)).height, originalHeight);
      (span.recognizer! as TapGestureRecognizer).onTap!();
      (_spanFor(_paragraph(tester, 'existing').text, 'existing')!.recognizer!
              as TapGestureRecognizer)
          .onTap!();
      expect(taps, [_url, 'https://example.com']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cached callback updates do not remount the generated link body',
    (tester) async {
      final document = prepareRenderTestDocument(
        '<p>$_url</p>',
        options: _options,
      );
      var first = 0;
      var second = 0;
      await tester.pumpWidget(
        _app(
          document,
          options: _options,
          onTapUrl: (_) {
            first++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      final body = tester.element(
        find.byKey(const Key('forum-html-renderer-link-test')),
      );
      await tester.pumpWidget(
        _app(
          document,
          options: _options,
          onTapUrl: (_) {
            second++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      (_spanFor(_paragraph(tester, _url).text, _url)!.recognizer!
              as TapGestureRecognizer)
          .onTap!();
      expect(first, 0);
      expect(second, 1);
      expect(
        tester.element(find.byKey(const Key('forum-html-renderer-link-test'))),
        same(body),
      );
    },
  );
}

const _url = 'https://bbs.yamibo.com/thread-123-2-1.html';
final _options = renderTestOptions.copyWith(enablePlainTextLinks: true);

html_dom.DocumentFragment _fragment(String html) =>
    html_parser.parseFragment(html);

String _color(String style) => const CssInlineStyleDeclarationCodec()
    .tryParse(style)!
    .effectiveDeclaration({'color'})!
    .value;

Widget _app(
  ForumHtmlPreparedRenderDocument document, {
  ForumHtmlRenderOptions options = renderTestOptions,
  bool Function(String)? onTapUrl,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 240,
      child: ForumHtmlRenderer(
        preparedDocument: document,
        theme: forumHtmlTestTheme,
        options: options,
        labels: renderTestLabels,
        callbacks: ForumHtmlRenderCallbacks(onTapUrl: onTapUrl),
        sourceId: 'link-test',
        buildAsync: false,
        enableCaching: true,
      ),
    ),
  ),
);

RichText _paragraph(WidgetTester tester, String text) =>
    tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains(text),
      ),
    );

TextSpan? _spanFor(InlineSpan span, String text) {
  if (span is! TextSpan) return null;
  if (span.text?.contains(text) ?? false) return span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    final found = _spanFor(child, text);
    if (found != null) return found;
  }
  return null;
}
