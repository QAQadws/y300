import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/forum_link_routes.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';

void main() {
  const resolver = YamiboForumLinkResolver();
  const detail = 'home.php?mod=space&uid=101&do=blog&id=11';

  test('native blog page receives the complete parsed reading destination', () {
    for (final (suffix, initialPage, commentId, last, focus) in [
      ('', 1, null, false, false),
      ('&page=3', 3, null, false, false),
      ('&page=1&cid=31', 1, '31', false, true),
      ('#comment_31_li', 1, '31', false, true),
      ('&goto=last', 1, null, true, true),
      ('&page=3#comment', 3, null, false, true),
    ]) {
      final destination = resolver.resolve('$detail$suffix')!;
      final page = nativeForumLinkPage(destination) as ProfileBlogDetailPage;
      expect(page.ownerUserId, '101');
      expect(page.blogId, '11');
      expect(page.initialPage, initialPage);
      expect(page.commentId, commentId);
      expect(page.lastCommentPage, last);
      expect(page.focusComments, focus);
    }
  });

  test(
    'inactive blog routes do not mount readers and unsupported routes stay web',
    () {
      final destination = resolver.resolve(detail)!;
      expect(
        nativeForumLinkPage(destination, isActive: false),
        isA<SizedBox>(),
      );
      expect(
        nativeForumLinkPage(resolver.resolve('$detail&unknown=1')!),
        isNull,
      );
      for (final suffix in [
        '&page=3&cid=31',
        '&page=3&goto=last',
        '&page=3#comment_31_li',
      ]) {
        expect(
          nativeForumLinkPage(resolver.resolve('$detail$suffix')!),
          isNull,
        );
      }
    },
  );
}
