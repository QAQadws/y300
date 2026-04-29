import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';

void main() {
  test('ForumHomeViewData should count sections and forums', () {
    // 测试说明：检查 ForumHomeViewData 对 sections 和 forum item 的计数是否正确
    // 场景：一个分组包含一个版块，期望 sectionCount=1, forumCount=1
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
      isLoggedIn: false,
    );

    expect(viewData.sectionCount, 1);
    expect(viewData.forumCount, 1);
  });
}
