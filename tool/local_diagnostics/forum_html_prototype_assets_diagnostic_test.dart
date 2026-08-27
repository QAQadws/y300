import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_sample_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local forum HTML prototype assets are loadable UTF-8 documents',
    () async {
      for (final sample in forumHtmlPrototypeSamples) {
        final localFile = File(sample.assetPath);
        expect(
          localFile.existsSync(),
          isTrue,
          reason:
              'Missing local diagnostic asset ${sample.assetPath}. '
              'Private source hint: ${sample.sourceDocPath}',
        );

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
