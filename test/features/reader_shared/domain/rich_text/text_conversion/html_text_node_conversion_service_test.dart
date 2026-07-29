import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_exclusion_policy.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

void main() {
  group('DomHtmlTextNodeConversionService', () {
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
      'identity converter returns original html without conversion',
      () async {
        final service = DomHtmlTextNodeConversionService();

        final result = await service.convert(
          html: '<p>正文</p>',
          converter: const IdentityTextConverter(),
        );

        expect(result.html, '<p>正文</p>');
        expect(result.convertedTextNodeCount, 0);
        expect(result.converterId, 'conv:none');
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

class _MapTextConverter implements TextConverter {
  _MapTextConverter(this.replacements);

  final Map<String, String> replacements;
  int callCount = 0;

  @override
  String get id => 'fake:map';

  @override
  TextConversionMode get mode => TextConversionMode.toTraditional;

  @override
  Future<String> convertHtml(String html) async {
    callCount += 1;
    var result = html;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
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
