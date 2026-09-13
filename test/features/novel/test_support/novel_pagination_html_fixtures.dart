import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/thread/data/services/thread_detail_document_decoder.dart';

import '../../../test_support/utf8_test_fixture.dart';
import 'novel_title_fixtures.dart';

final novelPaginationHtmlFixtures = novelPaginationFixtureTitles.entries
    .map((entry) => (id: entry.key, title: entry.value))
    .toList(growable: false);

final class NovelPaginationHtmlFixtureLoader {
  NovelPaginationHtmlFixtureLoader({ThreadDetailDocumentDecoder? decoder})
    : decoder =
          decoder ??
          ThreadDetailDocumentDecoder(createY300ThreadDetailHtmlDecoder());

  final ThreadDetailDocumentDecoder decoder;

  String loadFirstPostMessage(({String id, String title}) sample) {
    final source = readUtf8TestFixture('novel/pagination/${sample.id}.html');
    final detail = decoder.decode(
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
