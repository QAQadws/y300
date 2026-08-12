import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';

void main() {
  late io.Directory root;
  late _FakeDownloader downloader;
  late LocalLibraryCoverStore store;

  setUp(() async {
    root = await io.Directory.systemTemp.createTemp('y300-cover-store-');
    downloader = _FakeDownloader();
    store = LocalLibraryCoverStore(
      rootPath: Future<String>.value(root.path),
      downloader: downloader,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'path is deterministic and revision changes only the filename',
    () async {
      const first = LibraryCoverAssetRef(
        assetId: '漫画/作品/source',
        revision: 1,
        kind: LibraryCoverAssetKind.source,
      );
      final second = first.copyWith(revision: 2);

      final firstPath = await store.fileFor(first);
      final repeated = await store.fileFor(first);
      final secondPath = await store.fileFor(second);

      expect(repeated.path, firstPath.path);
      expect(secondPath.parent.path, firstPath.parent.path);
      expect(secondPath.path, isNot(firstPath.path));
    },
  );

  test('same asset revision downloads with a single flight', () async {
    const asset = LibraryCoverAssetRef(
      assetId: 'comic/1/source',
      revision: 1,
      kind: LibraryCoverAssetKind.source,
      sourceUrl: 'https://img.test/1.jpg',
    );

    final results = await Future.wait(<Future<io.File>>[
      store.ensureAvailable(asset),
      store.ensureAvailable(asset),
      store.ensureAvailable(asset),
    ]);

    expect(downloader.calls, 1);
    expect(results.map((file) => file.path).toSet(), hasLength(1));
    expect(await io.File('${results.first.path}.part').exists(), isFalse);
  });

  test('network cover downloads are strictly serial', () async {
    final adapter = _ControlledDownloadAdapter();
    final downloader = DioLibraryCoverDownloader(
      headerBuilder: const _StaticHeaderBuilder(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    final firstPath = '${root.path}/first.img';
    final secondPath = '${root.path}/second.img';

    final first = downloader.download(
      url: 'https://img.test/first.jpg',
      targetPath: firstPath,
    );
    await adapter.firstStarted;
    final second = downloader.download(
      url: 'https://img.test/second.jpg',
      targetPath: secondPath,
    );
    await Future<void>.delayed(Duration.zero);

    expect(adapter.callCount, 1);
    expect(adapter.maxActive, 1);

    adapter.release(0);
    await first;
    await adapter.secondStarted;
    expect(adapter.callCount, 2);
    expect(adapter.maxActive, 1);

    adapter.release(1);
    await second;
    expect(await io.File(firstPath).readAsBytes(), <int>[1]);
    expect(await io.File(secondPath).readAsBytes(), <int>[2]);
  });

  test(
    'staged revision preserves old file until activation is committed',
    () async {
      const first = LibraryCoverAssetRef(
        assetId: 'novel/1/custom',
        revision: 1,
        kind: LibraryCoverAssetKind.custom,
      );
      final second = first.copyWith(revision: 2);
      final source = io.File('${root.path}/picked.jpg');
      await source.writeAsBytes(<int>[0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]);

      await store.installLocalFile(asset: first, sourcePath: source.path);
      final oldFile = await store.fileFor(first);
      expect(await oldFile.exists(), isTrue);

      await store.installLocalFile(asset: second, sourcePath: source.path);

      expect(await (await store.fileFor(second)).exists(), isTrue);
      expect(await oldFile.exists(), isTrue);

      await store.deleteOlderRevisions(second);

      expect(await oldFile.exists(), isFalse);
    },
  );
}

class _FakeDownloader implements LibraryCoverDownloader {
  int calls = 0;

  @override
  Future<void> download({
    required String url,
    required String targetPath,
  }) async {
    calls += 1;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await io.File(targetPath).writeAsBytes(<int>[0xff, 0xd8, 1, 0xff, 0xd9]);
  }
}

class _StaticHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
  }
}

class _ControlledDownloadAdapter implements HttpClientAdapter {
  final List<Completer<void>> _releases = <Completer<void>>[
    Completer<void>(),
    Completer<void>(),
  ];
  final Completer<void> _firstStarted = Completer<void>();
  final Completer<void> _secondStarted = Completer<void>();
  int callCount = 0;
  int _active = 0;
  int maxActive = 0;

  Future<void> get firstStarted => _firstStarted.future;

  Future<void> get secondStarted => _secondStarted.future;

  void release(int index) => _releases[index].complete();

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = callCount;
    callCount += 1;
    _active += 1;
    if (_active > maxActive) {
      maxActive = _active;
    }
    if (index == 0) {
      _firstStarted.complete();
    } else if (index == 1) {
      _secondStarted.complete();
    }
    await _releases[index].future;
    _active -= 1;
    return ResponseBody.fromBytes(<int>[index + 1], 200);
  }
}
