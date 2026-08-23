import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/data/repositories/current_user_profile_repository.dart';
import 'package:y300/features/profile/data/repositories/forum_user_profile_repository.dart';
import 'package:y300/features/profile/domain/models/current_user_profile_models.dart';
import 'package:y300/features/profile/domain/models/forum_user_profile_models.dart';

import '../../../support/data_source_contracts/current_user_profile_repository_contract_suite.dart';
import '../../../support/data_source_contracts/forum_user_profile_repository_contract_suite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  runCurrentUserProfileRepositoryContractSuite(
    () => CurrentUserProfileRepositoryContractDriver(
      name: 'Discuz profile API',
      createRepository: (scenario) => DiscuzCurrentUserProfileRepository(
        _apiClient(_CurrentProfileAdapter(scenario)),
      ),
    ),
  );

  runForumUserProfileRepositoryContractSuite(
    () => ForumUserProfileRepositoryContractDriver(
      name: 'Discuz mobile profile HTML',
      createRepository: (scenario) => DiscuzForumUserProfileRepository(
        htmlClient: _htmlClient(_ForumProfileAdapter(scenario)),
      ),
    ),
  );

  group('profile read adapter wiring', () {
    test('uses profile API default request', () async {
      final adapter = _CurrentProfileAdapter(
        CurrentUserProfileContractScenario.populated,
      );

      await DiscuzCurrentUserProfileRepository(
        _apiClient(adapter),
      ).load(const CurrentUserProfileQuery());

      expect(adapter.requestedUris, hasLength(1));
      expect(adapter.requestedUris.single.queryParameters['module'], 'profile');
      expect(adapter.requestedUris.single.queryParameters['version'], '4');
    });

    test('uses public and self mobile profile requests', () async {
      final adapter = _ForumProfileAdapter(
        ForumUserProfileContractScenario.populated,
      );
      final repository = DiscuzForumUserProfileRepository(
        htmlClient: _htmlClient(adapter),
      );

      final publicResult = await repository.load(
        const ForumUserProfileQuery(userId: '509957'),
      );
      final selfResult = await repository.load(
        const ForumUserProfileQuery(
          userId: '509957',
          view: ForumUserProfileView.self,
        ),
      );

      expect(publicResult.isSuccess, isTrue);
      expect(selfResult.isSuccess, isTrue);
      expect(adapter.requestedUris, hasLength(2));
      expect(adapter.requestedUris.first.path, '/home.php');
      expect(
        adapter.requestedUris.first.queryParameters,
        containsPair('mod', 'space'),
      );
      expect(
        adapter.requestedUris.first.queryParameters,
        containsPair('uid', '509957'),
      );
      expect(
        adapter.requestedUris.first.queryParameters,
        containsPair('do', 'profile'),
      );
      expect(
        adapter.requestedUris.first.queryParameters,
        containsPair('mobile', '2'),
      );
      expect(
        adapter.requestedUris.first.queryParameters.containsKey('mycenter'),
        isFalse,
      );
      expect(adapter.requestedUris.last.queryParameters['mycenter'], '1');
      expect(
        adapter.userAgents.every((value) => value.contains('Mobile')),
        isTrue,
      );
    });

    test('both cache policies perform one uncached request each', () async {
      final apiAdapter = _CurrentProfileAdapter(
        CurrentUserProfileContractScenario.populated,
      );
      final currentRepository = DiscuzCurrentUserProfileRepository(
        _apiClient(apiAdapter),
      );
      await currentRepository.load(
        const CurrentUserProfileQuery(),
        cachePolicy: CacheLoadPolicy.cacheFirst,
      );
      await currentRepository.load(
        const CurrentUserProfileQuery(),
        cachePolicy: CacheLoadPolicy.networkFirst,
      );

      final htmlAdapter = _ForumProfileAdapter(
        ForumUserProfileContractScenario.populated,
      );
      final forumRepository = DiscuzForumUserProfileRepository(
        htmlClient: _htmlClient(htmlAdapter),
      );
      await forumRepository.load(
        const ForumUserProfileQuery(userId: '509957'),
        cachePolicy: CacheLoadPolicy.cacheFirst,
      );
      await forumRepository.load(
        const ForumUserProfileQuery(userId: '509957'),
        cachePolicy: CacheLoadPolicy.networkFirst,
      );

      expect(apiAdapter.requestedUris, hasLength(2));
      expect(htmlAdapter.requestedUris, hasLength(2));
    });

    test('invalid public profile query fails before network access', () async {
      final adapter = _ForumProfileAdapter(
        ForumUserProfileContractScenario.invalidQuery,
      );
      final result = await DiscuzForumUserProfileRepository(
        htmlClient: _htmlClient(adapter),
      ).load(const ForumUserProfileQuery(userId: ' '));

      expect(result.failureOrNull?.kind, DataReadFailureKind.business);
      expect(adapter.requestedUris, isEmpty);
    });

    test('default providers stay fixed to API and mobile HTML', () {
      final apiClient = _apiClient(
        _CurrentProfileAdapter(CurrentUserProfileContractScenario.populated),
      );
      final htmlClient = _htmlClient(
        _ForumProfileAdapter(ForumUserProfileContractScenario.populated),
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          yamiboHtmlClientProvider.overrideWithValue(htmlClient),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(currentUserProfileRepositoryProvider),
        isA<DiscuzCurrentUserProfileRepository>(),
      );
      expect(
        container.read(forumUserProfileRepositoryProvider),
        isA<DiscuzForumUserProfileRepository>(),
      );
    });
  });
}

ApiClient _apiClient(HttpClientAdapter adapter) {
  return ApiClient(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: Dio()..httpClientAdapter = adapter,
    enableLog: false,
  );
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

final class _CurrentProfileAdapter implements HttpClientAdapter {
  _CurrentProfileAdapter(this.scenario);

  final CurrentUserProfileContractScenario scenario;
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
      case CurrentUserProfileContractScenario.networkFailure:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      case CurrentUserProfileContractScenario.timeout:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      case CurrentUserProfileContractScenario.cancelled:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      case CurrentUserProfileContractScenario.unauthorized:
        return ResponseBody.fromString('unauthorized', 401);
      case CurrentUserProfileContractScenario.serverFailure:
        return ResponseBody.fromString('server unavailable', 503);
      case CurrentUserProfileContractScenario.businessFailure:
        return _jsonResponse(
          variables: const <String, Object?>{},
          message: const <String, Object?>{
            'messageval': 'profile_unavailable',
            'messagestr': 'profile unavailable',
          },
        );
      default:
        return _jsonResponse(variables: _currentVariables(scenario));
    }
  }
}

Map<String, Object?> _currentVariables(
  CurrentUserProfileContractScenario scenario,
) {
  final base = <String, Object?>{
    'member_uid': '42',
    'member_username': 'Alice',
    'member_avatar': 'https://bbs.yamibo.com/avatar.jpg',
    'groupid': '10',
    'space': <String, Object?>{
      'uid': '42',
      'username': 'Alice',
      'credits': '12',
      'posts': '34',
      'threads': '5',
    },
  };
  switch (scenario) {
    case CurrentUserProfileContractScenario.missingOptionalFields:
      return <String, Object?>{
        'member_uid': '42',
        'member_username': 'Alice',
        'space': <String, Object?>{'uid': '42', 'username': 'Alice'},
      };
    case CurrentUserProfileContractScenario.anonymous:
      return <String, Object?>{...base, 'member_uid': '0'};
    case CurrentUserProfileContractScenario.missingSpace:
      return <String, Object?>{...base}..remove('space');
    case CurrentUserProfileContractScenario.identityMismatch:
      return <String, Object?>{
        ...base,
        'space': <String, Object?>{
          ...(base['space']! as Map<String, Object?>),
          'uid': '99',
        },
      };
    case CurrentUserProfileContractScenario.nameMismatch:
      return <String, Object?>{
        ...base,
        'space': <String, Object?>{
          ...(base['space']! as Map<String, Object?>),
          'username': 'Bob',
        },
      };
    case CurrentUserProfileContractScenario.malformedNumber:
      return <String, Object?>{
        ...base,
        'space': <String, Object?>{
          ...(base['space']! as Map<String, Object?>),
          'posts': '34 posts',
        },
      };
    default:
      return base;
  }
}

ResponseBody _jsonResponse({
  required Map<String, Object?> variables,
  Map<String, Object?>? message,
}) {
  final body = <String, Object?>{
    'Version': '4',
    'Charset': 'UTF-8',
    'Variables': variables,
  };
  if (message != null) {
    body['Message'] = message;
  }
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: const <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json'],
    },
  );
}

final class _ForumProfileAdapter implements HttpClientAdapter {
  _ForumProfileAdapter(this.scenario);

  final ForumUserProfileContractScenario scenario;
  final List<Uri> requestedUris = <Uri>[];
  final List<String> userAgents = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);
    userAgents.add(options.headers['User-Agent']?.toString() ?? '');
    switch (scenario) {
      case ForumUserProfileContractScenario.networkFailure:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      case ForumUserProfileContractScenario.timeout:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      case ForumUserProfileContractScenario.cancelled:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      case ForumUserProfileContractScenario.unauthorized:
        return ResponseBody.fromString(
          '<html><form id="loginform"></form></html>',
          200,
        );
      case ForumUserProfileContractScenario.serverFailure:
        return ResponseBody.fromString('server unavailable', 503);
      default:
        return ResponseBody.fromString(_forumProfileHtml(scenario), 200);
    }
  }
}

String _forumProfileHtml(ForumUserProfileContractScenario scenario) {
  if (scenario == ForumUserProfileContractScenario.missingRoot) {
    return '<html><body>missing profile root</body></html>';
  }
  final name = scenario == ForumUserProfileContractScenario.emptyName
      ? ''
      : 'Alice';
  final uid = scenario == ForumUserProfileContractScenario.identityMismatch
      ? '99'
      : '509957';
  final details = scenario == ForumUserProfileContractScenario.missingIdentity
      ? '<div class="myinfo_list"><ul><li><b>个人资料</b></li></ul></div>'
      : '''
        <div class="myinfo_list"><ul>
          <li><b>个人资料</b></li>
          <li>UID<span>$uid</span></li>
          <li>用户组<span>百合会员</span></li>
        </ul></div>
      ''';
  final sparse =
      scenario == ForumUserProfileContractScenario.missingOptionalFields;
  final metrics = sparse
      ? ''
      : scenario == ForumUserProfileContractScenario.unlabeledMetric
      ? '<div class="user_box"><ul><li><span>12</span></li></ul></div>'
      : '''
        <div class="user_box"><ul>
          <li><span>12</span>总积分</li>
          <li><span>3 点</span>积分</li>
        </ul></div>
      ''';
  return '''
    <html><head>${sparse ? '' : '<style>.user_avatar { background-image: url(/cover.jpg) }</style>'}</head>
    <body><div class="userinfo">
      ${sparse ? '' : '<div class="avatar_m"><img src="/avatar.jpg"></div>'}
      <h2 class="name">$name</h2>
      $metrics
      ${sparse ? '' : '<div class="myinfo_list"><ul><li><b>个人签名</b></li><li class="sig"><b>Hello</b></li></ul></div>'}
      $details
    </div><a href="member.php?mod=logging&amp;action=logout">Logout</a></body></html>
  ''';
}
