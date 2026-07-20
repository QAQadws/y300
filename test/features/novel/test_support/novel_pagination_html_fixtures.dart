import 'dart:convert';
import 'dart:io';

import 'package:y300/features/thread/data/services/thread_detail_html_parser.dart';
import 'package:y300/features/thread/domain/html_rendering/forum_html_sample_document.dart';

final List<ForumHtmlSampleDocument> novelPaginationHtmlFixtures =
    List<ForumHtmlSampleDocument>.unmodifiable(
      forumHtmlPrototypeSamples.where(
        (sample) => const <String>{
          'ruby',
          'background_color',
          'collapse_directory',
          'text_color_size',
        }.contains(sample.id),
      ),
    );

final class NovelPaginationHtmlFixtureLoader {
  const NovelPaginationHtmlFixtureLoader({
    this.parser = const ThreadDetailHtmlParser(),
  });

  final ThreadDetailHtmlParser parser;

  String loadFirstPostMessage(ForumHtmlSampleDocument sample) {
    final bytes = File(sample.sourceDocPath).readAsBytesSync();
    final source = utf8.decode(bytes);
    final detail = parser.parse(
      source,
      fallbackTid: 'phase6-${sample.id}',
      fallbackPage: 1,
      fallbackSubject: sample.title,
    );
    if (detail.posts.isEmpty) {
      throw StateError('Fixture ${sample.id} has no parsed forum post.');
    }
    return detail.posts
        .firstWhere((post) => post.isFirst, orElse: () => detail.posts.first)
        .message;
  }
}
