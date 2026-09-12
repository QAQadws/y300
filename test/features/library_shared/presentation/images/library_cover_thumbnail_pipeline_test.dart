import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/data/services/library_cover_thumbnail_cache.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_decode_policy.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_image_provider.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_thumbnail_writer.dart';

import '../../test_support/cover_image_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late io.Directory root;
  late _ObservedThumbnailCache cache;
  late LibraryCoverThumbnailWriter writer;
  late LibraryCoverDecodeScheduler scheduler;
  late _Store store;
  late List<void Function()> frames;
  const asset = LibraryCoverAssetRef(
    assetId: 'novel/fixture/source',
    revision: 1,
    kind: LibraryCoverAssetKind.source,
    sourceUrl: 'https://example.test/cover',
  );
  const target = LibraryCoverDecodeTarget.thumbnail(widthPx: 32, heightPx: 48);
  final key = LibraryCoverThumbnailKey(asset: asset, width: 32, height: 48);

  setUp(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    root = await io.Directory.systemTemp.createTemp('cover-pipeline-test-');
    cache = _ObservedThumbnailCache(
      rootPath: () async => '${root.path}/derived',
    );
    scheduler = LibraryCoverDecodeScheduler(maxConcurrent: 2);
    frames = <void Function()>[];
    writer = LibraryCoverThumbnailWriter(
      cache: cache,
      scheduler: scheduler,
      afterFrame: frames.add,
    );
    final original = io.File('${root.path}/original.png');
    await original.writeAsBytes(await _png());
    store = _Store(original);
  });
  tearDown(() async {
    writer.dispose();
    await _until(() => writer.retainedBytes == 0);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await cache.dispose();
    await root.delete(recursive: true);
  });

  LibraryCoverImageProvider provider({
    LibraryCoverDecodeTarget size = target,
  }) => LibraryCoverImageProvider(
    asset: asset,
    decodeTarget: size,
    store: store,
    scheduler: scheduler,
    thumbnails: cache,
    thumbnailWriter: writer,
  );

  test(
    'first frame does not wait for encoding; restart reads only the derived file',
    () async {
      final first = _ImageConsumer(provider());
      addTearDown(first.dispose);
      final info = await first.frame;
      expect(info.image.width, 32);
      expect(info.image.height, 48);
      expect(store.reads, 1);
      expect(await cache.lookup(key), isNull);
      expect(writer.pendingCount, 1);
      frames.removeAt(0)();
      await _until(() => writer.retainedBytes == 0);
      expect(await cache.lookup(key), isNotNull);

      first.dispose();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      writer.dispose();
      await cache.dispose();
      cache = _ObservedThumbnailCache(
        rootPath: () async => '${root.path}/derived',
      );
      writer = LibraryCoverThumbnailWriter(
        cache: cache,
        scheduler: scheduler,
        afterFrame: frames.add,
      );
      store.forbidReads = true;
      final restarted = _ImageConsumer(provider());
      addTearDown(restarted.dispose);
      final thumbnail = await restarted.frame;
      expect(thumbnail.image.width, 32);
      expect(store.reads, 1);
      expect(writer.pendingCount, 0);
      // The fully transparent half stays transparent after PNG encoding.
      final pixels = await thumbnail.image.toByteData();
      expect(pixels!.getUint8(3), 0);

      await cache.clearRegular();
      final lookupsBeforeMemoryHit = cache.lookups;
      final memoryHit = _ImageConsumer(provider());
      addTearDown(memoryHit.dispose);
      expect((await memoryHit.frame).image.width, 32);
      expect(store.reads, 1);
      expect(cache.lookups, lookupsBeforeMemoryHit);
    },
  );

  test(
    'broken derivative falls back without invalidating a valid original',
    () async {
      await cache.write(
        key: key,
        ticket: cache.ticket(key),
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final consumer = _ImageConsumer(provider());
      addTearDown(consumer.dispose);
      expect((await consumer.frame).image.width, 32);
      expect(store.reads, 1);
      expect(store.invalidations, 0);
      expect(writer.pendingCount, 1);
    },
  );

  test('empty derivative is replaced and the next cold load uses it', () async {
    await cache.write(key: key, ticket: cache.ticket(key), bytes: await _png());
    final file = (await cache.lookup(key))!;
    await file.writeAsBytes(<int>[]);

    final first = _ImageConsumer(provider());
    addTearDown(first.dispose);
    expect((await first.frame).image.width, 32);
    expect(store.reads, 1);
    expect(store.invalidations, 0);
    expect(writer.pendingCount, 1);
    frames.removeAt(0)();
    await _until(() => writer.retainedBytes == 0);
    expect(await file.length(), greaterThan(0));

    first.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    store.forbidReads = true;
    final next = _ImageConsumer(provider());
    addTearDown(next.dispose);
    expect((await next.frame).image.width, 32);
    expect(store.reads, 1);
  });

  test(
    'clear during corrupt thumbnail removal cannot renew the ticket',
    () async {
      await cache.write(
        key: key,
        ticket: cache.ticket(key),
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final release = Completer<void>();
      cache.removalGate = release.future;
      final consumer = _ImageConsumer(provider());
      addTearDown(consumer.dispose);
      await _until(() => cache.removalStarted);
      await cache.clearRegular();
      release.complete();

      expect((await consumer.frame).image.width, 32);
      expect(writer.pendingCount, 0);
      expect(writer.retainedBytes, 0);
      expect(await cache.lookup(key), isNull);
      expect(store.invalidations, 0);
    },
  );

  for (final derivative in <bool>[true, false]) {
    for (final invalidate in <String>['clear', 'purge', 'none']) {
      test('${derivative ? 'thumbnail' : 'original'} failure after $invalidate '
          'preserves the request write generation', () async {
        if (derivative) {
          await cache.write(
            key: key,
            ticket: cache.ticket(key),
            bytes: await _png(),
          );
        }
        store.onInvalidate = () => cache.invalidateAsset(asset.assetId);
        final release = Completer<void>();
        _FrameGateCodec? failedCodec;
        Future<ui.Codec> decode(
          ui.ImmutableBuffer buffer, {
          ui.TargetImageSizeCallback? getTargetSize,
        }) async {
          final codec = await PaintingBinding.instance
              .instantiateImageCodecWithSize(
                buffer,
                getTargetSize: getTargetSize,
              );
          if (failedCodec != null) return codec;
          return failedCodec = _FrameGateCodec(
            codec,
            release.future,
            failure: StateError('fixture first frame failure'),
          );
        }

        final consumer = _ImageConsumer(provider(), decode: decode);
        addTearDown(consumer.dispose);
        await _until(() => failedCodec?.requested == true);
        if (invalidate == 'clear') {
          await cache.clearRegular();
        } else if (invalidate == 'purge') {
          await cache.invalidateAsset(asset.assetId);
        }
        release.complete();

        expect((await consumer.frame).image.width, 32);
        expect(failedCodec!.disposed, isTrue);
        expect(store.reads, derivative ? 1 : 2);
        expect(store.invalidations, derivative ? 0 : 1);
        expect(writer.pendingCount, invalidate == 'none' ? 1 : 0);
        for (final callback in frames.toList()) {
          callback();
        }
        await _until(() => writer.retainedBytes == 0);
        expect(
          await cache.lookup(key),
          invalidate == 'none' ? isNotNull : isNull,
        );
      });
    }
  }

  test(
    'disposed consumers do not encode or retain a pending cloned image',
    () async {
      var encodes = 0;
      writer.dispose();
      writer = LibraryCoverThumbnailWriter(
        cache: cache,
        scheduler: scheduler,
        afterFrame: frames.add,
        encoder: (_) async {
          encodes++;
          return null;
        },
      );
      final consumer = _ImageConsumer(provider());
      await consumer.frame;
      expect(writer.retainedBytes, greaterThan(0));
      consumer.dispose();
      expect(writer.retainedBytes, 0);
      frames.removeAt(0)();
      await _until(() => writer.retainedBytes == 0);
      expect(encodes, 0);
    },
  );

  test('cache clear during encoding cannot commit a late thumbnail', () async {
    final encoding = Completer<Uint8List?>();
    var started = false;
    writer.dispose();
    writer = LibraryCoverThumbnailWriter(
      cache: cache,
      scheduler: scheduler,
      afterFrame: frames.add,
      encoder: (_) {
        started = true;
        return encoding.future;
      },
    );
    final consumer = _ImageConsumer(provider());
    addTearDown(consumer.dispose);
    expect((await consumer.frame).image.width, 32);
    frames.removeAt(0)();
    await _until(() => started);
    await cache.clearRegular();
    encoding.complete(Uint8List.fromList(<int>[1, 2, 3]));
    await _until(() => writer.retainedBytes == 0);
    expect(await cache.lookup(key), isNull);
  });

  test(
    'same provider key shares a pending load, not separate codecs',
    () async {
      final first = _ImageConsumer(provider());
      final second = _ImageConsumer(provider());
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await Future.wait(<Future<ImageInfo>>[first.frame, second.frame]);
      expect(store.reads, 1);
      expect(writer.pendingCount, 1);
    },
  );

  for (final fixture in <String, Uint8List Function()>{
    'JPEG': coverJpegFixture,
    'WebP': coverWebpFixture,
  }.entries) {
    test(
      '${fixture.key} sampled display frame becomes an uncropped PNG',
      () async {
        await store.file.writeAsBytes(fixture.value());
        final consumer = _ImageConsumer(provider());
        addTearDown(consumer.dispose);
        final first = await consumer.frame;
        expect(first.image.width, 32);
        expect(first.image.height, 48);
        frames.removeAt(0)();
        await _until(() => writer.retainedBytes == 0);
        final file = (await cache.lookup(key))!;
        final codec = await ui.instantiateImageCodec(await file.readAsBytes());
        final saved = await codec.getNextFrame();
        expect(saved.image.width, first.image.width);
        expect(saved.image.height, first.image.height);
        expect(
          (await saved.image.toByteData())!.buffer.asUint8List(),
          (await first.image.toByteData())!.buffer.asUint8List(),
        );
        saved.image.dispose();
        codec.dispose();
        expect(store.reads, 1);
      },
    );
  }

  testWidgets('animated covers are not frozen into static thumbnails', (
    tester,
  ) async {
    await tester.runAsync(
      () => store.file.writeAsBytes(coverAnimatedGifFixture()),
    );
    final consumer = _ImageConsumer(provider());
    addTearDown(consumer.dispose);
    for (var i = 0; i < 60 && !consumer.hasFrame; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(consumer.hasFrame, isTrue);
    expect(writer.pendingCount, 0);
    expect(writer.retainedBytes, 0);
    consumer.dispose();
    await tester.pump();
  });

  test(
    'original and non-downsampled views never generate thumbnails',
    () async {
      for (final size in <LibraryCoverDecodeTarget>[
        const LibraryCoverDecodeTarget.original(),
        const LibraryCoverDecodeTarget.thumbnail(widthPx: 960, heightPx: 1440),
      ]) {
        final consumer = _ImageConsumer(provider(size: size));
        addTearDown(consumer.dispose);
        expect((await consumer.frame).image.width, 96);
        expect(writer.pendingCount, 0);
      }
    },
  );

  test('encoding failure leaves the first frame and original intact', () async {
    writer.dispose();
    writer = LibraryCoverThumbnailWriter(
      cache: cache,
      scheduler: scheduler,
      afterFrame: frames.add,
      encoder: (_) => Future<Uint8List?>.error(StateError('fixture failure')),
    );
    final consumer = _ImageConsumer(provider());
    addTearDown(consumer.dispose);
    final first = await consumer.frame;
    frames.removeAt(0)();
    await _until(() => writer.retainedBytes == 0);
    expect(first.image.width, 32);
    expect(await cache.lookup(key), isNull);
    expect(await store.file.exists(), isTrue);
    expect(store.invalidations, 0);
  });

  test(
    'decode slot is held until getNextFrame finishes, not just codec creation',
    () async {
      scheduler = LibraryCoverDecodeScheduler(maxConcurrent: 1);
      final release = Completer<void>();
      var codecCreations = 0;
      final codecs = <_FrameGateCodec>[];
      Future<ui.Codec> decode(
        ui.ImmutableBuffer buffer, {
        ui.TargetImageSizeCallback? getTargetSize,
      }) async {
        codecCreations++;
        final codec = _FrameGateCodec(
          await PaintingBinding.instance.instantiateImageCodecWithSize(
            buffer,
            getTargetSize: getTargetSize,
          ),
          release.future,
        );
        codecs.add(codec);
        return codec;
      }

      final first = _ImageConsumer(provider(), decode: decode);
      final second = _ImageConsumer(provider(), decode: decode);
      await _until(() => codecs.isNotEmpty && codecs.first.requested);
      expect(codecCreations, 1);
      expect(scheduler.activeCount, 1);
      expect(scheduler.pendingCount, 1);
      release.complete();
      await Future.wait([first.frame, second.frame]);
      expect(codecCreations, 2);
      expect(identical(codecs.first, codecs.last), isFalse);
      first.dispose();
      second.dispose();
      expect(codecs.every((codec) => codec.disposed), isTrue);
      expect(scheduler.activeCount, 0);
    },
  );

  test(
    'non-sRGB frames and oversized handles are skipped before clone',
    () async {
      for (final color in [
        ui.ColorSpace.displayP3,
        ui.ColorSpace.extendedSRGB,
      ]) {
        writer.enqueue(
          key: key,
          ticket: cache.ticket(key),
          image: _NonSrgbImage(color),
          isActive: () => true,
        );
      }
      expect(writer.retainedBytes, 0);
      final codec = await ui.instantiateImageCodec(await _png());
      final frame = await codec.getNextFrame();
      writer.dispose();
      writer = LibraryCoverThumbnailWriter(
        cache: cache,
        scheduler: scheduler,
        maxRetainedBytes: 1,
        afterFrame: frames.add,
      );
      writer.enqueue(
        key: key,
        ticket: cache.ticket(key),
        image: frame.image,
        isActive: () => true,
      );
      expect(writer.pendingCount, 0);
      expect(writer.retainedBytes, 0);
      frame.image.dispose();
      codec.dispose();
    },
  );

  test(
    'clear and revision change release queued handles before a frame runs',
    () async {
      final consumer = _ImageConsumer(provider());
      addTearDown(consumer.dispose);
      await consumer.frame;
      expect(writer.pendingCount, 1);
      await cache.invalidateAsset(asset.assetId, retainRevision: 2);
      expect(writer.pendingCount, 0);
      expect(writer.retainedBytes, 0);
      await cache.clearRegular();
      frames.removeAt(0)();
      expect(await cache.lookup(key), isNull);
    },
  );

  test(
    'writer bounds handles and queued keys without changing caller ownership',
    () async {
      final codec = await ui.instantiateImageCodec(await _png());
      final frame = await codec.getNextFrame();
      final bytes = frame.image.width * frame.image.height * 4;
      writer.dispose();
      writer = LibraryCoverThumbnailWriter(
        cache: cache,
        scheduler: scheduler,
        afterFrame: frames.add,
        maxPending: 1,
        maxRetainedBytes: bytes,
      );
      final second = LibraryCoverThumbnailKey(
        asset: asset.copyWith(revision: 2),
        width: 32,
        height: 48,
      );
      writer.enqueue(
        key: key,
        ticket: cache.ticket(key),
        image: frame.image,
        isActive: () => true,
      );
      writer.enqueue(
        key: second,
        ticket: cache.ticket(second),
        image: frame.image,
        isActive: () => true,
      );
      expect(writer.pendingCount, 1);
      expect(writer.retainedBytes, bytes);
      writer.dispose();
      expect(writer.retainedBytes, 0);
      expect(frame.image.width, 96);
      frame.image.dispose();
      codec.dispose();
    },
  );
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue);
}

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(48, 0, 48, 144),
    ui.Paint()..color = const ui.Color(0xff803355),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 144);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _ImageConsumer {
  _ImageConsumer(
    LibraryCoverImageProvider provider, {
    ImageDecoderCallback? decode,
  }) {
    stream = decode == null
        ? provider.resolve(ImageConfiguration.empty)
        : (ImageStream()
            ..setCompleter(provider.loadImage(provider.cacheKey, decode)));
    listener = ImageStreamListener(
      (info, _) {
        if (_frame.isCompleted) {
          info.dispose();
          return;
        }
        _image = info;
        _frame.complete(info);
      },
      onError: (Object error, StackTrace? stack) =>
          _frame.completeError(error, stack),
    );
    stream.addListener(listener);
  }
  late final ImageStream stream;
  late final ImageStreamListener listener;
  final _frame = Completer<ImageInfo>();
  ImageInfo? _image;
  bool _disposed = false;
  Future<ImageInfo> get frame => _frame.future;
  bool get hasFrame => _frame.isCompleted;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stream.removeListener(listener);
    _image?.dispose();
  }
}

class _ObservedThumbnailCache extends LibraryCoverThumbnailCache {
  _ObservedThumbnailCache({required super.rootPath});

  int lookups = 0;
  bool removalStarted = false;
  Future<void>? removalGate;

  @override
  Future<io.File?> lookup(LibraryCoverThumbnailKey key) {
    lookups++;
    return super.lookup(key);
  }

  @override
  Future<void> remove(LibraryCoverThumbnailKey key) async {
    await super.remove(key);
    removalStarted = true;
    await removalGate;
  }
}

class _Store implements LibraryCoverStore {
  _Store(this.file);
  final io.File file;
  int reads = 0;
  int invalidations = 0;
  bool forbidReads = false;
  Future<void> Function()? onInvalidate;
  @override
  Future<io.File> ensureAvailable(LibraryCoverAssetRef asset) async {
    if (forbidReads) throw StateError('Original must not be opened');
    reads++;
    return file;
  }

  @override
  Future<void> invalidate(LibraryCoverAssetRef asset) async {
    invalidations++;
    await onInvalidate?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FrameGateCodec implements ui.Codec {
  _FrameGateCodec(this.codec, this.release, {this.failure});
  final ui.Codec codec;
  final Future<void> release;
  final Object? failure;
  bool requested = false;
  bool disposed = false;
  @override
  int get frameCount => codec.frameCount;
  @override
  int get repetitionCount => codec.repetitionCount;
  @override
  Future<ui.FrameInfo> getNextFrame() async {
    requested = true;
    await release;
    final error = failure;
    if (error != null) throw error;
    return codec.getNextFrame();
  }

  @override
  void dispose() {
    disposed = true;
    codec.dispose();
  }
}

class _NonSrgbImage implements ui.Image {
  _NonSrgbImage(this.colorSpace);
  @override
  final ui.ColorSpace colorSpace;
  @override
  int get width => 96;
  @override
  int get height => 144;
  @override
  ui.Image clone() =>
      throw StateError('Wide-gamut images must not be cloned for PNG');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
