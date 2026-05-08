import 'package:y300/features/tags/domain/forum_tag_models.dart';

class ForumTagLookup {
  ForumTagLookup(List<ForumBoardTagSet> boards)
      : _byFidTypeid = <String, ForumTagDefinition>{
          for (final board in boards)
            for (final tag in board.tags) _key(board.fid, tag.typeid): tag,
        },
        _byFid = <String, ForumBoardTagSet>{
          for (final board in boards) board.fid.trim(): board,
        };

  final Map<String, ForumTagDefinition> _byFidTypeid;
  final Map<String, ForumBoardTagSet> _byFid;

  ForumBoardTagSet? findBoard({required String fid}) {
    return _byFid[fid.trim()];
  }

  ForumTagDefinition? find({
    required String fid,
    required String typeid,
  }) {
    return _byFidTypeid[_key(fid, typeid)];
  }

  String? findName({
    required String fid,
    required String typeid,
  }) {
    final name = find(fid: fid, typeid: typeid)?.name.trim();
    return name == null || name.isEmpty ? null : name;
  }

  static String _key(String fid, String typeid) {
    return '${fid.trim()}:${typeid.trim()}';
  }
}
