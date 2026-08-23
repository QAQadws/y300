import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/tags/data/repositories/forum_tag_directory_repository.dart';
import 'package:y300/features/tags/domain/models/forum_tag_directory_models.dart';
import 'package:y300/features/tags/domain/repositories/forum_tag_directory_repository.dart';

import '../../../support/data_source_contracts/forum_tag_directory_repository_contract_suite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  runForumTagDirectoryRepositoryContractSuite(
    () => ForumTagDirectoryRepositoryContractDriver(
      name: 'contract fake',
      createRepository: _scenarioRepository,
    ),
  );

  group('DiscuzForumTagDirectoryRepository', () {
    test('uses desktop tag endpoint and preserves page parameters', () async {
      final adapter = _HtmlAdapter(_HtmlScenario.fixture);
      final repository = _buildRepository(adapter);

      final result = await repository.load(
        const ForumTagDirectoryQuery(tagId: '21920', page: 2),
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.requestedUris, hasLength(1));
      expect(adapter.requestedUris.single.path, '/misc.php');
      expect(adapter.requestedUris.single.queryParameters, {
        'mod': 'tag',
        'id': '21920',
        'type': 'thread',
        'page': '2',
      });
    });

    test('invalid query does not make a network request', () async {
      final adapter = _HtmlAdapter(_HtmlScenario.fixture);
      final repository = _buildRepository(adapter);

      final result = await repository.load(
        const ForumTagDirectoryQuery(tagId: ' ', page: 0),
      );

      expect(result.failureOrNull!.kind, DataReadFailureKind.business);
      expect(adapter.requestedUris, isEmpty);
    });

    test(
      'cacheFirst and networkFirst each perform one uncached read',
      () async {
        final adapter = _HtmlAdapter(_HtmlScenario.fixture);
        final repository = _buildRepository(adapter);

        await repository.load(const ForumTagDirectoryQuery(tagId: '21920'));
        await repository.load(
          const ForumTagDirectoryQuery(tagId: '21920'),
          cachePolicy: CacheLoadPolicy.networkFirst,
        );

        expect(adapter.requestedUris, hasLength(2));
      },
    );

    test('maps timeout, cancellation and server failures', () async {
      for (final entry in <(_HtmlScenario, DataReadFailureKind)>[
        (_HtmlScenario.timeout, DataReadFailureKind.timeout),
        (_HtmlScenario.cancelled, DataReadFailureKind.cancelled),
        (_HtmlScenario.server, DataReadFailureKind.server),
      ]) {
        final result = await _buildRepository(
          _HtmlAdapter(entry.$1),
        ).load(const ForumTagDirectoryQuery(tagId: '21920'));
        expect(result.failureOrNull!.kind, entry.$2);
      }
    });

    test('does not leak source HTML in parse diagnostics', () async {
      const marker = 'secret-source-html-marker';
      final adapter = _HtmlAdapter(_HtmlScenario.parseFailure, marker: marker);
      final result = await _buildRepository(
        adapter,
      ).load(const ForumTagDirectoryQuery(tagId: '21920'));

      expect(result.failureOrNull!.kind, DataReadFailureKind.parse);
      expect(result.failureOrNull!.diagnosticMessage, isNot(contains(marker)));
    });
  });
}

ForumTagDirectoryRepository _scenarioRepository(
  ForumTagDirectoryContractScenario scenario,
) {
  return _FakeRepository(scenario);
}

final class _FakeRepository implements ForumTagDirectoryRepository {
  _FakeRepository(this.scenario);

  final ForumTagDirectoryContractScenario scenario;

  @override
  ForumTagDirectorySourceCapabilities get capabilities =>
      ForumTagDirectorySourceCapabilities(
        values: DataCapabilitySet<ForumTagDirectoryCapability>.supported(
          ForumTagDirectoryCapability.values,
        ),
        paginationPrecision: PaginationPrecision.exact,
      );

  @override
  Future<
    DataReadResult<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>
  >
  load(
    ForumTagDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    switch (scenario) {
      case ForumTagDirectoryContractScenario.invalidQuery:
        return const DataReadFailure(
          kind: DataReadFailureKind.business,
          code: 'invalid_query',
          diagnosticMessage: 'invalid query',
        );
      case ForumTagDirectoryContractScenario.parseFailure:
        return const DataReadFailure(
          kind: DataReadFailureKind.parse,
          code: 'parse_failure',
          diagnosticMessage: 'parse failure',
        );
      case ForumTagDirectoryContractScenario.networkFailure:
        return const DataReadFailure(
          kind: DataReadFailureKind.network,
          code: 'network_failure',
          diagnosticMessage: 'network failure',
        );
      case ForumTagDirectoryContractScenario.empty:
      case ForumTagDirectoryContractScenario.populated:
        final topics = scenario == ForumTagDirectoryContractScenario.empty
            ? const <ForumTagTopicSummary>[]
            : const <ForumTagTopicSummary>[
                ForumTagTopicSummary(tid: '1', title: 'first'),
                ForumTagTopicSummary(tid: '2', title: 'second'),
              ];
        final capabilities = ForumTagDirectoryReadCapabilities(
          values: DataCapabilitySet<ForumTagDirectoryCapability>.supported(
            ForumTagDirectoryCapability.values,
          ),
          paginationPrecision: PaginationPrecision.exact,
        );
        return DataReadSuccess(
          data: ForumTagDirectoryData(
            tag: const ForumTagIdentity(id: '21920', name: 'tag'),
            topics: topics,
            pagination: const ForumTagPagination(
              currentPage: 1,
              totalPages: 1,
              hasPrevious: false,
              hasNext: false,
            ),
          ),
          capabilities: capabilities,
          metadata: const DataReadMetadata.network(),
        );
    }
  }
}

DiscuzForumTagDirectoryRepository _buildRepository(_HtmlAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  final gateway = YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: dio,
    enableLog: false,
  );
  return DiscuzForumTagDirectoryRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
  );
}

enum _HtmlScenario { fixture, timeout, cancelled, server, parseFailure }

final class _HtmlAdapter implements HttpClientAdapter {
  _HtmlAdapter(this.scenario, {this.marker});

  final _HtmlScenario scenario;
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
      case _HtmlScenario.timeout:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      case _HtmlScenario.cancelled:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        );
      case _HtmlScenario.server:
        return ResponseBody.fromString('server failure', 503);
      case _HtmlScenario.parseFailure:
        return ResponseBody.fromString(
          '<html>$marker<div class="bm tl"></div></html>',
          200,
        );
      case _HtmlScenario.fixture:
        return ResponseBody.fromString(
          File('docs/html/帖子详细页/tag页样例.html').readAsStringSync(),
          200,
        );
    }
  }
}
