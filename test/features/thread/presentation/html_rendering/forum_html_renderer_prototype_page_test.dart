import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_sample_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_renderer_prototype_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/widgets/forum_collapse_block.dart';

void main() {
  const samples = <ForumHtmlSampleDocument>[
    ForumHtmlSampleDocument(
      id: 'one',
      title: '样例一',
      assetPath: 'assets/prototypes/forum_html/one.html',
      sourceDocPath: 'docs/html/特殊格式/one.html',
    ),
    ForumHtmlSampleDocument(
      id: 'two',
      title: '样例二',
      assetPath: 'assets/prototypes/forum_html/two.html',
      sourceDocPath: 'docs/html/特殊格式/two.html',
    ),
  ];

  testWidgets('shows sample choices and renders loaded fragment', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithProviders(
        ForumHtmlRendererPrototypePage(
          samples: samples,
          assetBundle: _FakeAssetBundle(
            assets: const <String, String>{
              'assets/prototypes/forum_html/one.html':
                  '<html><body><div class="message">'
                  '<p><a href="thread.html">第一个样例链接</a></p>'
                  '</div></body></html>',
              'assets/prototypes/forum_html/two.html':
                  '<html><body><div class="message">第二个样例</div></body></html>',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HTML 正文渲染原型'), findsOneWidget);
    expect(
      find.byKey(const Key('forum-html-prototype-sample-one')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('forum-html-prototype-sample-two')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('forum-html-prototype-debug-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('样例：样例一'), findsOneWidget);
    expect(find.textContaining('原 HTML：'), findsOneWidget);
    expect(find.textContaining('正文 fragment：'), findsOneWidget);
    expect(find.textContaining('转换模式：原文'), findsOneWidget);
    expect(find.textContaining('转换文本节点：0 个'), findsOneWidget);
    expect(find.textContaining('字号 100%'), findsOneWidget);
    expect(find.textContaining('作者样式：字号保留'), findsOneWidget);
    expect(
      find.byKey(const Key('forum-html-prototype-reader-settings-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('forum-html-prototype-conversion-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('forum-html-prototype-conversion-none')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('forum-html-prototype-conversion-simplified')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('forum-html-prototype-conversion-traditional')),
      findsOneWidget,
    );
    expect(find.textContaining('第一个样例', findRichText: true), findsOneWidget);

    expect(find.byKey(const Key('forum-html-renderer-one')), findsOneWidget);
  });

  testWidgets('switches selected sample and reloads asset', (tester) async {
    await tester.pumpWidget(
      _wrapWithProviders(
        ForumHtmlRendererPrototypePage(
          samples: samples,
          assetBundle: _FakeAssetBundle(
            assets: const <String, String>{
              'assets/prototypes/forum_html/one.html':
                  '<html><body><div class="message">第一个样例</div></body></html>',
              'assets/prototypes/forum_html/two.html':
                  '<html><body><div class="message">第二个样例</div></body></html>',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('第一个样例', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(const Key('forum-html-prototype-sample-two')));
    await tester.pumpAndSettle();

    expect(find.textContaining('第二个样例', findRichText: true), findsOneWidget);
  });

  testWidgets('renders thread detail samples as full post lists', (
    tester,
  ) async {
    const threadSample = ForumHtmlSampleDocument(
      id: 'thread',
      title: '完整帖子',
      assetPath: 'assets/prototypes/forum_html/thread.html',
      sourceDocPath: 'docs/html/特殊格式/thread.html',
      renderMode: ForumHtmlSampleRenderMode.threadDetail,
    );

    await tester.pumpWidget(
      _wrapWithProviders(
        ForumHtmlRendererPrototypePage(
          samples: const <ForumHtmlSampleDocument>[threadSample],
          assetBundle: _FakeAssetBundle(
            assets: const <String, String>{
              'assets/prototypes/forum_html/thread.html': _mobileThreadHtml,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('forum-html-prototype-thread-loaded-view')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('forum-html-prototype-thread-debug-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('帖子：完整帖子标题'), findsOneWidget);
    expect(find.textContaining('楼层：2 个'), findsOneWidget);
    expect(find.byKey(const Key('thread-detail-list')), findsOneWidget);
    expect(find.textContaining('第一层正文', findRichText: true), findsOneWidget);
    expect(find.textContaining('第二层正文', findRichText: true), findsOneWidget);
  });

  testWidgets('jitter sample records and copies scroll diagnostics', (
    tester,
  ) async {
    const jitterSample = ForumHtmlSampleDocument(
      id: 'jitter_test',
      title: '抖动测试',
      assetPath: 'assets/prototypes/forum_html/jitter.html',
      sourceDocPath: 'docs/html/特殊格式/抖动测试.html',
      renderMode: ForumHtmlSampleRenderMode.threadDetail,
    );
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<Object?, Object?>)['text']! as String;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      _wrapWithProviders(
        ForumHtmlRendererPrototypePage(
          samples: const <ForumHtmlSampleDocument>[jitterSample],
          assetBundle: _FakeAssetBundle(
            assets: const <String, String>{
              'assets/prototypes/forum_html/jitter.html': _mobileThreadHtml,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('forum-html-prototype-jitter-log-panel')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('forum-html-prototype-jitter-log-switch')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('forum-html-prototype-jitter-log-switch')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('forum-html-prototype-jitter-log-copy')),
    );
    await tester.pump();

    expect(copiedText, isNotNull);
    expect(copiedText, contains('session-start sample=jitter_test'));
    expect(copiedText, contains('scroll'));
    expect(copiedText, contains('session-stop'));
  });

  testWidgets('renders and expands collapse directory sample content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithProviders(
        ForumHtmlRendererPrototypePage(
          samples: samples,
          assetBundle: _FakeAssetBundle(
            assets: const <String, String>{
              'assets/prototypes/forum_html/one.html':
                  '<html><body><div class="message">'
                  '<div id="toc" class="showcollapse_box">'
                  '<div class="showcollapse_title">折叠目录</div>'
                  '<div class="showcollapse_content">'
                  '<a href="thread.html">目录链接</a>'
                  '</div>'
                  '</div>'
                  '</div></body></html>',
              'assets/prototypes/forum_html/two.html':
                  '<html><body><div class="message">第二个样例</div></body></html>',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ForumCollapseBlock), findsOneWidget);
    expect(find.textContaining('目录链接', findRichText: true), findsNothing);

    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-one-toc')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('目录链接', findRichText: true), findsOneWidget);
    final nestedRenderer = tester.widget<HtmlWidget>(
      find.byKey(const Key('forum-html-renderer-one-toc-content')),
    );
    await nestedRenderer.onTapUrl?.call('https://bbs.yamibo.com/thread.html');
    await tester.pump();

    expect(
      find.textContaining('链接：https://bbs.yamibo.com/thread.html'),
      findsOneWidget,
    );
  });

  testWidgets('switches conversion mode and renders converted html', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithProviders(
        ForumHtmlRendererPrototypePage(
          samples: samples,
          assetBundle: _FakeAssetBundle(
            assets: const <String, String>{
              'assets/prototypes/forum_html/one.html':
                  '<html><body><div class="message">第一个样例</div></body></html>',
              'assets/prototypes/forum_html/two.html':
                  '<html><body><div class="message">第二个样例</div></body></html>',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('forum-html-prototype-conversion-traditional')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('第一个樣例', findRichText: true), findsOneWidget);
    expect(find.textContaining('转换模式：转繁'), findsOneWidget);
    expect(find.textContaining('转换器：fake:toTraditional'), findsOneWidget);
    expect(find.textContaining('转换文本节点：1 个'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forum-html-prototype-sample-two')));
    await tester.pumpAndSettle();

    expect(find.textContaining('第二个樣例', findRichText: true), findsOneWidget);
    expect(find.textContaining('转换模式：转繁'), findsOneWidget);
  });

  testWidgets('reader settings sheet updates preview summary', (tester) async {
    await tester.pumpWidget(
      _wrapWithProviders(
        ForumHtmlRendererPrototypePage(
          samples: samples,
          assetBundle: _FakeAssetBundle(
            assets: const <String, String>{
              'assets/prototypes/forum_html/one.html':
                  '<html><body><div class="message">'
                  '<p style="font-size: 24px; color: red; '
                  'background-color: yellow">第一个样例</p>'
                  '</div></body></html>',
              'assets/prototypes/forum_html/two.html':
                  '<html><body><div class="message">第二个样例</div></body></html>',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('forum-html-prototype-reader-settings-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('forum-html-reader-font-scale-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('forum-html-reader-line-height-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('forum-html-reader-paragraph-spacing-slider')),
      findsOneWidget,
    );

    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const Key('forum-html-reader-paragraph-spacing-slider')),
        matching: find.byType(Slider),
      ),
    );
    slider.onChanged?.call(24);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('forum-html-reader-preserve-font-size-switch')),
    );
    await tester.tap(
      find.byKey(const Key('forum-html-reader-preserve-color-switch')),
    );
    await tester.tap(
      find.byKey(const Key('forum-html-reader-preserve-background-switch')),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.textContaining('段距 24px'), findsOneWidget);
    expect(find.textContaining('作者样式：字号忽略 / 颜色忽略 / 背景忽略'), findsOneWidget);
  });

  testWidgets('shows missing local asset message', (tester) async {
    await tester.pumpWidget(
      _wrapWithProviders(
        ForumHtmlRendererPrototypePage(
          samples: samples,
          assetBundle: _FakeAssetBundle(assets: const <String, String>{}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('forum-html-prototype-error-state')),
      findsOneWidget,
    );
    expect(find.textContaining('本地样例未找到'), findsOneWidget);
    expect(find.textContaining(samples.first.sourceDocPath), findsOneWidget);
    expect(find.textContaining(samples.first.assetPath), findsOneWidget);
  });
}

const _mobileThreadHtml = '''
<!DOCTYPE html>
<html>
<body id="forum" class="pg_viewthread">
  <div class="viewthread">
    <div class="view_tit">完整帖子标题</div>
    <div class="plc cl" id="pid1001">
      <div class="display pione">
        <ul class="authi">
          <li class="mtit">
            <span class="z"><a href="home.php?mod=space&uid=11">Alice</a></span>
            <span class="y">1#</span>
          </li>
          <li class="mtime">发表于 2026-7-9 10:00</li>
        </ul>
      </div>
      <div class="message"><p>第一层正文</p></div>
    </div>
    <div class="plc cl" id="pid1002">
      <div class="display">
        <ul class="authi">
          <li class="mtit">
            <span class="z"><a href="home.php?mod=space&uid=12">Bob</a></span>
            <span class="y">2#</span>
          </li>
          <li class="mtime">发表于 2026-7-9 10:01</li>
        </ul>
      </div>
      <div class="message"><p>第二层正文</p></div>
    </div>
  </div>
</body>
</html>
''';

Widget _wrapWithProviders(
  Widget child, {
  ForumHtmlReaderPreferences? initialPreferences,
}) {
  final preferencesRepository = _FakeForumHtmlReaderPreferencesRepository(
    initialPreferences ?? ForumHtmlReaderPreferences.defaults(),
  );
  return ProviderScope(
    overrides: [
      forumHtmlReaderPreferencesRepositoryProvider.overrideWithValue(
        preferencesRepository,
      ),
      textConverterProvider.overrideWith(
        (ref, mode) => switch (mode) {
          TextConversionMode.none => _FakeTextConverter(mode),
          TextConversionMode.toSimplified => _FakeTextConverter(mode),
          TextConversionMode.toTraditional => _FakeTextConverter(mode),
        },
      ),
    ],
    child: MaterialApp(home: child),
  );
}

class _FakeForumHtmlReaderPreferencesRepository
    implements ForumHtmlReaderPreferencesRepository {
  _FakeForumHtmlReaderPreferencesRepository(this.current);

  ForumHtmlReaderPreferences current;

  @override
  Future<ForumHtmlReaderPreferences> load() async => current;

  @override
  Future<void> save(ForumHtmlReaderPreferences preferences) async {
    current = preferences;
  }
}

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle({required this.assets});

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final value = assets[key];
    if (value == null) {
      throw FlutterError('Unable to load asset: $key');
    }
    final bytes = utf8.encode(value);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

class _FakeTextConverter implements TextConverter {
  const _FakeTextConverter(this.mode);

  @override
  final TextConversionMode mode;

  @override
  String get id => 'fake:${mode.name}';

  @override
  Future<String> convertHtml(String html) async {
    return switch (mode) {
      TextConversionMode.none => html,
      TextConversionMode.toSimplified => html.replaceAll('樣', '样'),
      TextConversionMode.toTraditional => html.replaceAll('样', '樣'),
    };
  }
}
