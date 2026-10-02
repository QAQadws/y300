import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/providers/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/data/services/long_term_image_revalidator.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';

const _request = ImageCacheRequest(
  cacheKey: 'account:42',
  sourceUrl: 'https://forum.example.test/avatar.jpg',
  ownerType: ImageCacheOwnerType.profile,
  ownerId: '42',
  role: ImageCacheRole.avatar,
  retentionClass: ImageRetentionClass.sticky,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Repository repository;
  late _FileService network;
  late LongTermImageRevalidator service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('account_avatar_test');
    repository = _Repository();
    network = _FileService();
    service = LongTermImageRevalidator(
      repository: repository,
      fileService: network,
      directories: _Directories(directory.path),
      mutations: const NoopCacheMutationReporter(),
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    '304 and unchanged bytes preserve the file; changed bytes replace the same URL',
    () async {
      final firstBytes = await _png(const ui.Color(0xffff0000));
      network.response = _Response(firstBytes, eTag: 'one');
      final first = await service.revalidate(_request);
      expect(first.success, isTrue);
      expect(repository.value?.retentionClass, ImageRetentionClass.sticky);
      network.response = _Response(Uint8List(0), statusCode: 304);
      final notModified = await service.revalidate(_request);
      expect(network.headers.last?['If-None-Match'], 'one');
      expect(notModified.localPath, first.localPath);
      expect(notModified.fromCache, isTrue);
      network.response = _Response(firstBytes, eTag: 'two');
      final same = await service.revalidate(_request);
      expect(same.localPath, first.localPath);
      expect(same.fromCache, isTrue);
      expect(repository.value?.eTag, 'two');
      network.response = _Response(
        await _png(const ui.Color(0xff0000ff)),
        eTag: 'three',
      );
      final changed = await service.revalidate(_request);
      expect(changed.success, isTrue);
      expect(changed.localPath, isNot(first.localPath));
      expect(changed.fromCache, isFalse);
      expect(await File(changed.localPath!).exists(), isTrue);
      expect(await File(first.localPath!).exists(), isFalse);
    },
  );

  test(
    'decode, download, storage and cancellation failures retain the old file',
    () async {
      network.response = _Response(await _png(const ui.Color(0xffff0000)));
      final first = await service.revalidate(_request);
      final original = repository.value;
      network.response = _Response(Uint8List.fromList([0, 1, 2]));
      expect((await service.revalidate(_request)).success, isFalse);
      expect(repository.value, same(original));
      network.fail = true;
      expect((await service.revalidate(_request)).success, isFalse);
      network.fail = false;
      network.response = _Response(await _png(const ui.Color(0xff0000ff)));
      repository.failWrites = true;
      expect((await service.revalidate(_request)).success, isFalse);
      expect(repository.value, same(original));
      repository.failWrites = false;
      expect(
        (await service.revalidate(_request, isCurrent: () => false)).success,
        isFalse,
      );
      expect(await File(first.localPath!).exists(), isTrue);
      expect(await directory.list().length, 1);
    },
  );

  test(
    'concurrent refreshes merge and a new owner waits for the cancelled old flight',
    () async {
      final pending = Completer<FileServiceResponse>();
      network.pending = pending.future;
      var current = true;
      final first = service.revalidate(_request, isCurrent: () => current);
      final duplicate = service.revalidate(_request, isCurrent: () => current);
      expect(identical(first, duplicate), isTrue);
      await Future<void>.delayed(Duration.zero);
      current = false;
      final next = service.revalidate(_request);
      network.pending = null;
      network.response = _Response(await _png(const ui.Color(0xff0000ff)));
      pending.complete(_Response(await _png(const ui.Color(0xffff0000))));
      expect((await first).success, isFalse);
      expect((await next).success, isTrue);
      expect(network.headers, hasLength(2));
    },
  );

  test('corrupt on-disk bytes force an unconditional repair', () async {
    final bytes = await _png(const ui.Color(0xffff0000));
    network.response = _Response(bytes, eTag: 'one');
    final first = await service.revalidate(_request);
    await File(first.localPath!).writeAsBytes([1, 2, 3]);
    final repaired = await service.revalidate(_request);
    expect(repaired.success, isTrue);
    expect(network.headers.last?.containsKey('If-None-Match'), isFalse);
    expect(await File(first.localPath!).readAsBytes(), bytes);
  });
}

Future<Uint8List> _png(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(
    recorder,
  ).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

class _Repository extends Fake implements ImageCacheRepository {
  CachedImageRecord? value;
  bool failWrites = false;
  @override
  Future<CachedImageRecord?> getByKey(String key) async => value;
  @override
  Future<void> upsert(CachedImageRecord record) async {
    if (failWrites) throw StateError('synthetic storage failure');
    value = record;
  }
}

class _Directories extends ImageCacheDirectoryResolver {
  _Directories(this.path);
  final String path;
  @override
  Future<String> resolveLongTermDirectory() async => path;
}

class _FileService extends FileService {
  late FileServiceResponse response;
  Future<FileServiceResponse>? pending;
  final List<Map<String, String>?> headers = [];
  bool fail = false;
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    this.headers.add(headers);
    if (fail) throw StateError('synthetic network failure');
    return pending != null ? await pending! : response;
  }
}

class _Response implements FileServiceResponse {
  _Response(this.bytes, {this.statusCode = 200, this.eTag});
  final Uint8List bytes;
  @override
  final int statusCode;
  @override
  final String? eTag;
  @override
  Stream<List<int>> get content => Stream.value(bytes);
  @override
  int? get contentLength => bytes.length;
  @override
  String get fileExtension => 'png';
  @override
  DateTime get validTill => DateTime(2030);
}
