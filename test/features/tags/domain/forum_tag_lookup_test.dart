import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';

void main() {
  test('ForumTagLookup finds tag name by fid and typeid', () {
    final lookup = ForumTagLookup(
      const <ForumBoardTagSet>[
        ForumBoardTagSet(
          fid: '30',
          name: '中文百合漫画区',
          tags: <ForumTagDefinition>[
            ForumTagDefinition(fid: '30', typeid: '65', name: '公告'),
            ForumTagDefinition(fid: '30', typeid: '398', name: '韩国漫画'),
          ],
        ),
      ],
    );

    expect(lookup.findName(fid: '30', typeid: '65'), '公告');
    expect(lookup.findName(fid: '30', typeid: '398'), '韩国漫画');
    expect(lookup.findName(fid: '30', typeid: '999'), isNull);
  });
}
