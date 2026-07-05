import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_sample_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forum HTML prototype sample manifest is stable', () {
    expect(forumHtmlPrototypeSamples, hasLength(4));

    expect(
      forumHtmlPrototypeSamples.map((sample) => sample.id),
      containsAll(<String>[
        'ruby',
        'background_color',
        'collapse_directory',
        'text_color_size',
      ]),
    );

    expect(
      forumHtmlPrototypeSamples.map((sample) => sample.id).toSet(),
      hasLength(forumHtmlPrototypeSamples.length),
    );
    expect(
      forumHtmlPrototypeSamples.map((sample) => sample.assetPath).toSet(),
      hasLength(forumHtmlPrototypeSamples.length),
    );

    expect(
      forumHtmlPrototypeSamples.map((sample) => sample.sourceDocPath),
      containsAll(<String>[
        'docs/html/特殊格式/注音.html',
        'docs/html/特殊格式/文字背景色.html',
        'docs/html/特殊格式/折叠目录.html',
        'docs/html/特殊格式/字颜色字号.html',
      ]),
    );
  });

  test(
    'local forum HTML prototype assets are loadable and preserve UTF-8 text',
    () async {
      for (final sample in forumHtmlPrototypeSamples) {
        final localFile = File(sample.assetPath);
        if (!localFile.existsSync()) {
          markTestSkipped(
            'Local prototype asset ${sample.assetPath} is intentionally not '
            'committed. Copy it from ${sample.sourceDocPath} to run this check.',
          );
          return;
        }

        final html = await rootBundle.loadString(sample.assetPath);

        expect(html.trim(), isNotEmpty, reason: sample.id);
        expect(html.toLowerCase(), contains('<html'), reason: sample.id);
        expect(html, contains('pg_viewthread'), reason: sample.id);
        expect(
          html,
          anyOf(contains('阅读字号'), contains('閱讀字號')),
          reason: sample.id,
        );
      }
    },
  );
}
