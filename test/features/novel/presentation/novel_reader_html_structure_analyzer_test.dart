import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_structure_analyzer.dart';

const _realFixturePaths = <String, String>{
  '文字背景色': 'docs/html/特殊格式/文字背景色.html',
  '折叠目录': 'docs/html/特殊格式/折叠目录.html',
  '字颜色字号': 'docs/html/特殊格式/字颜色字号.html',
  '注音': 'docs/html/特殊格式/注音.html',
};

void main() {
  const analyzer = NovelReaderHtmlStructureAnalyzer();

  for (final entry in _realFixturePaths.entries) {
    final fixtureExists = File(entry.value).existsSync();
    test(
      'imports the real ${entry.key} fixture as UTF-8',
      () {
        final bytes = File(entry.value).readAsBytesSync();
        final report = analyzer.analyze(
          fixtureId: entry.key,
          rawHtml: utf8.decode(bytes),
        );

        expect(report.sourceUtf8Bytes, bytes.length);
        expect(report.messageFound, isTrue);
        expect(report.messageTextRunes, greaterThan(0));
        expect(report.messageSensitiveMarkers, isEmpty);
      },
      skip: fixtureExists
          ? false
          : 'Local Phase 0 HTML fixture is unavailable.',
    );
  }

  test('reports only structural counts for the first post message', () {
    const html = '''
      <html>
        <head><script>document.cookie = "ignored";</script></head>
        <body>
          <div class="message" id="first-message">
            普通文字<font color="#123456" style="font-size: 18px; background-color: #fff">强调</font>
            <ruby>文字<rt>注音</rt><rp>(</rp></ruby>
            <img src="https://example.invalid/image.jpg">
            <div class="showcollapse_box showcollapse_active">
              <div class="showcollapse_content">目录</div>
            </div>
            <table><tr><th>表头</th><td>单元格</td></tr></table>
          </div>
          <div class="message">不应进入首个 message 统计</div>
        </body>
      </html>
    ''';

    final report = analyzer.analyze(fixtureId: 'synthetic', rawHtml: html);

    expect(report.messageFound, isTrue);
    expect(report.messageSelector, '.message');
    expect(report.fontTagCount, 1);
    expect(report.fontSizeDeclarationCount, 1);
    expect(report.foregroundColorDeclarationCount, 1);
    expect(report.backgroundColorDeclarationCount, 1);
    expect(report.imageCount, 1);
    expect(report.collapseBlockCount, 1);
    expect(report.expandedCollapseBlockCount, 1);
    expect(report.tableCount, 1);
    expect(report.tableRowCount, 1);
    expect(report.tableCellCount, 2);
    expect(report.rubyCount, 1);
    expect(report.rubyAnnotationCount, 1);
    expect(report.rubyFallbackCount, 1);
    expect(report.ordinaryTextNodeCount, greaterThan(0));
    expect(report.messageSensitiveMarkers, isEmpty);
    expect(report.toJsonString(), isNot(contains('普通文字')));
    expect(report.toJsonString(), isNot(contains('example.invalid')));
  });

  test('does not mistake page scripts for message content', () {
    const html = '''
      <body>
        <script>document.cookie = "auth=secret";</script>
        <div class="message">正文</div>
      </body>
    ''';

    final report = analyzer.analyze(fixtureId: 'script', rawHtml: html);

    expect(report.scriptCount, 1);
    expect(report.messageSensitiveMarkers, isEmpty);
    expect(report.messageTextRunes, 2);
  });

  test(
    'falls back to the body without exposing fallback body text in JSON',
    () {
      final report = analyzer.analyze(
        fixtureId: 'missing',
        rawHtml: '<html><body>登录页面</body></html>',
      );

      expect(report.messageFound, isTrue);
      expect(report.messageSelector, 'body');
      expect(report.messageTextRunes, 4);
    },
  );
}
