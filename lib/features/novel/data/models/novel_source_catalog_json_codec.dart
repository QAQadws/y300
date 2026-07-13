import 'dart:convert';

import 'package:y300/features/novel/domain/models/novel_source_models.dart';

class NovelSourceCatalogJsonCodec {
  const NovelSourceCatalogJsonCodec();

  String encode(List<NovelSourceCatalogEntry> entries) {
    return jsonEncode(
      entries
          .map(
            (entry) => <String, Object?>{
              'position': entry.position,
              'pid': entry.pid,
              'title': entry.title,
              'url': entry.url,
            },
          )
          .toList(growable: false),
    );
  }

  List<NovelSourceCatalogEntry> decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Novel source catalog must be a JSON list.');
    }
    return decoded
        .map((value) {
          if (value is! Map) {
            throw const FormatException(
              'Novel source catalog entry must be a map.',
            );
          }
          return NovelSourceCatalogEntry(
            position: (value['position'] as num?)?.toInt() ?? 0,
            pid: value['pid']?.toString() ?? '',
            title: value['title']?.toString() ?? '',
            url: value['url']?.toString() ?? '',
          );
        })
        .toList(growable: false);
  }
}
