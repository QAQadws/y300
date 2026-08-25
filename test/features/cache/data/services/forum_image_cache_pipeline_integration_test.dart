import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/core/network/yamibo_forum_client_host_adapters.dart';
import 'package:y300/features/cache/data/providers/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/data/services/default_image_cache_service.dart';
import 'package:y300/features/cache/data/services/image_cache_diagnostic_recorder.dart';
import 'package:y300/features/cache/data/services/image_cache_manager_factory.dart';
import 'package:y300/features/cache/data/services/y300_forum_resource_file_service.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory cacheRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    cacheRoot = await Directory.systemTemp.createTemp(
      'y300_forum_image_pipeline_',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => switch (call.method) {
        'getApplicationSupportDirectory' => cacheRoot.path,
        _ => null,
      },
    );
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      null,
    );
    if (await cacheRoot.exists()) {
      await cacheRoot.delete(recursive: true);
    }
  });

  test('chunked image response is persisted and decodes end to end', () async {
    final bytes = await _pngBytes(width: 7, height: 5);
    final adapter = _PipelineHttpAdapter(<_PipelineResponse>[
      _PipelineResponse.chunked(bytes, contentType: 'image/png', chunkSize: 11),
    ]);
    final harness = await _buildHarness(cacheRoot, adapter);
    addTearDown(harness.dispose);

    final first = await harness.service.ensureCached(
      _request(cacheKey: 'pipeline-normal'),
    );
    final dimensions = await _decodeDimensions(File(first.localPath!));
    final second = await harness.service.ensureCached(
      _request(cacheKey: 'pipeline-normal'),
    );

    expect(first.success, isTrue);
    expect(first.bytes, bytes.length);
    expect(dimensions, (width: 7, height: 5));
    expect(second.success, isTrue);
    expect(second.fromCache, isTrue);
    expect(adapter.fetchCount, 1);
  });

  test('image signature repairs a misleading dynamic endpoint MIME', () async {
    final bytes = await _pngBytes(width: 3, height: 2);
    final adapter = _PipelineHttpAdapter(<_PipelineResponse>[
      _PipelineResponse.chunked(
        bytes,
        contentType: 'text/html; charset=utf-8',
        chunkSize: 9,
      ),
    ]);
    final harness = await _buildHarness(cacheRoot, adapter);
    addTearDown(harness.dispose);

    final result = await harness.service.ensureCached(
      _request(
        cacheKey: 'pipeline-dynamic-mime',
        sourceUrl:
            'https://bbs.yamibo.com/forum.php?mod=image&aid=123&size=300x300',
      ),
    );

    expect(result.success, isTrue);
    expect(await _decodeDimensions(File(result.localPath!)), (
      width: 3,
      height: 2,
    ));
    expect(p.extension(result.localPath!), '.png');
    expect(adapter.fetchCount, 1);
  });

  test('partial stream does not commit metadata and logs no secrets', () async {
    final bytes = await _pngBytes(width: 8, height: 6);
    final adapter = _PipelineHttpAdapter(<_PipelineResponse>[
      _PipelineResponse.failing(
        bytes,
        contentType: 'image/png',
        failAfter: bytes.length ~/ 2,
      ),
    ]);
    final output = _MemoryLogOutput();
    final recorder = _CapturingDiagnosticRecorder(
      LoggerImageCacheDiagnosticRecorder(
        Logger(
          printer: SimplePrinter(colors: false),
          output: output,
          filter: ProductionFilter(),
          level: Level.trace,
        ),
      ),
    );
    final cookieStore = CookieStore();
    await cookieStore.saveCookies(Uri.parse(_siteOrigin), <String, String>{
      'auth': 'secret-cookie-value',
    });
    final harness = await _buildHarness(
      cacheRoot,
      adapter,
      cookieStore: cookieStore,
      diagnosticRecorder: recorder,
    );
    addTearDown(harness.dispose);
    const cacheKey = 'private-cache-key';

    final result = await harness.service.ensureCached(
      _request(
        cacheKey: cacheKey,
        sourceUrl:
            'https://bbs.yamibo.com/data/attachment/private.png?token=url-secret',
        referer:
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=referer-secret',
      ),
    );

    expect(result.success, isFalse);
    expect(await harness.manager.getFileFromCache(cacheKey), isNull);
    expect(harness.repository.records[cacheKey], isNull);
    expect(recorder.events, hasLength(1));
    expect(recorder.events.single.stage, ImageCacheDiagnosticStage.download);
    expect(recorder.events.single.reasonCode, isNotEmpty);
    final diagnosticText = output.lines.join('\n');
    expect(diagnosticText, contains('[ImageCache][failure]'));
    expect(diagnosticText, isNot(contains('secret-cookie-value')));
    expect(diagnosticText, isNot(contains('referer-secret')));
    expect(diagnosticText, isNot(contains('url-secret')));
    expect(diagnosticText, isNot(contains(cacheKey)));
    expect(diagnosticText, isNot(contains('fixture-thread')));
    expect(diagnosticText, isNot(contains(cacheRoot.path)));
    expect(diagnosticText, isNot(contains('secret-response-body')));
    expect(diagnosticText, isNot(contains('waf-secret-token')));
  });
}

const _siteOrigin = 'https://bbs.yamibo.com';

ImageCacheRequest _request({
  required String cacheKey,
  String sourceUrl = 'https://bbs.yamibo.com/data/attachment/image.png',
  String referer = 'https://bbs.yamibo.com/thread-1-1-1.html',
}) {
  return ImageCacheRequest(
    cacheKey: cacheKey,
    sourceUrl: sourceUrl,
    referer: referer,
    ownerType: ImageCacheOwnerType.thread,
    ownerId: 'fixture-thread',
    role: ImageCacheRole.threadInline,
  );
}

Future<_PipelineHarness> _buildHarness(
  Directory cacheRoot,
  _PipelineHttpAdapter adapter, {
  CookieStore? cookieStore,
  ImageCacheDiagnosticRecorder diagnosticRecorder =
      const NoopImageCacheDiagnosticRecorder(),
}) async {
  final dio = Dio(
    BaseOptions(
      baseUrl: _siteOrigin,
      validateStatus: (status) => status != null,
    ),
  )..httpClientAdapter = adapter;
  final gateway = YamiboHttpGateway(
    cookieStore: cookieStore ?? CookieStore(),
    logger: Logger(level: Level.off),
    dio: dio,
    enableLog: false,
    siteUri: Uri.parse(_siteOrigin),
  );
  final resourceClient = Y300ForumClientNetworkAdapter(
    gateway: gateway,
    apiOrigin: Uri.parse('$_siteOrigin/api/mobile/index.php'),
    siteOrigin: Uri.parse(_siteOrigin),
    resourceUserAgent: 'Y300 integration test',
  );
  final manager = ImageCacheManagerFactory(
    fileService: Y300ForumResourceFileService(
      client: resourceClient,
      siteOrigin: Uri.parse(_siteOrigin),
    ),
  ).create(cacheDirectoryPath: cacheRoot.path);
  await manager.emptyCache();
  final repository = _MemoryImageCacheRepository();
  return _PipelineHarness(
    manager: manager,
    repository: repository,
    service: DefaultImageCacheService(
      repository: repository,
      cacheManagerFuture: Future<BaseCacheManager>.value(manager),
      directoryResolver: const ImageCacheDirectoryResolver(),
      diagnosticRecorder: diagnosticRecorder,
    ),
  );
}

final class _PipelineHarness {
  const _PipelineHarness({
    required this.manager,
    required this.repository,
    required this.service,
  });

  final BaseCacheManager manager;
  final _MemoryImageCacheRepository repository;
  final DefaultImageCacheService service;

  Future<void> dispose() async {
    await manager.emptyCache();
    await manager.dispose();
  }
}

final class _PipelineResponse {
  const _PipelineResponse._({
    required this.bytes,
    required this.contentType,
    required this.chunkSize,
    this.failAfter,
  });

  factory _PipelineResponse.chunked(
    Uint8List bytes, {
    required String contentType,
    required int chunkSize,
  }) => _PipelineResponse._(
    bytes: bytes,
    contentType: contentType,
    chunkSize: chunkSize,
  );

  factory _PipelineResponse.failing(
    Uint8List bytes, {
    required String contentType,
    required int failAfter,
  }) => _PipelineResponse._(
    bytes: bytes,
    contentType: contentType,
    chunkSize: failAfter,
    failAfter: failAfter,
  );

  final Uint8List bytes;
  final String contentType;
  final int chunkSize;
  final int? failAfter;

  Stream<Uint8List> openStream() async* {
    final failureOffset = failAfter;
    final limit = failureOffset ?? bytes.length;
    for (var offset = 0; offset < limit; offset += chunkSize) {
      final end = offset + chunkSize < limit ? offset + chunkSize : limit;
      yield Uint8List.sublistView(bytes, offset, end);
    }
    if (failureOffset != null) {
      throw StateError('secret-response-body waf-secret-token');
    }
  }
}

final class _PipelineHttpAdapter implements HttpClientAdapter {
  _PipelineHttpAdapter(this._responses);

  final List<_PipelineResponse> _responses;
  int fetchCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = fetchCount++;
    if (index >= _responses.length) {
      throw StateError('No scripted response for request $index');
    }
    final response = _responses[index];
    return ResponseBody(
      response.openStream(),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[response.contentType],
        Headers.contentLengthHeader: <String>[response.bytes.length.toString()],
      },
    );
  }
}

final class _CapturingDiagnosticRecorder
    implements ImageCacheDiagnosticRecorder {
  _CapturingDiagnosticRecorder(this.delegate);

  final ImageCacheDiagnosticRecorder delegate;
  final List<ImageCacheFailureDiagnostic> events =
      <ImageCacheFailureDiagnostic>[];

  @override
  void recordFailure(ImageCacheFailureDiagnostic event) {
    events.add(event);
    delegate.recordFailure(event);
  }
}

final class _MemoryLogOutput extends LogOutput {
  final List<String> lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

final class _MemoryImageCacheRepository implements ImageCacheRepository {
  final Map<String, CachedImageRecord> records = <String, CachedImageRecord>{};

  @override
  Future<int> calculateUsageBytes({required bool includeProtected}) async => 0;

  @override
  Future<List<ImageCacheUsageGroup>> calculateUsageGroups() async =>
      const <ImageCacheUsageGroup>[];

  @override
  Future<void> deleteByKey(String cacheKey) async {
    records.remove(cacheKey);
  }

  @override
  Future<CachedImageRecord?> getByKey(String cacheKey) async =>
      records[cacheKey];

  @override
  Future<List<CachedImageRecord>> listByOwner({
    required String ownerType,
    required String ownerId,
  }) async => records.values
      .where(
        (record) => record.ownerType == ownerType && record.ownerId == ownerId,
      )
      .toList(growable: false);

  @override
  Future<List<CachedImageRecord>> listProtectedCovers() async =>
      const <CachedImageRecord>[];

  @override
  Future<List<CachedImageRecord>> listUnprotectedByAccessTime() async =>
      const <CachedImageRecord>[];

  @override
  Future<List<CachedImageRecord>> listUnprotectedByRoles({
    required List<String> roles,
  }) async => const <CachedImageRecord>[];

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {}

  @override
  Future<void> updateDimensions({
    required String cacheKey,
    required int width,
    required int height,
    required DateTime updatedAt,
  }) async {}

  @override
  Future<void> upsert(CachedImageRecord record) async {
    records[record.cacheKey] = record;
  }
}

Future<Uint8List> _pngBytes({required int width, required int height}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('Failed to create PNG fixture.');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<({int width, int height})> _decodeDimensions(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final frame = await codec.getNextFrame();
  final dimensions = (width: frame.image.width, height: frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return dimensions;
}
