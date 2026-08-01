import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';

void main() {
  test('ForumHomeViewData should count sections and forums', () {
    final viewData = ForumHomeViewData(
      sections: const [
        ForumSection(
          sourceIdentity: 'regular:2',
          title: '综合区',
          items: [
            ForumHomeForumDisplayItem(
              fid: '2',
              title: '公告区',
              description: '',
              todayPosts: null,
            ),
          ],
        ),
      ],
      isLoggedIn: false,
    );

    expect(viewData.sectionCount, 1);
    expect(viewData.regularForumCount, 1);
    expect(viewData.forumCount, 1);
  });

  test(
    'ForumHomeViewData counts favorite and regular forums without double count',
    () {
      final viewData = ForumHomeViewData(
        sections: const [
          ForumSection(
            sourceIdentity: 'favorite:2',
            title: '我收藏的版块',
            items: [
              ForumHomeForumDisplayItem(
                fid: '2',
                title: '公告区',
                description: '',
                todayPosts: null,
              ),
            ],
            type: ForumSectionType.favorite,
          ),
          ForumSection(
            sourceIdentity: 'regular:2',
            title: '综合区',
            items: [
              ForumHomeForumDisplayItem(
                fid: '2',
                title: '公告区',
                description: '',
                todayPosts: 2,
              ),
            ],
          ),
        ],
        isLoggedIn: true,
      );

      expect(viewData.sectionCount, 2);
      expect(viewData.regularForumCount, 1);
      expect(viewData.forumCount, 1);
    },
  );
}
