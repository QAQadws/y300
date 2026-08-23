import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo/yamibo_resource_client.dart';
import 'package:y300/features/forum/data/repositories/forum_directory_repository.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/services/forum_home_carousel_image_probe.dart';
import 'package:y300/features/forum/domain/models/forum_directory_models.dart';
import 'package:y300/features/forum/domain/repositories/forum_directory_repository.dart';

import '../../../support/data_source_contracts/forum_directory_repository_contract_suite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  runForumDirectoryRepositoryContractSuite(
    () => ForumDirectoryRepositoryContractDriver(
      name: 'mobile HTML',
      createRepository: _buildHtmlRepository,
      expectsNestedForums: false,
    ),
  );

  runForumDirectoryRepositoryContractSuite(
    () => ForumDirectoryRepositoryContractDriver(
      name: 'Discuz API forumindex',
      createRepository: _buildApiRepository,
      expectsNestedForums: true,
    ),
  );

  test('HTML directory read never probes carousel images', () async {
    final adapter = _ScenarioAdapter(
      source: _DirectorySource.html,
      scenario: ForumDirectoryContractScenario.populated,
      includeCarousel: true,
    );
    final repository = _buildHtmlRepositoryWithAdapter(adapter);

    final result = await repository.load(const ForumDirectoryQuery());

    expect(result.isSuccess, isTrue);
    expect(adapter.imageRequests, 0);
  });

  test('API adapter preserves recursive sublist structure', () async {
    final result = await _buildApiRepository(
      ForumDirectoryContractScenario.populated,
    ).load(const ForumDirectoryQuery());

    final parent = result.dataOrNull!.sections.single.forums.single;
    expect(parent.fid, '30');
    expect(parent.children.single.fid, '31');
  });
}

ForumDirectoryRepository _buildHtmlRepository(
  ForumDirectoryContractScenario scenario,
) {
  return _buildHtmlRepositoryWithAdapter(
    _ScenarioAdapter(source: _DirectorySource.html, scenario: scenario),
  );
}

ForumHomeHtmlRepository _buildHtmlRepositoryWithAdapter(
  _ScenarioAdapter adapter,
) {
  final gateway = YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: Dio(
      BaseOptions(
        baseUrl: 'https://bbs.yamibo.com',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    )..httpClientAdapter = adapter,
    enableLog: false,
  );
  return ForumHomeHtmlRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
    imageProbe: ForumHomeCarouselImageProbe(
      resourceClient: YamiboResourceClient(gateway: gateway),
      headerBuilder: const _Headers(),
    ),
  );
}

ForumDirectoryRepository _buildApiRepository(
  ForumDirectoryContractScenario scenario,
) {
  final adapter = _ScenarioAdapter(
    source: _DirectorySource.api,
    scenario: scenario,
  );
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com/api/mobile/index.php',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return DiscuzForumDirectoryRepository(
    ApiClient(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
  );
}

enum _DirectorySource { html, api }

final class _ScenarioAdapter implements HttpClientAdapter {
  _ScenarioAdapter({
    required this.source,
    required this.scenario,
    this.includeCarousel = false,
  });

  final _DirectorySource source;
  final ForumDirectoryContractScenario scenario;
  final bool includeCarousel;
  int imageRequests = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path.endsWith('.jpg')) {
      imageRequests += 1;
      return ResponseBody.fromBytes(Uint8List(24), 200);
    }
    switch (scenario) {
      case ForumDirectoryContractScenario.serverFailure:
        return ResponseBody.fromString('unavailable', 503);
      case ForumDirectoryContractScenario.timeout:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      case ForumDirectoryContractScenario.cancelled:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      case ForumDirectoryContractScenario.populated:
      case ForumDirectoryContractScenario.empty:
      case ForumDirectoryContractScenario.missingTodayPosts:
      case ForumDirectoryContractScenario.malformed:
      case ForumDirectoryContractScenario.missingRoot:
      case ForumDirectoryContractScenario.emptySectionIdentity:
      case ForumDirectoryContractScenario.duplicateSectionIdentity:
      case ForumDirectoryContractScenario.duplicateForumIdentity:
        break;
    }
    final body = source == _DirectorySource.html
        ? _htmlFor(scenario, includeCarousel: includeCarousel)
        : jsonEncode(_apiFor(scenario));
    return ResponseBody.fromString(
      body,
      200,
      headers: source == _DirectorySource.api
          ? <String, List<String>>{
              Headers.contentTypeHeader: <String>['application/json'],
            }
          : const <String, List<String>>{},
    );
  }
}

String _htmlFor(
  ForumDirectoryContractScenario scenario, {
  required bool includeCarousel,
}) {
  if (scenario == ForumDirectoryContractScenario.malformed ||
      scenario == ForumDirectoryContractScenario.missingRoot) {
    return '<body id="forum"></body>';
  }
  if (scenario == ForumDirectoryContractScenario.empty) {
    return '<body id="forum"><div class="forumlist"></div></body>';
  }
  if (scenario == ForumDirectoryContractScenario.emptySectionIdentity) {
    return '''
      <body id="forum">
        <div class="forumlist">
          <div class="subforumshow" href=".directory-target"><h2>庙堂</h2></div>
          <div class="directory-target">
            <a class="murl" href="forum.php?mod=forumdisplay&amp;fid=30">
              <span class="mtit">漫画区</span>
            </a>
          </div>
        </div>
      </body>
    ''';
  }
  if (scenario == ForumDirectoryContractScenario.duplicateSectionIdentity) {
    return '''
      <body id="forum">
        <div class="forumlist">
          <div class="subforumshow" href="#sub-forum_14"><h2>庙堂</h2></div>
          <div class="subforumshow" href="#sub-forum_14"><h2>庙堂副本</h2></div>
          <div id="sub-forum_14">
            <a class="murl" href="forum.php?mod=forumdisplay&amp;fid=30">
              <span class="mtit">漫画区</span>
            </a>
          </div>
        </div>
      </body>
    ''';
  }
  if (scenario == ForumDirectoryContractScenario.duplicateForumIdentity) {
    return '''
      <body id="forum">
        <div class="forumlist">
          <div class="subforumshow" href="#sub-forum_14"><h2>庙堂</h2></div>
          <div id="sub-forum_14">
            <a class="murl" href="forum.php?mod=forumdisplay&amp;fid=30">
              <span class="mtit">漫画区</span>
            </a>
            <a class="murl" href="forum.php?mod=forumdisplay&amp;fid=30">
              <span class="mtit">漫画区副本</span>
            </a>
          </div>
        </div>
      </body>
    ''';
  }
  final count = scenario == ForumDirectoryContractScenario.missingTodayPosts
      ? ''
      : '<span class="mnum">今日 5</span>';
  final carousel = includeCarousel
      ? '''
        <div class="index-top-wrapper"><div class="yami-swiper">
          <div class="swiper-slide"><a href="thread-1-1-1.html">
            <img src="banner.jpg"></a></div>
        </div></div>
        '''
      : '';
  return '''
    <body id="forum">
      $carousel
      <div class="forumlist">
        <div class="subforumshow" href="#sub-forum_14"><h2>庙堂</h2></div>
        <div id="sub-forum_14" class="sub-forum">
          <a class="murl" href="forum.php?mod=forumdisplay&amp;fid=30">
            <span class="mtit">漫画区$count</span>
            <span class="mtxt">漫画讨论</span>
          </a>
        </div>
      </div>
    </body>
  ''';
}

Map<String, Object?> _apiFor(ForumDirectoryContractScenario scenario) {
  if (scenario == ForumDirectoryContractScenario.malformed ||
      scenario == ForumDirectoryContractScenario.missingRoot) {
    return <String, Object?>{
      'Version': '4',
      'Charset': 'utf-8',
      'Variables': <String, Object?>{'catlist': <Object?>[]},
    };
  }
  if (scenario == ForumDirectoryContractScenario.empty) {
    return <String, Object?>{
      'Version': '4',
      'Charset': 'utf-8',
      'Variables': <String, Object?>{
        'catlist': <Object?>[],
        'forumlist': <Object?>[],
      },
    };
  }
  final missingTodayPosts =
      scenario == ForumDirectoryContractScenario.missingTodayPosts;
  if (scenario == ForumDirectoryContractScenario.emptySectionIdentity) {
    return <String, Object?>{
      'Version': '4',
      'Charset': 'utf-8',
      'Variables': <String, Object?>{
        'catlist': <Object?>[
          <String, Object?>{'fid': '', 'name': '无效分组', 'forums': <String>[]},
        ],
        'forumlist': <Object?>[],
      },
    };
  }
  if (scenario == ForumDirectoryContractScenario.duplicateSectionIdentity) {
    return <String, Object?>{
      'Version': '4',
      'Charset': 'utf-8',
      'Variables': <String, Object?>{
        'catlist': <Object?>[
          <String, Object?>{'fid': '14', 'name': '庙堂', 'forums': <String>[]},
          <String, Object?>{'fid': '14', 'name': '庙堂副本', 'forums': <String>[]},
        ],
        'forumlist': <Object?>[],
      },
    };
  }
  if (scenario == ForumDirectoryContractScenario.duplicateForumIdentity) {
    return <String, Object?>{
      'Version': '4',
      'Charset': 'utf-8',
      'Variables': <String, Object?>{
        'catlist': <Object?>[
          <String, Object?>{
            'fid': '14',
            'name': '庙堂',
            'forums': <String>['30'],
          },
        ],
        'forumlist': <Object?>[
          <String, Object?>{
            'fid': '30',
            'name': '漫画区',
            'description': '',
            'sublist': <Object?>[],
          },
          <String, Object?>{
            'fid': '30',
            'name': '漫画区副本',
            'description': '',
            'sublist': <Object?>[],
          },
        ],
      },
    };
  }
  return <String, Object?>{
    'Version': '4',
    'Charset': 'utf-8',
    'Variables': <String, Object?>{
      'catlist': <Object?>[
        <String, Object?>{
          'fid': '14',
          'name': '庙堂',
          'forums': <String>['30'],
        },
      ],
      'forumlist': <Object?>[
        <String, Object?>{
          'fid': '30',
          'name': '漫画区',
          'description': '漫画讨论',
          if (!missingTodayPosts) 'todayposts': '5',
          'sublist': <Object?>[
            <String, Object?>{
              'fid': '31',
              'name': '漫画子版',
              'description': '',
              'todayposts': '0',
              'sublist': <Object?>[],
            },
          ],
        },
      ],
    },
  };
}

final class _Headers implements ImageRequestHeaderBuilder {
  const _Headers();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
  }
}
