import 'dart:convert';
import 'dart:io';

import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class NovelPhase0ApiFixture {
  const NovelPhase0ApiFixture._({required this.path, required this.root});

  final String path;
  final Map<String, dynamic> root;

  Map<String, dynamic> get metadata => _asStringMap(root['FixtureMetadata']);

  Map<String, dynamic> get variables => _asStringMap(root['Variables']);

  int get requestedPage => _asInt(metadata['requestedPage']);

  ThreadDetailData parseDetail() {
    return createY300ThreadDetailApiDecoder()(variables, page: requestedPage);
  }

  static Future<NovelPhase0ApiFixture> load(String path) async {
    final text = await File(path).readAsString(encoding: utf8);
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException('Fixture root must be a JSON object: $path');
    }
    return NovelPhase0ApiFixture._(path: path, root: _asStringMap(decoded));
  }
}

const novelPhase0FavoriteDetailV4FixturePath =
    'test/features/novel/fixtures/phase0/'
    'favorite_detail_v4_later_posts_unsafe.json';

const novelPhase0ObservedAuthorPageFixturePath =
    'test/features/novel/fixtures/phase0/'
    'author_posts_v1_observed_page_1_default_ppp.json';

const novelPhase0AuthorPageFixturePaths = <String>[
  'test/features/novel/fixtures/phase0/author_posts_v1_page_1.json',
  'test/features/novel/fixtures/phase0/author_posts_v1_page_2.json',
  'test/features/novel/fixtures/phase0/author_posts_v1_page_3.json',
];

const novelPaginationShortParagraphFixturePath =
    'test/features/novel/fixtures/pagination/'
    'thread_572954_pid_41569751_v1.json';

const novelPaginationDivParagraphFixturePath =
    'test/features/novel/fixtures/pagination/'
    'thread_565218_pid_41425060_v1.json';

const novelComplexHtmlThread511960FixturePath =
    'test/features/novel/fixtures/pagination/'
    'thread_511960_complex_blocks_v1.json';

const novelComplexHtmlThread565218FixturePath =
    'test/features/novel/fixtures/pagination/'
    'thread_565218_pid_41425048_complex_v1.json';

const novelComplexHtmlInvalidFontFixturePath =
    'test/features/novel/fixtures/pagination/'
    'flowable_complex_invalid_font_v1.html';

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
    );
  }
  return <String, dynamic>{};
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
