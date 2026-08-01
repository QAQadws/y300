import 'package:y300/core/utils/parse_utils.dart';

class ForumTagDefinition {
  const ForumTagDefinition({
    required this.fid,
    required this.typeid,
    required this.name,
  });

  final String fid;
  final String typeid;
  final String name;

  factory ForumTagDefinition.fromJson(JsonMap json, {required String fid}) {
    return ForumTagDefinition(
      fid: fid,
      typeid: ParseUtils.asString(json['typeid']),
      name: ParseUtils.asString(json['name']),
    );
  }
}

class ForumBoardTagSet {
  const ForumBoardTagSet({
    required this.fid,
    required this.name,
    required this.tags,
  });

  final String fid;
  final String name;
  final List<ForumTagDefinition> tags;

  factory ForumBoardTagSet.fromJson(JsonMap json) {
    final fid = ParseUtils.asString(json['fid']);
    return ForumBoardTagSet(
      fid: fid,
      name: ParseUtils.asString(json['name']),
      tags: ParseUtils.asList(json['tags'])
          .map(
            (item) =>
                ForumTagDefinition.fromJson(ParseUtils.asMap(item), fid: fid),
          )
          .where((tag) => tag.typeid.trim().isNotEmpty)
          .toList(growable: false),
    );
  }
}
