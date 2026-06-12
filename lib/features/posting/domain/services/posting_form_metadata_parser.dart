import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';

/// 把 `module=forumdisplay` 响应里的 Variables 解析成
/// [NewThreadFormMetadata]。
///
/// Discuz 接口在不同版块上的字段形状不完全一致：
/// - `Variables.threadtypes.types` 在多数情况下是 `{typeid: name}` 的 Map；
///   在另一些版块是 `[{id, name}]` 的 List。
/// - `threadtypes.required` / `threadsorts.required` 可能是 '0'/'1' 字符串
///   或 0/1 整数。
///
/// 这里写在独立 service 而不是模型里，方便后续把 forumdisplay 共用解析（比如
/// `ForumDisplayJsonMapper`）和发帖 metadata 解析独立演进。
class PostingFormMetadataParser {
  const PostingFormMetadataParser();

  NewThreadFormMetadata parse({
    required String fid,
    required JsonMap variables,
  }) {
    final formHash = ParseUtils.asString(variables['formhash']);
    final forum = ParseUtils.asMap(variables['forum']);
    final forumName = ParseUtils.asString(forum['name']);

    final threadTypesRoot = ParseUtils.asMap(variables['threadtypes']);
    final threadSortsRoot = ParseUtils.asMap(variables['threadsorts']);

    return NewThreadFormMetadata(
      fid: fid,
      forumName: forumName,
      formHash: formHash,
      threadTypes: _parseThreadTypes(threadTypesRoot),
      threadSorts: _parseThreadSorts(threadSortsRoot),
      typeRequired: _parseRequired(threadTypesRoot['required']),
      sortRequired: _parseRequired(threadSortsRoot['required']),
    );
  }

  List<ThreadType> _parseThreadTypes(JsonMap root) {
    final raw = root['types'];
    return _parseEntries(raw)
        .map((entry) => ThreadType(id: entry.id, name: entry.name))
        .toList(growable: false);
  }

  List<ThreadSort> _parseThreadSorts(JsonMap root) {
    final raw = root['types'];
    return _parseEntries(raw)
        .map((entry) => ThreadSort(id: entry.id, name: entry.name))
        .toList(growable: false);
  }

  /// 同时支持 `Map<typeid, name>` 与 `List<{id|typeid, name|typename}>`。
  List<_TypeEntry> _parseEntries(dynamic raw) {
    if (raw is Map) {
      return raw.entries
          .map(
            (entry) => _TypeEntry(
              id: entry.key.toString(),
              name: ParseUtils.asString(entry.value),
            ),
          )
          .where((entry) => entry.id.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is List) {
      return raw
          .map(ParseUtils.asMap)
          .map(
            (item) => _TypeEntry(
              id: ParseUtils.asString(
                item['id'],
                fallback: ParseUtils.asString(item['typeid']),
              ),
              name: ParseUtils.asString(
                item['name'],
                fallback: ParseUtils.asString(item['typename']),
              ),
            ),
          )
          .where((entry) => entry.id.isNotEmpty)
          .toList(growable: false);
    }
    return const <_TypeEntry>[];
  }

  bool _parseRequired(dynamic raw) {
    return ParseUtils.asBool(raw);
  }
}

class _TypeEntry {
  const _TypeEntry({required this.id, required this.name});
  final String id;
  final String name;
}
