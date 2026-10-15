import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_exclusion_policy.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_content_projection_batch_executor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('DomHtmlTextNodeConversionService', () {
    test(
      'production providers reuse fragments and forward actual work metrics',
      () async {
        const channel = MethodChannel('flutter_open_chinese_convert');
        final nativeCalls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          return ((call.arguments as List<Object?>).first as String).replaceAll(
            '臺',
            '台',
          );
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final service = container.read(htmlTextNodeConversionServiceProvider);
        final plainService = container.read(
          plainTextBatchConversionServiceProvider,
        );
        final converter = container.read(
          textConverterProvider(TextConversionMode.toSimplified),
        );
        expect(service, isA<DomHtmlTextNodeConversionService>());
        expect(plainService, isA<DefaultPlainTextBatchConversionService>());
        expect(converter, isA<IndependentTextValueConverter>());
        final fragments = List<String>.generate(
          30,
          (index) => '<p title="臺属性">臺正文$index</p>',
        );
        await service.convertAll(
          htmlFragments: fragments.sublist(0, 20),
          converter: converter,
        );
        final recorder = _RecordingDiagnosticRecorder();
        final executor = TextContentProjectionBatchExecutor(
          plainTextBatchConversionService: plainService,
          htmlTextNodeConversionService: service,
          diagnosticRecorder: recorder,
        );
        final result = await executor.convert(
          surface: TextConversionSurface.threadDetail,
          plainSources: const [],
          htmlFragments: fragments,
          converter: converter,
          sourceRevision: 'incremental',
        );
        expect(result.succeeded, isTrue);
        expect(result.htmlValues.map((value) => value.html), [
          for (var index = 0; index < 30; index++)
            '<p title="臺属性">台正文$index</p>',
        ]);
        expect(nativeCalls, hasLength(2));
        expect((nativeCalls.last.arguments as List<Object?>)[2], isTrue);
        expect(
          ((nativeCalls.last.arguments as List<Object?>).first as String).split(
            DefaultPlainTextBatchConversionService.delimiter,
          ),
          [for (var index = 20; index < 30; index++) '臺正文$index'],
        );
        final event = recorder.events.single;
        expect(event.cachedHtmlFragmentCount, 20);
        expect(event.parsedHtmlFragmentCount, 10);
        expect(event.deduplicatedHtmlFragmentCount, 0);
        expect(event.submittedHtmlPlainSourceCount, 10);
        expect(event.convertedTextNodeCount, 30);
        expect(event.failureType, isNull);
      },
    );

    test('appended fragments reuse old HTML and batch only new text', () async {
      final metrics = <HtmlTextNodeConversionMetrics>[];
      final converter = _MapTextConverter({'正文': '正文T'});
      final service = DomHtmlTextNodeConversionService(
        plainTextBatchConversionService: DefaultPlainTextBatchConversionService(
          maxCacheEntries: 0,
        ),
        metricsListener: metrics.add,
      );
      final fragments = List<String>.generate(
        30,
        (index) => '<p data-index="$index">正文$index</p>',
      );
      await service.convertAll(
        htmlFragments: fragments.sublist(0, 20),
        converter: converter,
      );
      final result = await service.convertAll(
        htmlFragments: fragments,
        converter: converter,
      );

      expect(result.map((value) => value.html), [
        for (var i = 0; i < 30; i++) '<p data-index="$i">正文T$i</p>',
      ]);
      expect(converter.callCount, 2);
      expect(
        converter.inputs.last.split(
          DefaultPlainTextBatchConversionService.delimiter,
        ),
        [for (var i = 20; i < 30; i++) '正文$i'],
      );
      expect(metrics.last.cachedHtmlFragmentCount, 20);
      expect(metrics.last.parsedHtmlFragmentCount, 10);
      expect(metrics.last.submittedPlainSourceCount, 10);
      expect(metrics.last.plainSourceCount, 30);
      expect(metrics.last.convertedTextNodeCount, 30);
      expect(metrics.last.cacheHit, isFalse);
    });

    test(
      'unknown stateful policies retain visits for each duplicate fragment',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final policy = _FirstParagraphExclusionPolicy();
        final service = DomHtmlTextNodeConversionService(
          metricsListener: metrics.add,
        );
        final converter = _MapTextConverter({'正文': '正文T'});
        final options = HtmlTextNodeConversionOptions(
          exclusionPolicies: [policy],
        );
        final result = await service.convertAll(
          htmlFragments: const ['<p>正文</p>', '<p>正文</p>'],
          converter: converter,
          options: options,
        );
        expect(result.map((value) => value.html), ['<p>正文</p>', '<p>正文T</p>']);
        expect(policy.paragraphVisits, 2);
        expect(metrics.last.parsedHtmlFragmentCount, 2);
        expect(metrics.last.deduplicatedHtmlFragmentCount, 0);
        final changedBatch = await service.convertAll(
          htmlFragments: const ['<p>正文</p>', '<p>正文</p>', '<p>正文</p>'],
          converter: converter,
          options: options,
        );
        expect(
          changedBatch.every((value) => value.html == '<p>正文T</p>'),
          isTrue,
        );
        expect(policy.paragraphVisits, 5);
        expect(metrics.last.cachedHtmlFragmentCount, 0);
        expect(metrics.last.parsedHtmlFragmentCount, 3);
      },
    );

    test(
      'profile policies with injected resolvers retain duplicate visits',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final resolver = _CountingSiteUrlResolver();
        final service = DomHtmlTextNodeConversionService(
          metricsListener: metrics.add,
        );
        final result = await service.convertAll(
          htmlFragments: const [
            '<p>正文</p><a href="home.php?mod=space&amp;uid=100">帳號</a>',
            '<p>正文</p><a href="home.php?mod=space&amp;uid=100">帳號</a>',
          ],
          converter: _MapTextConverter({'正文': '正文T', '帳號': '不可转换'}),
          options: HtmlTextNodeConversionOptions(
            exclusionPolicies: [
              YamiboUserProfileLinkExclusionPolicy(siteUrlResolver: resolver),
            ],
          ),
        );
        expect(
          result.every((fragment) => fragment.html.endsWith('>帳號</a>')),
          isTrue,
        );
        expect(resolver.calls, 2);
        expect(metrics.single.parsedHtmlFragmentCount, 2);
        expect(metrics.single.deduplicatedHtmlFragmentCount, 0);
      },
    );

    test(
      'duplicates and reordered fragments retain logical counts and order',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final converter = _MapTextConverter({
          '第一': '第一T',
          '第二': '第二T',
          '第三': '第三T',
        });
        final service = DomHtmlTextNodeConversionService(
          metricsListener: metrics.add,
        );
        const first = '<p>第一</p>';
        const second = '<p>第二<span>第三</span></p>';
        await service.convertAll(
          htmlFragments: const [first, second, first],
          converter: converter,
        );
        expect(metrics.last.parsedHtmlFragmentCount, 2);
        expect(metrics.last.deduplicatedHtmlFragmentCount, 1);
        expect(metrics.last.submittedPlainSourceCount, 3);
        final reordered = await service.convertAll(
          htmlFragments: const [second, first, first],
          converter: converter,
        );
        expect(reordered.map((value) => value.html), [
          '<p>第二T<span>第三T</span></p>',
          '<p>第一T</p>',
          '<p>第一T</p>',
        ]);
        expect(reordered.map((value) => value.convertedTextNodeCount), [
          2,
          1,
          1,
        ]);
        expect(metrics.last.convertedTextNodeCount, 4);
        expect(metrics.last.plainSourceCount, 4);
        expect(metrics.last.parsedHtmlFragmentCount, 0);
        expect(metrics.last.cachedHtmlFragmentCount, 3);
        expect(metrics.last.submittedPlainSourceCount, 0);
        expect(metrics.last.cacheHit, isTrue);
        expect(converter.callCount, 1);
      },
    );

    test(
      'a markup edit reparses the full changed fragment, not an inferred PID',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final converter = _MapTextConverter({'第一': '第一T', '第二': '第二T'});
        final service = DomHtmlTextNodeConversionService(
          metricsListener: metrics.add,
        );
        await service.convertAll(
          htmlFragments: const ['<p id="a">第一</p>', '<p id="b">第二</p>'],
          converter: converter,
        );
        final result = await service.convertAll(
          htmlFragments: const [
            '<p id="a">第一</p>',
            '<p id="b" class="edited">第二</p>',
          ],
          converter: converter,
        );
        expect(result[1].html, '<p id="b" class="edited">第二T</p>');
        expect(metrics.last.cachedHtmlFragmentCount, 1);
        expect(metrics.last.parsedHtmlFragmentCount, 1);
      },
    );

    test(
      'unknown converter keeps whole-batch context even after a cache fill',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final converter = _ContextConverter();
        final service = DomHtmlTextNodeConversionService(
          metricsListener: metrics.add,
        );
        final first = await service.convertAll(
          htmlFragments: const ['<p>甲</p>', '<p>乙</p>'],
          converter: converter,
        );
        final second = await service.convertAll(
          htmlFragments: const ['<p>甲</p>'],
          converter: converter,
        );
        expect(first.first.html, '<p>甲联动</p>');
        expect(second.single.html, '<p>甲</p>');
        expect(metrics.last.parsedHtmlFragmentCount, 1);
        expect(metrics.last.cachedHtmlFragmentCount, 0);
      },
    );

    test(
      'unknown batch wrappers keep the conservative whole-batch path',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final wrapped = _WrappedPlainService();
        final service = DomHtmlTextNodeConversionService(
          plainTextBatchConversionService: wrapped,
          metricsListener: metrics.add,
        );
        final converter = _MapTextConverter({'第一': '第一T', '第二': '第二T'});
        await service.convertAll(
          htmlFragments: const ['<p>第一</p>'],
          converter: converter,
        );
        await service.convertAll(
          htmlFragments: const ['<p>第一</p>', '<p>第二</p>'],
          converter: converter,
        );
        expect(wrapped.inputs.last, ['第一', '第二']);
        expect(metrics.last.parsedHtmlFragmentCount, 2);
        expect(metrics.last.cachedHtmlFragmentCount, 0);
      },
    );

    test(
      'raw no-Han fragments retain their mixed-batch serialization rule',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final converter = _MapTextConverter({'正文': '正文T'});
        final service = DomHtmlTextNodeConversionService(
          metricsListener: metrics.add,
        );
        const plain = "<p data-token='x'>hello&nbsp;</p>";
        const han = '<p>正文</p>';
        final raw = await service.convert(html: plain, converter: converter);
        expect(raw.html, plain);
        final mixed = await service.convertAll(
          htmlFragments: const [plain, han],
          converter: converter,
        );
        expect(mixed.first.html, '<p data-token="x">hello&nbsp;</p>');
        final reordered = await service.convertAll(
          htmlFragments: const [han, plain],
          converter: converter,
        );
        expect(reordered[1].html, mixed.first.html);
        expect(metrics.last.cachedHtmlFragmentCount, 1);
        expect(metrics.last.parsedHtmlFragmentCount, 1);
        expect(metrics.last.submittedPlainSourceCount, 0);
        expect(metrics.last.plainSourceCount, 2);
        final original = await service.convert(
          html: plain,
          converter: converter,
        );
        expect(original.html, plain);
      },
    );

    test(
      'failed incremental batches publish and retain no new subset',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final converter = _FailingIndependentConverter();
        final service = DomHtmlTextNodeConversionService(
          plainTextBatchConversionService:
              DefaultPlainTextBatchConversionService(maxCacheEntries: 0),
          metricsListener: metrics.add,
        );
        await service.convert(html: '<p>第一</p>', converter: converter);
        converter.fail = true;
        await expectLater(
          service.convertAll(
            htmlFragments: const ['<p>第一</p>', '<p>第二</p>', '<p>第三</p>'],
            converter: converter,
          ),
          throwsA(isA<StateError>()),
        );
        expect(metrics.last.failureType, 'StateError');
        expect(metrics.last.cachedHtmlFragmentCount, 1);
        expect(metrics.last.parsedHtmlFragmentCount, 2);
        converter.fail = false;
        final result = await service.convertAll(
          htmlFragments: const ['<p>第一</p>', '<p>第二</p>', '<p>第三</p>'],
          converter: converter,
        );
        expect(result.map((value) => value.html), [
          '<p>第一T</p>',
          '<p>第二T</p>',
          '<p>第三T</p>',
        ]);
        expect(metrics.last.cachedHtmlFragmentCount, 1);
        expect(metrics.last.parsedHtmlFragmentCount, 2);
      },
    );

    test(
      'caller list mutation cannot replace a retained successful fragment',
      () async {
        final converter = _MapTextConverter({'第一': '第一T', '第二': '第二T'});
        final service = DomHtmlTextNodeConversionService();
        final first = await service.convertAll(
          htmlFragments: const ['<p>第一</p>'],
          converter: converter,
        );
        first[0] = const HtmlTextNodeConversionResult(
          html: 'poison',
          convertedTextNodeCount: 0,
          converterId: 'other',
        );
        final result = await service.convertAll(
          htmlFragments: const ['<p>第一</p>', '<p>第二</p>'],
          converter: converter,
        );
        expect(result.first.html, '<p>第一T</p>');
      },
    );

    test(
      'fragment reuse is limited to the retained successful batch budget',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final converter = _MapTextConverter({'正文': '正文T'});
        final service = DomHtmlTextNodeConversionService(
          maxCacheEntries: 1,
          metricsListener: metrics.add,
        );
        await service.convertAll(
          htmlFragments: const ['<p>正文1</p>', '<p>正文2</p>'],
          converter: converter,
        );
        await service.convertAll(
          htmlFragments: const ['<p>正文1</p>', '<p>正文2</p>', '<p>正文3</p>'],
          converter: converter,
        );
        expect(metrics.last.cachedHtmlFragmentCount, 2);
        await service.convert(html: '<p>正文4</p>', converter: converter);
        await service.convertAll(
          htmlFragments: const ['<p>正文1</p>', '<p>正文3</p>'],
          converter: converter,
        );
        expect(metrics.last.cachedHtmlFragmentCount, 0);
        expect(metrics.last.parsedHtmlFragmentCount, 2);
      },
    );

    test('cardinality failures retain no partial batch', () async {
      final wrong = _ShortPlainService();
      final service = DomHtmlTextNodeConversionService(
        plainTextBatchConversionService: wrong,
      );
      final converter = _MapTextConverter({'正文': '正文T'});
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          service.convertAll(
            htmlFragments: const ['<p>正文1</p>', '<p>正文2</p>'],
            converter: converter,
          ),
          throwsA(isA<HtmlTextNodeConversionException>()),
        );
      }
      expect(wrong.calls, 2);
    });

    test(
      'fragment reuse respects converter direction and full options',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final service = DomHtmlTextNodeConversionService(
          metricsListener: metrics.add,
        );
        final traditional = _MapTextConverter({'正文': '正文T'}, id: 'fake:s2t');
        final simplified = _MapTextConverter(
          {'正文': '正文S'},
          id: 'fake:t2s',
          mode: TextConversionMode.toSimplified,
        );
        const html = '<p>正文<span>正文</span></p>';
        await service.convert(html: html, converter: traditional);
        final changedMode = await service.convertAll(
          htmlFragments: const [html, '<p>正文</p>'],
          converter: simplified,
        );
        expect(changedMode.first.html, '<p>正文S<span>正文S</span></p>');
        expect(metrics.last.cachedHtmlFragmentCount, 0);
        final changedOptions = await service.convertAll(
          htmlFragments: const [html, '<p>正文</p>'],
          converter: traditional,
          options: const HtmlTextNodeConversionOptions(skipTags: {'span'}),
        );
        expect(changedOptions.first.html, '<p>正文T<span>正文</span></p>');
        expect(metrics.last.cachedHtmlFragmentCount, 0);
      },
    );

    test(
      'options identity distinguishes case and comma-containing policy IDs',
      () async {
        final service = DomHtmlTextNodeConversionService();
        final converter = _MapTextConverter({'正文': '正文T'});
        const html = '<p>正文<span>正文</span></p>';
        final uppercase = await service.convert(
          html: html,
          converter: converter,
          options: const HtmlTextNodeConversionOptions(skipTags: {'SPAN'}),
        );
        final lowercase = await service.convert(
          html: html,
          converter: converter,
          options: const HtmlTextNodeConversionOptions(skipTags: {'span'}),
        );
        expect(uppercase.html, '<p>正文T<span>正文T</span></p>');
        expect(lowercase.html, '<p>正文T<span>正文</span></p>');
        final excluded = await service.convert(
          html: html,
          converter: converter,
          options: const HtmlTextNodeConversionOptions(
            exclusionPolicies: [_TagExclusionPolicy('one,two', 'span')],
          ),
        );
        final allowed = await service.convert(
          html: html,
          converter: converter,
          options: const HtmlTextNodeConversionOptions(
            exclusionPolicies: [
              _TagExclusionPolicy('one', null),
              _TagExclusionPolicy('two', null),
            ],
          ),
        );
        expect(excluded.html, '<p>正文T<span>正文</span></p>');
        expect(allowed.html, '<p>正文T<span>正文T</span></p>');
      },
    );
    test('converts only ordinary text nodes', () async {
      final service = DomHtmlTextNodeConversionService();
      final converter = _MapTextConverter({'正文': '正文T', '尾巴': '尾巴T'});

      final result = await service.convert(
        html: '<p class="keep" title="正文">正文<span>尾巴</span></p>',
        converter: converter,
      );

      expect(result.html, '<p class="keep" title="正文">正文T<span>尾巴T</span></p>');
      expect(result.convertedTextNodeCount, 2);
      expect(result.converterId, converter.id);
      expect(converter.callCount, 1);
    });

    test(
      'converts multiple fragments in one batch and keeps their order',
      () async {
        final service = DomHtmlTextNodeConversionService();
        final converter = _MapTextConverter({
          '第一': '第一T',
          '第二': '第二T',
          '第三': '第三T',
        });

        final results = await service.convertAll(
          htmlFragments: ['<p>第一</p>', '<p>第二<span>第三</span></p>'],
          converter: converter,
        );

        expect(results.map((result) => result.html), [
          '<p>第一T</p>',
          '<p>第二T<span>第三T</span></p>',
        ]);
        expect(results.map((result) => result.convertedTextNodeCount), [1, 2]);
        expect(converter.callCount, 1);
      },
    );

    test('does not convert href src style or class attributes', () async {
      final service = DomHtmlTextNodeConversionService();
      final converter = _MapTextConverter({'链接': '連結', '图片': '圖片'});

      final result = await service.convert(
        html:
            '<a class="简体" style="color:简体" href="/简体">链接</a>'
            '<img src="/图片.png" alt="图片">',
        converter: converter,
      );

      expect(result.html, contains('class="简体"'));
      expect(result.html, contains('style="color:简体"'));
      expect(result.html, contains('href="/简体"'));
      expect(result.html, contains('src="/图片.png"'));
      expect(result.html, contains('alt="图片"'));
      expect(result.html, contains('>連結</a>'));
      expect(result.convertedTextNodeCount, 1);
    });

    test(
      'returns an exact fragment when no convertible Han node exists',
      () async {
        final service = DomHtmlTextNodeConversionService();
        final converter = _MapTextConverter({'正文': '正文T'});
        const html = '<p class="keep" title="raw">plain text</p>';

        final result = await service.convert(html: html, converter: converter);

        expect(result.html, html);
        expect(result.convertedTextNodeCount, 0);
        expect(converter.callCount, 0);
      },
    );

    test('skips script style pre code textarea and blockcode text', () async {
      final service = DomHtmlTextNodeConversionService();
      final converter = _MapTextConverter({
        '正文': '正文T',
        '脚本': '腳本',
        '样式': '樣式',
        '代码': '代碼',
        '输入': '輸入',
      });

      final result = await service.convert(
        html:
            '<p>正文</p>'
            '<script>脚本</script>'
            '<style>.a{content:"样式"}</style>'
            '<pre>代码</pre>'
            '<code>代码</code>'
            '<textarea>输入</textarea>'
            '<div class="blockcode">代码</div>',
        converter: converter,
      );

      expect(result.html, contains('<p>正文T</p>'));
      expect(result.html, contains('<script>脚本</script>'));
      expect(result.html, contains('<style>.a{content:"样式"}</style>'));
      expect(result.html, contains('<pre>代码</pre>'));
      expect(result.html, contains('<code>代码</code>'));
      expect(result.html, contains('<textarea>输入</textarea>'));
      expect(result.html, contains('<div class="blockcode">代码</div>'));
      expect(result.convertedTextNodeCount, 1);
    });

    test('keeps ruby structure while converting ruby text nodes', () async {
      final service = DomHtmlTextNodeConversionService();
      final converter = _MapTextConverter({'漢字': '汉字', '注音': '注音T'});

      final result = await service.convert(
        html: '<ruby>漢字<rt>注音</rt></ruby>',
        converter: converter,
      );

      expect(result.html, '<ruby>汉字<rt>注音T</rt></ruby>');
      expect(result.convertedTextNodeCount, 2);
    });

    test('protects trusted Yamibo user profile links', () async {
      final service = DomHtmlTextNodeConversionService();
      final converter = _MapTextConverter({'漢字': '汉字'});

      final result = await service.convert(
        html:
            '<a href="home.php?mod=space&amp;uid=10">漢字</a>'
            '<a href="/space-uid-11.html"><span>漢字</span></a>'
            '<a href="forum.php?mod=viewthread&amp;tid=12">漢字</a>'
            '<a href="https://example.com/space-uid-13.html">漢字</a>',
        converter: converter,
      );

      expect(result.html, contains('home.php?mod=space&amp;uid=10">漢字</a>'));
      expect(result.html, contains('/space-uid-11.html"><span>漢字</span></a>'));
      expect(result.html, contains('tid=12">汉字</a>'));
      expect(result.html, contains('example.com/space-uid-13.html">汉字</a>'));
      expect(result.convertedTextNodeCount, 2);
      expect(converter.callCount, 1);
    });

    test('changes exclusion policy signature for cache identity', () async {
      final converter = _MapTextConverter({'正文': '正文T'});
      final service = DomHtmlTextNodeConversionService(
        plainTextBatchConversionService: DefaultPlainTextBatchConversionService(
          maxCacheEntries: 0,
        ),
      );

      await service.convert(html: '<p>正文</p>', converter: converter);
      await service.convert(
        html: '<p>正文</p>',
        converter: converter,
        options: const HtmlTextNodeConversionOptions(
          exclusionPolicies: <HtmlTextNodeExclusionPolicy>[],
        ),
      );

      expect(converter.callCount, 2);
    });

    test(
      'checks structural policies once and skips their entire subtree',
      () async {
        final policy = _RecordingExclusionPolicy();
        final service = DomHtmlTextNodeConversionService();
        final converter = _MapTextConverter({
          '正文': '正文T',
          '尾巴': '尾巴T',
          '保留': '不可转换',
        });
        var visible = '正文';
        for (var depth = 0; depth < 32; depth += 1) {
          visible = '<span>$visible 尾巴</span>';
        }

        final result = await service.convert(
          html:
              '<div>$visible'
              '<section data-protected="true">'
              '<span data-protected-child="true">保留</span>'
              '</section><p>正文</p></div>',
          converter: converter,
          options: HtmlTextNodeConversionOptions(exclusionPolicies: [policy]),
        );

        expect(result.html, contains('<span>正文T 尾巴T</span>'));
        expect(result.html, contains('<p>正文T</p>'));
        expect(result.html, contains('data-protected-child="true">保留</span>'));
        expect(result.html, isNot(contains('不可转换')));
        expect(result.convertedTextNodeCount, 33);
        expect(policy.checkedElements, hasLength(35));
        expect(policy.checkedElements.toSet(), hasLength(35));
        expect(
          policy.checkedElements.any(
            (element) => element.attributes.containsKey('data-protected-child'),
          ),
          isFalse,
        );
      },
    );

    test(
      'identity converter returns original html without conversion',
      () async {
        final metrics = <HtmlTextNodeConversionMetrics>[];
        final service = DomHtmlTextNodeConversionService(
          metricsListener: metrics.add,
        );

        final result = await service.convert(
          html: '<p>正文</p>',
          converter: const IdentityTextConverter(),
        );

        expect(result.html, '<p>正文</p>');
        expect(result.convertedTextNodeCount, 0);
        expect(result.converterId, 'conv:none');
        expect(metrics.single.parsedHtmlFragmentCount, 0);
        expect(metrics.single.submittedPlainSourceCount, 0);
      },
    );

    test(
      'reuses cached result for identical input converter and options',
      () async {
        final service = DomHtmlTextNodeConversionService();
        final converter = _MapTextConverter({'正文': '正文T'});

        final first = await service.convert(
          html: '<p>正文</p>',
          converter: converter,
        );
        final second = await service.convert(
          html: '<p>正文</p>',
          converter: converter,
        );

        expect(first.html, '<p>正文T</p>');
        expect(second.html, '<p>正文T</p>');
        expect(converter.callCount, 1);
      },
    );

    test(
      'default budget retains a long batch rejected by a smaller override',
      () async {
        final text = '甲' * (768 * 1024);
        final fragments = [
          for (var floor = 0; floor < 3; floor++)
            '<p data-floor="$floor">floor-$floor $text</p>',
        ];
        for (final useSmallerBudget in [false, true]) {
          final metrics = <HtmlTextNodeConversionMetrics>[];
          final plainService = DefaultPlainTextBatchConversionService(
            maxCacheEntries: 0,
          );
          final service = useSmallerBudget
              ? DomHtmlTextNodeConversionService(
                  plainTextBatchConversionService: plainService,
                  maxCacheCodeUnits: 4 * 1024 * 1024,
                  metricsListener: metrics.add,
                )
              : DomHtmlTextNodeConversionService(
                  plainTextBatchConversionService: plainService,
                  metricsListener: metrics.add,
                );
          final converter = _MapTextConverter({'甲': '乙'});
          final first = await service.convertAll(
            htmlFragments: fragments,
            converter: converter,
          );
          final second = await service.convertAll(
            htmlFragments: fragments,
            converter: converter,
          );

          expect(
            first.map((result) => result.html),
            fragments.map((html) => html.replaceAll('甲', '乙')),
          );
          expect(
            second.map((result) => result.html),
            first.map((result) => result.html),
          );
          expect(metrics.last.cacheHit, !useSmallerBudget);
          expect(
            metrics.last.parsedHtmlFragmentCount,
            useSmallerBudget ? fragments.length : 0,
          );
          expect(
            metrics.last.submittedPlainSourceCount,
            useSmallerBudget ? fragments.length : 0,
          );
          expect(converter.callCount, useSmallerBudget ? 2 : 1);
        }
      },
    );

    test('does not cache a batch over the HTML code unit budget', () async {
      final service = DomHtmlTextNodeConversionService(
        plainTextBatchConversionService: DefaultPlainTextBatchConversionService(
          maxCacheEntries: 0,
        ),
        maxCacheCodeUnits: 1,
      );
      final converter = _MapTextConverter({'正文': '正文T'});

      await service.convert(html: '<p>正文</p>', converter: converter);
      await service.convert(html: '<p>正文</p>', converter: converter);

      expect(converter.callCount, 2);
    });

    test('evicts HTML batches by least-recently-used entry order', () async {
      final service = DomHtmlTextNodeConversionService(
        plainTextBatchConversionService: DefaultPlainTextBatchConversionService(
          maxCacheEntries: 0,
        ),
        maxCacheEntries: 1,
      );
      final converter = _MapTextConverter({'第一': '第一T', '第二': '第二T'});

      await service.convert(html: '<p>第一</p>', converter: converter);
      await service.convert(html: '<p>第二</p>', converter: converter);
      await service.convert(html: '<p>第一</p>', converter: converter);

      expect(converter.callCount, 3);
    });

    test(
      'evicts HTML batches when their cumulative code units exceed budget',
      () async {
        final service = DomHtmlTextNodeConversionService(
          plainTextBatchConversionService:
              DefaultPlainTextBatchConversionService(maxCacheEntries: 0),
          maxCacheEntries: 8,
          maxCacheCodeUnits: 300,
        );
        final converter = _MapTextConverter({'第一': '第一T', '第二': '第二T'});
        final first = '<p>${List<String>.filled(20, '第一').join()}</p>';
        final second = '<p>${List<String>.filled(20, '第二').join()}</p>';
        const options = HtmlTextNodeConversionOptions(
          skipTags: <String>{},
          skipClassNames: <String>{},
          exclusionPolicies: <HtmlTextNodeExclusionPolicy>[],
        );

        await service.convert(
          html: first,
          converter: converter,
          options: options,
        );
        await service.convert(
          html: second,
          converter: converter,
          options: options,
        );
        await service.convert(
          html: first,
          converter: converter,
          options: options,
        );

        expect(converter.callCount, 3);
      },
    );

    test(
      'falls back to per-node conversion when batch split is invalid',
      () async {
        final service = DomHtmlTextNodeConversionService();
        final converter = _BadBatchTextConverter({'正文': '正文T', '尾巴': '尾巴T'});

        final result = await service.convert(
          html: '<p>正文<span>尾巴</span></p>',
          converter: converter,
        );

        expect(result.html, '<p>正文T<span>尾巴T</span></p>');
        expect(result.convertedTextNodeCount, 2);
        expect(converter.callCount, 3);
      },
    );

    test('observed conversion reports nested individual fallback', () async {
      final service = DomHtmlTextNodeConversionService();
      final converter = _BadBatchTextConverter({'正文': '正文T', '尾巴': '尾巴T'});
      final metrics = <HtmlTextNodeConversionMetrics>[];

      final result = await service.convertAllObserved(
        htmlFragments: const <String>['<p>正文<span>尾巴</span></p>'],
        converter: converter,
        metricsListener: metrics.add,
      );

      expect(result.single.html, '<p>正文T<span>尾巴T</span></p>');
      expect(metrics, hasLength(1));
      expect(metrics.single.usedIndividualFallback, isTrue);
    });
  });
}

class _RecordingExclusionPolicy implements HtmlTextNodeExclusionPolicy {
  final checkedElements = <html_dom.Element>[];

  @override
  String get id => 'recording-protected-subtree';

  @override
  bool excludes(html_dom.Element element) {
    checkedElements.add(element);
    return element.attributes['data-protected'] == 'true';
  }
}

class _RecordingDiagnosticRecorder implements TextConversionDiagnosticRecorder {
  final events = <TextConversionDiagnosticEvent>[];
  @override
  void record(TextConversionDiagnosticEvent event) => events.add(event);
}

class _FirstParagraphExclusionPolicy implements HtmlTextNodeExclusionPolicy {
  int paragraphVisits = 0;
  @override
  String get id => 'stateful-first-paragraph';
  @override
  bool excludes(html_dom.Element element) =>
      element.localName == 'p' && ++paragraphVisits == 1;
}

class _CountingSiteUrlResolver extends SiteUrlResolver {
  int calls = 0;
  @override
  String? resolve(String raw) {
    calls++;
    return super.resolve(raw);
  }
}

class _MapTextConverter implements IndependentTextValueConverter {
  _MapTextConverter(
    this.replacements, {
    this.id = 'fake:map',
    this.mode = TextConversionMode.toTraditional,
  });

  final Map<String, String> replacements;
  int callCount = 0;
  final inputs = <String>[];

  @override
  final String id;

  @override
  final TextConversionMode mode;

  @override
  Future<String> convertHtml(String html) async {
    callCount += 1;
    inputs.add(html);
    var result = html;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}

class _ContextConverter implements TextConverter {
  @override
  String get id => 'fake:context';
  @override
  TextConversionMode get mode => TextConversionMode.toTraditional;
  @override
  Future<String> convertHtml(String html) async =>
      html.contains('乙') ? html.replaceAll('甲', '甲联动') : html;
}

class _WrappedPlainService implements PlainTextBatchConversionService {
  final delegate = DefaultPlainTextBatchConversionService(maxCacheEntries: 0);
  final inputs = <List<String>>[];
  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) {
    inputs.add(List<String>.from(sources));
    return delegate.convertAll(sources: sources, converter: converter);
  }
}

class _ShortPlainService implements PlainTextBatchConversionService {
  int calls = 0;
  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    calls++;
    return sources.sublist(1);
  }
}

class _FailingIndependentConverter extends _MapTextConverter {
  _FailingIndependentConverter()
    : super({'第一': '第一T', '第二': '第二T', '第三': '第三T'});
  bool fail = false;
  @override
  Future<String> convertHtml(String html) async {
    if (fail) throw StateError('synthetic conversion failure');
    return super.convertHtml(html);
  }
}

class _TagExclusionPolicy implements HtmlTextNodeExclusionPolicy {
  const _TagExclusionPolicy(this.id, this.tag);
  @override
  final String id;
  final String? tag;
  @override
  bool excludes(html_dom.Element element) => element.localName == tag;
}

class _BadBatchTextConverter extends _MapTextConverter {
  _BadBatchTextConverter(super.replacements);

  @override
  Future<String> convertHtml(String html) async {
    callCount += 1;
    if (html.contains('\uE000')) {
      return 'invalid batch result';
    }
    var result = html;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}
