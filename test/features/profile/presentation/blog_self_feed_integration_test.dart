import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  for (final empty in [true, false]) {
    testWidgets(
      'my blogs renders ${empty ? 'the empty state' : 'entries'} when the active self link omits uid',
      (tester) async {
        final network = _SelfFeedNetwork(empty: empty);
        final repository = YamiboForumClientBuilder(
          config: ForumClientConfig(
            siteOrigin: Uri.parse('https://example.test'),
            apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
            userAgent: 'mobile-test',
            desktopUserAgent: 'desktop-test',
          ),
          network: network,
        ).buildStandardClient().userBlogDirectory!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              blogAccountIdProvider.overrideWithValue('101'),
              userBlogDirectoryRepositoryProvider.overrideWithValue(repository),
              forumImageRefererProvider.overrideWithValue(
                'https://example.test/',
              ),
            ],
            child: const LocalizedTestApp(home: ProfileBlogPage()),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ProfileBlogPage)),
        );

        await tester.tap(find.text(l10n.profileBlogMine));
        await tester.pumpAndSettle();

        expect(network.requests, hasLength(2));
        expect(network.requests.first.uri.queryParameters['view'], 'all');
        final selfQuery = network.requests.last.uri.queryParameters;
        expect(selfQuery['view'], 'me');
        expect(selfQuery['uid'], '101');
        expect(selfQuery['mobile'], '2');
        expect(find.byKey(const Key('profile-blog-list')), findsOneWidget);
        expect(
          find.text(l10n.profileBlogLoadFailed(l10n.commonParseError)),
          findsNothing,
        );
        if (empty) {
          expect(find.text(l10n.profileBlogEmpty), findsOneWidget);
          expect(find.byKey(const Key('profile-blog-item-11')), findsNothing);
        } else {
          expect(find.text(l10n.profileBlogEmpty), findsNothing);
          expect(find.byKey(const Key('profile-blog-item-11')), findsOneWidget);
          expect(find.text('Self blog title'), findsOneWidget);
          expect(find.text('Author'), findsOneWidget);
          expect(find.text('2026-09-27 09:00'), findsOneWidget);
          expect(find.text('A short blog excerpt'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _SelfFeedNetwork implements ForumClientNetwork {
  _SelfFeedNetwork({required this.empty});

  final bool empty;
  final requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    final self = request.uri.queryParameters['view'] == 'me';
    return ForumTransportSuccess(
      ForumResponse(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: _feedHtml(self: self, empty: !self || empty),
      ),
    );
  }
}

// Discuz's touch template omits uid in the current user's active navigation
// link, including when the account has no blogs or personal categories.
String _feedHtml({required bool self, required bool empty}) =>
    '''
<!DOCTYPE html>
<html>
<head><script>var STYLEID = '19', discuz_uid = '101';</script></head>
<body id="home" class="pg_space">
  <div class="dhnv">
    <a class="flex${self ? ' mon' : ''}" href="home.php?mod=space&do=blog&view=me&mobile=2">My blogs</a>
    <a class="flex${self ? '' : ' mon'}" href="home.php?mod=space&do=blog&view=all&mobile=2">Browse blogs</a>
  </div>
  ${self ? '' : '<div id="dhnavs_li"><a class="mon" href="home.php?mod=space&do=blog&view=all&order=dateline&mobile=2">Latest</a></div>'}
  <div class="threadlist_box cl">
    <div class="threadlist cl">
      ${empty ? '<div class="threadlist_box mt10 cl"><h4>还没有相关的日志</h4></div>' : '''
      <ul><li class="list">
        <div class="threadlist_top">
          <div class="muser">
            <h3><a href="home.php?mod=space&uid=101&do=profile">Author</a></h3>
            <div class="mtime"><span>2026-09-27 09:00</span></div>
          </div>
        </div>
        <a href="home.php?mod=space&uid=101&do=blog&id=11&mobile=2">
          <div class="threadlist_tit">Self blog title</div>
          <div class="threadlist_mes">A short blog excerpt</div>
        </a>
      </li></ul>
      '''}
    </div>
  </div>
</body>
</html>
''';
