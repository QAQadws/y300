import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/data/repositories/user_blog_detail_repository.dart';
import 'package:y300/features/profile/data/repositories/user_blog_directory_repository.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart'
    as forum_adapters;

import '../../../support/data_source_contracts/user_blog_detail_repository_contract_suite.dart';
import '../../../support/data_source_contracts/user_blog_directory_repository_contract_suite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  runUserBlogDirectoryRepositoryContractSuite(
    () => UserBlogDirectoryRepositoryContractDriver(
      name: 'Discuz mobile blog directory HTML',
      createRepository: (scenario) => DiscuzUserBlogDirectoryRepository(
        htmlClient: _htmlClient(_BlogDirectoryAdapter(scenario)),
      ),
    ),
  );

  runUserBlogDetailRepositoryContractSuite(
    () => UserBlogDetailRepositoryContractDriver(
      name: 'Discuz mobile blog detail HTML',
      createRepository: (scenario) => DiscuzUserBlogDetailRepository(
        htmlClient: _htmlClient(_BlogDetailAdapter(scenario)),
      ),
    ),
  );

  group('user blog read adapter wiring', () {
    test('normalizes we, me, all, hot, dateline and page parameters', () async {
      final adapter = _BlogDirectoryAdapter(
        UserBlogDirectoryContractScenario.populated,
      );
      final repository = DiscuzUserBlogDirectoryRepository(
        htmlClient: _htmlClient(adapter),
      );

      await repository.load(const UserBlogDirectoryQuery.friends());
      await repository.load(const UserBlogDirectoryQuery.self());
      await repository.load(const UserBlogDirectoryQuery.public());
      await repository.load(
        const UserBlogDirectoryQuery.public(
          order: UserBlogOrder.recommended,
          page: 2,
        ),
      );

      expect(adapter.requestedUris, hasLength(4));
      expect(adapter.requestedUris[0].queryParameters['view'], 'we');
      expect(adapter.requestedUris[1].queryParameters['view'], 'me');
      expect(adapter.requestedUris[2].queryParameters['view'], 'all');
      expect(
        adapter.requestedUris[2].queryParameters.containsKey('order'),
        isFalse,
      );
      expect(adapter.requestedUris[3].queryParameters['order'], 'hot');
      expect(adapter.requestedUris[3].queryParameters['page'], '2');
      expect(
        adapter.requestedUris.every(
          (uri) =>
              uri.path == '/home.php' &&
              uri.queryParameters['mod'] == 'space' &&
              uri.queryParameters['do'] == 'blog' &&
              uri.queryParameters['mobile'] == '2',
        ),
        isTrue,
      );
    });

    test('uses composite identity for blog detail request', () async {
      final adapter = _BlogDetailAdapter(
        UserBlogDetailContractScenario.populated,
      );

      await DiscuzUserBlogDetailRepository(
        htmlClient: _htmlClient(adapter),
      ).load(const UserBlogDetailQuery(ownerUserId: '101', blogId: '11'));

      expect(adapter.requestedUris, hasLength(1));
      expect(adapter.requestedUris.single.path, '/home.php');
      expect(adapter.requestedUris.single.queryParameters, <String, String>{
        'mod': 'space',
        'uid': '101',
        'do': 'blog',
        'id': '11',
        'mobile': '2',
      });
    });

    test('both cache policies perform one uncached request each', () async {
      final directoryAdapter = _BlogDirectoryAdapter(
        UserBlogDirectoryContractScenario.populated,
      );
      final directoryRepository = DiscuzUserBlogDirectoryRepository(
        htmlClient: _htmlClient(directoryAdapter),
      );
      await directoryRepository.load(
        const UserBlogDirectoryQuery.public(),
        cachePolicy: CacheLoadPolicy.cacheFirst,
      );
      await directoryRepository.load(
        const UserBlogDirectoryQuery.public(),
        cachePolicy: CacheLoadPolicy.networkFirst,
      );

      final detailAdapter = _BlogDetailAdapter(
        UserBlogDetailContractScenario.populated,
      );
      final detailRepository = DiscuzUserBlogDetailRepository(
        htmlClient: _htmlClient(detailAdapter),
      );
      const detailQuery = UserBlogDetailQuery(ownerUserId: '101', blogId: '11');
      await detailRepository.load(
        detailQuery,
        cachePolicy: CacheLoadPolicy.cacheFirst,
      );
      await detailRepository.load(
        detailQuery,
        cachePolicy: CacheLoadPolicy.networkFirst,
      );

      expect(directoryAdapter.requestedUris, hasLength(2));
      expect(detailAdapter.requestedUris, hasLength(2));
    });

    test('invalid directory and detail queries fail before network', () async {
      final directoryAdapter = _BlogDirectoryAdapter(
        UserBlogDirectoryContractScenario.invalidQuery,
      );
      final directoryResult =
          await DiscuzUserBlogDirectoryRepository(
            htmlClient: _htmlClient(directoryAdapter),
          ).load(
            const UserBlogDirectoryQuery(
              scope: UserBlogFeedScope.friends,
              order: UserBlogOrder.latest,
            ),
          );
      final detailAdapter = _BlogDetailAdapter(
        UserBlogDetailContractScenario.invalidQuery,
      );
      final detailResult = await DiscuzUserBlogDetailRepository(
        htmlClient: _htmlClient(detailAdapter),
      ).load(const UserBlogDetailQuery(ownerUserId: ' ', blogId: ''));

      expect(directoryResult.failureOrNull?.kind, DataReadFailureKind.business);
      expect(detailResult.failureOrNull?.kind, DataReadFailureKind.business);
      expect(directoryAdapter.requestedUris, isEmpty);
      expect(detailAdapter.requestedUris, isEmpty);
    });

    test('parse diagnostics do not expose source HTML', () async {
      const marker = 'secret-source-html-marker';
      final result = await DiscuzUserBlogDirectoryRepository(
        htmlClient: _htmlClient(
          _BlogDirectoryAdapter(
            UserBlogDirectoryContractScenario.missingRoot,
            marker: marker,
          ),
        ),
      ).load(const UserBlogDirectoryQuery.public());

      expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      expect(result.failureOrNull?.diagnosticMessage, isNot(contains(marker)));
    });

    test('default providers stay fixed to mobile HTML adapters', () {
      final htmlClient = _htmlClient(
        _BlogDirectoryAdapter(UserBlogDirectoryContractScenario.populated),
      );
      final container = ProviderContainer(
        overrides: [yamiboHtmlClientProvider.overrideWithValue(htmlClient)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(userBlogDirectoryRepositoryProvider),
        isA<forum_adapters.DiscuzUserBlogDirectoryRepository>(),
      );
      expect(
        container.read(userBlogDetailRepositoryProvider),
        isA<forum_adapters.DiscuzUserBlogDetailRepository>(),
      );
    });
  });
}

YamiboHtmlClient _htmlClient(HttpClientAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return YamiboHtmlClient(
    gateway: YamiboHttpGateway(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
  );
}

final class _BlogDirectoryAdapter implements HttpClientAdapter {
  _BlogDirectoryAdapter(this.scenario, {this.marker});

  final UserBlogDirectoryContractScenario scenario;
  final String? marker;
  final List<Uri> requestedUris = <Uri>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);
    switch (scenario) {
      case UserBlogDirectoryContractScenario.networkFailure:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      case UserBlogDirectoryContractScenario.timeout:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      case UserBlogDirectoryContractScenario.cancelled:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      case UserBlogDirectoryContractScenario.unauthorized:
        return ResponseBody.fromString(
          '<html><form id="loginform"></form></html>',
          200,
        );
      case UserBlogDirectoryContractScenario.serverFailure:
        return ResponseBody.fromString('server unavailable', 503);
      default:
        return ResponseBody.fromString(
          _directoryHtml(scenario, marker: marker),
          200,
        );
    }
  }
}

String _directoryHtml(
  UserBlogDirectoryContractScenario scenario, {
  String? marker,
}) {
  if (scenario == UserBlogDirectoryContractScenario.missingRoot) {
    return '<html>$marker<div class="navigation"></div></html>';
  }
  final scope = switch (scenario) {
    UserBlogDirectoryContractScenario.empty => 'me',
    UserBlogDirectoryContractScenario.identityMismatch => 'we',
    _ => 'all',
  };
  final order =
      '<div id="dhnavs_li"><ul><li class="mon"><a href="home.php?mod=space&amp;do=blog&amp;view=all">最新</a></li></ul></div>';
  final items = switch (scenario) {
    UserBlogDirectoryContractScenario.empty => '',
    UserBlogDirectoryContractScenario.missingOptionalFields => _directoryItem(
      blogId: '11',
      ownerId: '101',
      title: 'First',
      sparse: true,
    ),
    UserBlogDirectoryContractScenario.emptyBlogIdentity => _directoryItem(
      blogId: '',
      ownerId: '101',
      title: 'First',
    ),
    UserBlogDirectoryContractScenario.emptyOwnerIdentity => _directoryItem(
      blogId: '11',
      ownerId: '',
      title: 'First',
    ),
    UserBlogDirectoryContractScenario.emptyTitle => _directoryItem(
      blogId: '11',
      ownerId: '101',
      title: '',
    ),
    UserBlogDirectoryContractScenario.duplicateIdentity =>
      '${_directoryItem(blogId: '11', ownerId: '101', title: 'First')}${_directoryItem(blogId: '11', ownerId: '102', title: 'Second')}',
    _ =>
      '${_directoryItem(blogId: '11', ownerId: '101', title: 'First')}${_directoryItem(blogId: '12', ownerId: '102', title: 'Second')}',
  };
  final pagination = switch (scenario) {
    UserBlogDirectoryContractScenario.directionalPagination =>
      '<div class="pg"><strong>1</strong><a class="nxt" href="home.php?mod=space&amp;do=blog&amp;view=all&amp;order=dateline&amp;page=2">Next</a></div>',
    UserBlogDirectoryContractScenario.unknownPagination ||
    UserBlogDirectoryContractScenario.empty ||
    UserBlogDirectoryContractScenario.missingOptionalFields => '',
    UserBlogDirectoryContractScenario.malformedPagination =>
      '<div class="pg"><strong>1</strong><label><span>many pages</span></label></div>',
    _ =>
      '<div class="pg"><strong>1</strong><label><span>/ 3 页</span></label><a class="nxt" href="home.php?mod=space&amp;do=blog&amp;view=all&amp;order=dateline&amp;page=2">Next</a></div>',
  };
  return '''
    <html><body>
      <a href="member.php?mod=logging&amp;action=logout">Logout</a>
      <div class="dhnv"><a class="mon" href="home.php?mod=space&amp;do=blog&amp;view=$scope">Active</a></div>
      ${scope == 'all' ? order : ''}
      <div class="threadlist"><ul>$items</ul></div>
      $pagination
    </body></html>
  ''';
}

String _directoryItem({
  required String blogId,
  required String ownerId,
  required String title,
  bool sparse = false,
}) {
  return '''
    <li class="list">
      ${sparse ? '' : '<div class="threadlist_top"><a class="avatar"><img src="/avatar-$ownerId.jpg"></a><div class="muser"><h3><a href="home.php?mod=space&amp;uid=$ownerId&amp;do=profile">Author $ownerId</a></h3><div class="mtime"><span>Today</span></div></div></div>'}
      <a href="home.php?mod=space&amp;uid=$ownerId&amp;do=blog&amp;id=$blogId">
        <div class="threadlist_tit">$title</div>
        ${sparse ? '' : '<div class="threadlist_mes">Excerpt $blogId</div>'}
      </a>
    </li>
  ''';
}

final class _BlogDetailAdapter implements HttpClientAdapter {
  _BlogDetailAdapter(this.scenario);

  final UserBlogDetailContractScenario scenario;
  final List<Uri> requestedUris = <Uri>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);
    switch (scenario) {
      case UserBlogDetailContractScenario.networkFailure:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      case UserBlogDetailContractScenario.timeout:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      case UserBlogDetailContractScenario.cancelled:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      case UserBlogDetailContractScenario.unauthorized:
        return ResponseBody.fromString('unauthorized', 401);
      case UserBlogDetailContractScenario.serverFailure:
        return ResponseBody.fromString('server unavailable', 503);
      default:
        return ResponseBody.fromString(_detailHtml(scenario), 200);
    }
  }
}

String _detailHtml(UserBlogDetailContractScenario scenario) {
  if (scenario == UserBlogDetailContractScenario.missingRoot) {
    return '<html><body>missing detail root</body></html>';
  }
  final ownerId = scenario == UserBlogDetailContractScenario.ownerMismatch
      ? '999'
      : '101';
  final blogId = scenario == UserBlogDetailContractScenario.identityMismatch
      ? '99'
      : '11';
  final sparse =
      scenario == UserBlogDetailContractScenario.missingOptionalFields;
  final statistics =
      scenario == UserBlogDetailContractScenario.malformedStatistic
      ? '<li class="mtime"><span class="y"><i class="dm-eye"></i><em>seven</em></span></li>'
      : sparse
      ? ''
      : '<li class="mtime"><span class="y"><i class="dm-eye"></i><em>7</em><i class="dm-chat-s"></i><em>2</em></span>Today</li>';
  final comments = switch (scenario) {
    UserBlogDetailContractScenario.missingOptionalFields => '',
    UserBlogDetailContractScenario.emptyCommentIdentity => _commentHtml(
      commentId: '',
      authorId: '301',
      author: 'Commenter A',
    ),
    UserBlogDetailContractScenario.duplicateCommentIdentity =>
      '${_commentHtml(commentId: '201', authorId: '301', author: 'Commenter A')}${_commentHtml(commentId: '201', authorId: '302', author: 'Commenter B')}',
    _ =>
      '${_commentHtml(commentId: '201', authorId: '301', author: 'Commenter A')}${_commentHtml(commentId: '202', authorId: '302', author: 'Commenter B')}',
  };
  final form =
      sparse || scenario == UserBlogDetailContractScenario.commentsUnavailable
      ? ''
      : '<form id="quickcommentform_11"><input name="id" value="11"><input name="idtype" value="blogid"></form>';
  return '''
    <html><body><div class="viewthread">
      <div class="view_tit">Blog title</div>
      <div class="plc">
        ${sparse ? '' : '<div class="avatar"><img src="/owner.jpg"></div>'}
        <ul class="authi"><li class="mtit"><a href="home.php?mod=space&amp;uid=$ownerId">${sparse ? '' : 'Owner'}</a></li>$statistics</ul>
        <div class="message"><p>Body</p></div>
        <div class="threadlist_foot"><a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=blog&amp;id=$blogId">Favorite</a></div>
      </div>
      <div class="doing_list_box">$comments</div>
      $form
    </div></body></html>
  ''';
}

String _commentHtml({
  required String commentId,
  required String authorId,
  required String author,
}) {
  return '''
    <li id="comment_${commentId}_li" class="doing_list_li">
      <a class="avatar"><img src="/comment-$commentId.jpg"></a>
      <div class="muser"><h3><a href="home.php?mod=space&amp;uid=$authorId">$author</a></h3><div class="mtime"><span>Now</span></div></div>
      <div class="do_comment"><p>Comment $commentId</p></div>
    </li>
  ''';
}
