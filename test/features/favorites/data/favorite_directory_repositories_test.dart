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
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/favorites/data/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';

import '../../../support/data_source_contracts/favorite_forum_directory_repository_contract_suite.dart';
import '../../../support/data_source_contracts/favorite_thread_directory_repository_contract_suite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  runFavoriteForumDirectoryRepositoryContractSuite(
    () => FavoriteForumDirectoryRepositoryContractDriver(
      name: 'Discuz API myfavforum',
      createRepository: _buildForumRepository,
    ),
  );
  runFavoriteThreadDirectoryRepositoryContractSuite(
    () => FavoriteThreadDirectoryRepositoryContractDriver(
      name: 'Discuz API myfavthread',
      createRepository: _buildThreadRepository,
    ),
  );

  group('favorite directory adapter wiring', () {
    test('uses myfavforum and explicit myfavthread v4 page requests', () async {
      final forumAdapter = _ScenarioAdapter.forum(
        FavoriteForumDirectoryContractScenario.empty,
      );
      final threadAdapter = _ScenarioAdapter.thread(
        FavoriteThreadDirectoryContractScenario.populated,
      );

      await DiscuzFavoriteForumDirectoryRepository(
        _apiClient(forumAdapter),
      ).load(const FavoriteForumDirectoryQuery());
      await DiscuzFavoriteThreadDirectoryRepository(
        _apiClient(threadAdapter),
      ).load(const FavoriteThreadDirectoryQuery(page: 2));

      expect(
        forumAdapter.requestedUris.single.queryParameters['module'],
        'myfavforum',
      );
      expect(forumAdapter.requestedUris.single.queryParameters['version'], '4');
      expect(
        threadAdapter.requestedUris.single.queryParameters,
        containsPair('module', 'myfavthread'),
      );
      expect(
        threadAdapter.requestedUris.single.queryParameters,
        containsPair('version', '4'),
      );
      expect(
        threadAdapter.requestedUris.single.queryParameters,
        containsPair('page', '2'),
      );
    });

    test('both cache policies perform exactly one network read', () async {
      final forumAdapter = _ScenarioAdapter.forum(
        FavoriteForumDirectoryContractScenario.empty,
      );
      final forumRepository = DiscuzFavoriteForumDirectoryRepository(
        _apiClient(forumAdapter),
      );
      await forumRepository.load(
        const FavoriteForumDirectoryQuery(),
        cachePolicy: CacheLoadPolicy.cacheFirst,
      );
      await forumRepository.load(
        const FavoriteForumDirectoryQuery(),
        cachePolicy: CacheLoadPolicy.networkFirst,
      );

      final threadAdapter = _ScenarioAdapter.thread(
        FavoriteThreadDirectoryContractScenario.empty,
      );
      final threadRepository = DiscuzFavoriteThreadDirectoryRepository(
        _apiClient(threadAdapter),
      );
      await threadRepository.load(
        const FavoriteThreadDirectoryQuery(),
        cachePolicy: CacheLoadPolicy.cacheFirst,
      );
      await threadRepository.load(
        const FavoriteThreadDirectoryQuery(),
        cachePolicy: CacheLoadPolicy.networkFirst,
      );

      expect(forumAdapter.requestedUris, hasLength(2));
      expect(threadAdapter.requestedUris, hasLength(2));
    });

    test('invalid thread query fails before network access', () async {
      final adapter = _ScenarioAdapter.thread(
        FavoriteThreadDirectoryContractScenario.invalidQuery,
      );
      final result = await DiscuzFavoriteThreadDirectoryRepository(
        _apiClient(adapter),
      ).load(const FavoriteThreadDirectoryQuery(page: 0));

      expect(result.failureOrNull?.kind, DataReadFailureKind.business);
      expect(adapter.requestedUris, isEmpty);
    });

    test('default providers remain fixed to Discuz API adapters', () {
      final adapter = _ScenarioAdapter.forum(
        FavoriteForumDirectoryContractScenario.empty,
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(_apiClient(adapter))],
      );
      addTearDown(container.dispose);

      expect(
        container.read(favoriteForumDirectoryRepositoryProvider),
        isA<DiscuzFavoriteForumDirectoryRepository>(),
      );
      expect(
        container.read(favoriteThreadDirectoryRepositoryProvider),
        isA<DiscuzFavoriteThreadDirectoryRepository>(),
      );
    });
  });
}

DiscuzFavoriteForumDirectoryRepository _buildForumRepository(
  FavoriteForumDirectoryContractScenario scenario,
) {
  final adapter = _ScenarioAdapter.forum(scenario);
  return DiscuzFavoriteForumDirectoryRepository(_apiClient(adapter));
}

DiscuzFavoriteThreadDirectoryRepository _buildThreadRepository(
  FavoriteThreadDirectoryContractScenario scenario,
) {
  final adapter = _ScenarioAdapter.thread(scenario);
  return DiscuzFavoriteThreadDirectoryRepository(_apiClient(adapter));
}

ApiClient _apiClient(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: dio,
    enableLog: false,
  );
}

final class _ScenarioAdapter implements HttpClientAdapter {
  _ScenarioAdapter.forum(this.forumScenario) : threadScenario = null;

  _ScenarioAdapter.thread(this.threadScenario) : forumScenario = null;

  final FavoriteForumDirectoryContractScenario? forumScenario;
  final FavoriteThreadDirectoryContractScenario? threadScenario;
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
    final scenario = forumScenario ?? threadScenario!;
    switch (scenario) {
      case FavoriteForumDirectoryContractScenario.networkFailure ||
          FavoriteThreadDirectoryContractScenario.networkFailure:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'network failure',
        );
      case FavoriteForumDirectoryContractScenario.timeout ||
          FavoriteThreadDirectoryContractScenario.timeout:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      case FavoriteForumDirectoryContractScenario.cancelled ||
          FavoriteThreadDirectoryContractScenario.cancelled:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      case FavoriteForumDirectoryContractScenario.unauthorized ||
          FavoriteThreadDirectoryContractScenario.unauthorized:
        return ResponseBody.fromString('unauthorized', 401);
      case FavoriteForumDirectoryContractScenario.businessFailure ||
          FavoriteThreadDirectoryContractScenario.businessFailure:
        return ResponseBody.fromString(
          jsonEncode(<String, Object?>{
            'Version': '4',
            'Charset': 'UTF-8',
            'Variables': <String, Object?>{},
            'Message': <String, Object?>{
              'messageval': 'login_before_enter_home',
              'messagestr': 'authentication required',
            },
          }),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      case FavoriteForumDirectoryContractScenario.serverFailure ||
          FavoriteThreadDirectoryContractScenario.serverFailure:
        return ResponseBody.fromString('server unavailable', 503);
      default:
        break;
    }

    final variables = forumScenario != null
        ? _forumVariables(forumScenario!)
        : _threadVariables(
            threadScenario!,
            int.tryParse(options.uri.queryParameters['page'] ?? '1') ?? 1,
          );
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{
        'Version': '4',
        'Charset': 'UTF-8',
        'Variables': variables,
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

Map<String, Object?> _forumVariables(
  FavoriteForumDirectoryContractScenario scenario,
) {
  final first = <String, Object?>{
    'favid': 'fav-55',
    'id': '55',
    'title': '综合区',
    'description': '综合讨论',
    'threads': '12',
    'posts': '34',
    'todayposts': '5',
  };
  final second = <String, Object?>{
    'favid': 'fav-30',
    'id': '30',
    'title': '漫画区',
  };
  return switch (scenario) {
    FavoriteForumDirectoryContractScenario.empty => <String, Object?>{
      'list': <Object?>[],
    },
    FavoriteForumDirectoryContractScenario.missingList => <String, Object?>{},
    FavoriteForumDirectoryContractScenario.emptyIdentity => <String, Object?>{
      'list': <Object?>[
        <String, Object?>{...first, 'id': ''},
      ],
    },
    FavoriteForumDirectoryContractScenario.emptyTitle => <String, Object?>{
      'list': <Object?>[
        <String, Object?>{...first, 'title': ' '},
      ],
    },
    FavoriteForumDirectoryContractScenario.duplicateIdentity =>
      <String, Object?>{
        'list': <Object?>[
          first,
          <String, Object?>{...second, 'id': '55'},
        ],
      },
    FavoriteForumDirectoryContractScenario.duplicateRemoteIdentity =>
      <String, Object?>{
        'list': <Object?>[
          first,
          <String, Object?>{...second, 'favid': 'fav-55'},
        ],
      },
    FavoriteForumDirectoryContractScenario.malformedNumber => <String, Object?>{
      'list': <Object?>[
        <String, Object?>{...first, 'threads': '12 topics'},
      ],
    },
    _ => <String, Object?>{
      'list': <Object?>[first, second],
    },
  };
}

Map<String, Object?> _threadVariables(
  FavoriteThreadDirectoryContractScenario scenario,
  int requestedPage,
) {
  final first = <String, Object?>{
    'favid': 'fav-100',
    'id': '100',
    'title': '第一帖',
    'description': '简介',
    'author': '作者A',
    'replies': '3',
    'dateline': '1767225600',
  };
  final second = <String, Object?>{
    'favid': 'fav-200',
    'id': '200',
    'title': '第二帖',
    'replies': '0',
    'dateline': '1767225601',
  };
  final populatedItems = requestedPage == 1
      ? <Object?>[first, second]
      : <Object?>[
          <String, Object?>{...second, 'favid': 'fav-300', 'id': '300'},
        ];
  return switch (scenario) {
    FavoriteThreadDirectoryContractScenario.empty => <String, Object?>{
      'count': '0',
      'perpage': '20',
      'list': <Object?>[],
    },
    FavoriteThreadDirectoryContractScenario.missingOptionalFields =>
      <String, Object?>{
        'count': '1',
        'perpage': '20',
        'list': <Object?>[
          <String, Object?>{'id': '100', 'title': '稀疏主题'},
        ],
      },
    FavoriteThreadDirectoryContractScenario.zeroTimestamp => <String, Object?>{
      'count': '1',
      'perpage': '20',
      'list': <Object?>[
        <String, Object?>{...first, 'dateline': '0'},
      ],
    },
    FavoriteThreadDirectoryContractScenario.missingList => <String, Object?>{
      'count': '1',
      'perpage': '20',
    },
    FavoriteThreadDirectoryContractScenario.emptyIdentity => _singleThread(
      <String, Object?>{...first, 'id': ''},
    ),
    FavoriteThreadDirectoryContractScenario.emptyTitle => _singleThread(
      <String, Object?>{...first, 'title': ''},
    ),
    FavoriteThreadDirectoryContractScenario.duplicateIdentity => _twoThreads(
      first,
      <String, Object?>{...second, 'id': '100'},
    ),
    FavoriteThreadDirectoryContractScenario.duplicateRemoteIdentity =>
      _twoThreads(first, <String, Object?>{...second, 'favid': 'fav-100'}),
    FavoriteThreadDirectoryContractScenario.malformedNumber => _singleThread(
      <String, Object?>{...first, 'replies': '-1'},
    ),
    FavoriteThreadDirectoryContractScenario.malformedTimestamp => _singleThread(
      <String, Object?>{...first, 'dateline': 'yesterday'},
    ),
    _ => <String, Object?>{
      'count': '3',
      'perpage': '2',
      'list': populatedItems,
    },
  };
}

Map<String, Object?> _singleThread(Map<String, Object?> item) {
  return <String, Object?>{
    'count': '1',
    'perpage': '20',
    'list': <Object?>[item],
  };
}

Map<String, Object?> _twoThreads(
  Map<String, Object?> first,
  Map<String, Object?> second,
) {
  return <String, Object?>{
    'count': '2',
    'perpage': '20',
    'list': <Object?>[first, second],
  };
}
