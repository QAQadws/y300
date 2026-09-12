import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import '../support/blog_fixtures.dart';

void main() {
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  read(String source) async {
    final network = BlogFixtureNetwork(source);
    final result =
        await YamiboForumClientBuilder(config: blogConfig, network: network)
            .buildStandardClient()
            .userBlogDetail!
            .load(const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'));
    expect(network.requests, hasLength(1));
    return result;
  }

  test(
    'only explicit toolbar links advertise favorite, share and invite',
    () async {
      final source = blogArticle()
          .replaceFirst('type=blog&id=11', 'type=blog&id=11&spaceuid=101')
          .replaceFirst('>Action</a>', '''>Action</a>
      <a href="home.php?mod=spacecp&ac=share&type=blog&id=11&handlekey=sharebloghk_11">Share</a>
      <a href="misc.php?mod=invite&action=blog&id=11">Invite</a>''');
      final result = await read(source);
      expect(result.failureOrNull, isNull);
      expect(
        result.dataOrNull!.socialActions,
        UserBlogSocialAction.values.toSet(),
      );
      expect(
        () => result.dataOrNull!.socialActions.clear(),
        throwsUnsupportedError,
      );
      expect(result.dataOrNull!.actions, isEmpty);
    },
  );

  for (final link in [
    'home.php?mod=spacecp&ac=favorite&type=blog&id=11',
    'home.php?mod=spacecp&ac=favorite&type=blog&id=11&spaceuid=102',
    'home.php?mod=spacecp&ac=favorite&type=blog&id=11&spaceuid=101&op=delete',
    'home.php?mod=spacecp&ac=favorite&type=blog&id=11&spaceuid=101&favoritesubmit=true',
    'home.php?mod=spacecp&ac=share&type=blog&id=11&handlekey=another_action',
    'home.php?mod=spacecp&ac=share&type=blog&id=11&op=delete',
    'misc.php?mod=invite&action=blog&id=11&invitesubmit=true',
    'misc.php?mod=invite&action=blog&id=11&mobile=1',
    'https://outside.test/home.php?mod=spacecp&ac=share&type=blog&id=11',
    'http://example.test/home.php?mod=spacecp&ac=share&type=blog&id=11',
    'https://example.test:444/home.php?mod=spacecp&ac=share&type=blog&id=11',
    'home.php?mod=spacecp&ac=share&type=blog&id=11&id=99',
    'home.php?mod=spacecp&ac=share&type=blog&id=11#unknown',
  ]) {
    test('an unproven action is not advertised: $link', () async {
      final source = blogArticle().replaceFirst(
        'home.php?mod=spacecp&ac=favorite&type=blog&id=11',
        link,
      );
      final result = await read(source);
      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.socialActions, isEmpty);
    });
  }

  test('article content cannot impersonate the source toolbar', () async {
    final source = blogArticle().replaceFirst(
      'Real <b>rich text</b>',
      '''<a href="home.php?mod=spacecp&ac=favorite&type=blog&id=11&spaceuid=101">Favorite</a>
      <a href="misc.php?mod=invite&action=blog&id=11">Invite</a>''',
    );
    final result = await read(source);
    expect(result.failureOrNull, isNull);
    expect(result.dataOrNull!.socialActions, isEmpty);
  });
}
