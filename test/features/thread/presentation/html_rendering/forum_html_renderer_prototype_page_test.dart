import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_sample_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_renderer_prototype_page.dart';

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
      MaterialApp(
        home: ForumHtmlRendererPrototypePage(
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
    expect(find.textContaining('第一个样例', findRichText: true), findsOneWidget);

    expect(find.byKey(const Key('forum-html-renderer-one')), findsOneWidget);
  });

  testWidgets('switches selected sample and reloads asset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ForumHtmlRendererPrototypePage(
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

  testWidgets('shows missing local asset message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ForumHtmlRendererPrototypePage(
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
