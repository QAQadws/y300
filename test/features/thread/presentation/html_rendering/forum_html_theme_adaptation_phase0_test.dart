import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_preparer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/css_author_color_parser.dart';
import 'forum_html_test_theme.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';

const _fixturePath =
    'test/features/thread/presentation/html_rendering/fixtures/'
    'forum_html_theme_adaptation_minimal.html';

void main() {
  group('Phase 0 author color characterization', () {
    late String fixtureHtml;

    setUpAll(() {
      fixtureHtml = utf8.decode(File(_fixturePath).readAsBytesSync());
    });

    test('minimal fixture remains a standalone UTF-8 test resource', () {
      final fragment = html_parser.parseFragment(fixtureHtml);

      expect(fragment.querySelectorAll('font'), hasLength(3));
      expect(fragment.querySelectorAll('span'), hasLength(1));
      expect(fragment.text!.trimRight(), '浅色强调\n深色主题不可读正文\n可能可保留的标题\n隐藏文字');
    });

    test('default preparation adapts colors without mutating source HTML', () {
      final sourceBeforePrepare = fixtureHtml;
      final preferences = ForumHtmlReaderPreferences.defaults();

      final prepared = const DefaultForumHtmlRenderPreparer().prepare(
        html: fixtureHtml,
        preferences: preferences,
        theme: forumHtmlTestTheme,
        sourceId: 'phase0-author-colors',
        threadId: 'phase0',
        imageCacheOwnerId: null,
      );
      final fragment = html_parser.parseFragment(prepared.preparedHtml);
      final fonts = fragment.querySelectorAll('font');
      final concealedText = fragment.querySelector('span')!;
      const colorParser = CsslibAuthorColorParser();
      final highlightStyle = colorParser.parseOwn(fonts[0]);
      final blackTextStyle = colorParser.parseOwn(fonts[1]);
      final blueTitleStyle = colorParser.parseOwn(fonts[2]);
      final concealedStyle = colorParser.parseOwn(concealedText);

      expect(highlightStyle.background, isNotNull);
      expect(highlightStyle.background!.toARGB32(), isNot(0xFFFCF4CF));
      expect(blackTextStyle.foreground?.toARGB32(), 0xFF000000);
      expect(blueTitleStyle.foreground, isNotNull);
      expect(fonts[1].attributes['color'], isNull);
      expect(fonts[2].attributes['color'], isNull);
      expect(concealedStyle.foreground, concealedStyle.background);
      expect(prepared.themeAdaptationStats.remappedBackgroundCount, 2);
      expect(
        prepared.themeAdaptationStats.remappedForegroundCount,
        greaterThan(0),
      );
      expect(prepared.themeAdaptationStats.concealedTextRangeCount, 1);
      expect(fixtureHtml, sourceBeforePrepare);
      expect(prepared.preparedHtml, contains('深色主题不可读正文'));
      expect(prepared.preparedHtml, contains('隐藏文字'));
    });
  });

  group('Phase 0 reading palette characterization', () {
    test('thread light and dark surfaces use the production palettes', () {
      final light = ThreadDetailNativePalette.resolve(AppTheme.light());
      final dark = ThreadDetailNativePalette.resolve(AppTheme.dark());

      expect(_threadPaletteSnapshot(light), <String, int>{
        'background': 0xFFF8F8E1,
        'surface': 0xFFFEF2DB,
        'foreground': 0xFF4F3A2A,
        'link': 0xFF531104,
        'muted': 0xFF7D6750,
      });
      expect(_threadPaletteSnapshot(dark), <String, int>{
        'background': 0xFF17110F,
        'surface': 0xFF241916,
        'foreground': 0xFFF6E8DD,
        'link': 0xFF2A0903,
        'muted': 0xFFD7C2B6,
      });
    });

    test('novel light, dark, and sepia use their reader palettes', () {
      const resolver = NovelReaderThemeResolver();
      final light = resolver.resolve(
        preferences: NovelReaderPreferences.defaults().copyWith(
          themePreset: NovelReaderThemePreset.light,
        ),
        theme: AppTheme.light(),
        platformBrightness: Brightness.light,
      );
      final dark = resolver.resolve(
        preferences: NovelReaderPreferences.defaults().copyWith(
          themePreset: NovelReaderThemePreset.dark,
        ),
        theme: AppTheme.dark(),
        platformBrightness: Brightness.light,
      );
      final sepia = resolver.resolve(
        preferences: NovelReaderPreferences.defaults().copyWith(
          themePreset: NovelReaderThemePreset.sepia,
        ),
        theme: AppTheme.light(),
        platformBrightness: Brightness.dark,
      );

      expect(_novelPaletteSnapshot(light), <String, int>{
        'background': 0xFFFDFDFD,
        'foreground': 0xFF1F1F1F,
        'muted': 0xFF737373,
        'accent': 0xFF8A5A2B,
        'surface': 0xFFF8F8E1,
        'link': 0xFF8A5A2B,
        'quoteSurface': 0xFFF1F1F1,
      });
      expect(_novelPaletteSnapshot(dark), <String, int>{
        'background': 0xFF141414,
        'foreground': 0xFFE9E9E9,
        'muted': 0xFFAAA39A,
        'accent': 0xFFE8B884,
        'surface': 0xFF202020,
        'link': 0xFF8DB7FF,
        'quoteSurface': 0xFF242424,
      });
      expect(_novelPaletteSnapshot(sepia), <String, int>{
        'background': 0xFFF4EAD7,
        'foreground': 0xFF4C3A21,
        'muted': 0xFF8B7355,
        'accent': 0xFF7A5A28,
        'surface': 0xFFEFE0C4,
        'link': 0xFF6A55A3,
        'quoteSurface': 0xFFE8D8B8,
      });
    });
  });

  test('prepares a deterministic 60 KiB long body baseline', () {
    final longBody = _buildLongBody();
    final byteLength = utf8.encode(longBody).length;
    const preparer = DefaultForumHtmlRenderPreparer();
    final stopwatch = Stopwatch()..start();
    final first = preparer.prepare(
      html: longBody,
      preferences: ForumHtmlReaderPreferences.defaults(),
      theme: forumHtmlTestTheme,
      sourceId: 'phase0-long-body',
      threadId: '573549',
      imageCacheOwnerId: null,
    );
    final firstElapsedMicros = stopwatch.elapsedMicroseconds;
    stopwatch
      ..reset()
      ..start();
    final second = preparer.prepare(
      html: longBody,
      preferences: ForumHtmlReaderPreferences.defaults(),
      theme: forumHtmlTestTheme,
      sourceId: 'phase0-long-body',
      threadId: '573549',
      imageCacheOwnerId: null,
    );
    final secondElapsedMicros = stopwatch.elapsedMicroseconds;
    stopwatch.stop();

    // Kept as diagnostic output instead of a timing assertion because host
    // performance varies. The stable input and output make later comparisons
    // reproducible.
    // ignore: avoid_print
    print(
      'PHASE0_HTML_PREPARE_BASELINE '
      'utf8Bytes=$byteLength '
      'firstMicros=$firstElapsedMicros '
      'secondMicros=$secondElapsedMicros',
    );
    expect(byteLength, inInclusiveRange(60 * 1024, 62 * 1024));
    expect(first.preparedHtml, second.preparedHtml);
    expect(first.sequence.entries, hasLength(first.totalImageCount));
    expect(first.totalImageCount, greaterThan(100));
    expect(
      first.preparedHtml,
      isNot(contains('background-color: rgb(252, 244, 207)')),
    );
    expect(first.preparedHtml, isNot(contains('color="black"')));
    expect(first.themeAdaptationStats.explicitForegroundCount, greaterThan(0));
    expect(first.themeAdaptationStats.explicitBackgroundCount, greaterThan(0));
  });
}

Map<String, int> _threadPaletteSnapshot(ThreadDetailNativePalette palette) {
  return <String, int>{
    'background': palette.background.toARGB32(),
    'surface': palette.card.toARGB32(),
    'foreground': palette.bodyText.toARGB32(),
    'link': palette.accent.toARGB32(),
    'muted': palette.muted.toARGB32(),
  };
}

Map<String, int> _novelPaletteSnapshot(NovelReaderPalette palette) {
  return <String, int>{
    'background': palette.background.toARGB32(),
    'foreground': palette.foreground.toARGB32(),
    'muted': palette.muted.toARGB32(),
    'accent': palette.accent.toARGB32(),
    'surface': palette.surface.toARGB32(),
    'link': palette.link.toARGB32(),
    'quoteSurface': palette.quoteBackground.toARGB32(),
  };
}

String _buildLongBody() {
  final buffer = StringBuffer();
  var byteLength = 0;
  var index = 0;
  while (byteLength < 60 * 1024) {
    final chunk =
        '<div class="phase0-section">'
        '<font color="#99BBF1"><strong>第 $index 节测试标题</strong></font>'
        '<br>'
        '<span style="background-color: rgb(252, 244, 207)">'
        '这是用于固定长正文准备行为的匿名内容，包含历史 Discuz 常见的嵌套节点。'
        '</span>'
        '<font color="black">深色主题下当前仍会保留的正文颜色。</font>'
        '<a href="forum.php?mod=viewthread&amp;tid=573549">章节链接</a>'
        '<img id="aimg_$index" '
        'src="data/attachment/forum/phase0-$index.jpg">'
        '</div>';
    buffer.write(chunk);
    byteLength += utf8.encode(chunk).length;
    index++;
  }
  return buffer.toString();
}
