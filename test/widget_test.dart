import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';

void main() {
  test('ForumHomeViewData should count sections and forums', () {
    final viewData = ForumHomeViewData(
      sections: [
        ForumSection(
          title: '综合区',
          items: [
            ForumItem(
              fid: '2',
              name: '公告区',
              threads: 1,
              posts: 2,
              todayPosts: 0,
              description: '',
              icon: '',
              subForums: const [],
            ),
          ],
        ),
      ],
    );

    expect(viewData.sectionCount, 1);
    expect(viewData.forumCount, 1);
  });
}
