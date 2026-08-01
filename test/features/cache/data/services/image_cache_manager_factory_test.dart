import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/cache/data/services/image_cache_manager_factory.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory cacheRoot;
  late BaseCacheManager manager;

  setUp(() async {
    cacheRoot = await Directory.systemTemp.createTemp(
      'y300_image_cache_manager_',
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => switch (call.method) {
        'getApplicationSupportDirectory' => cacheRoot.path,
        _ => null,
      },
    );
    manager = const ImageCacheManagerFactory().create(
      cacheDirectoryPath: cacheRoot.path,
    );
    await manager.emptyCache();
  });

  tearDown(() async {
    await manager.emptyCache();
    await manager.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProviderChannel,
      null,
    );
    if (await cacheRoot.exists()) {
      await cacheRoot.delete(recursive: true);
    }
  });

  test('factory preserves the shared cache and enables image resizing', () {
    expect(manager, isA<BaseCacheManager>());
    expect(manager, isA<ImageCacheManager>());
  });

  test(
    'keeps the original file when it is within the requested width',
    () async {
      const url = 'https://example.invalid/small.png';
      const originalKey = 'small-original';
      const targetWidth = 32;
      final original = await manager.putFile(
        url,
        await _pngBytes(width: 16, height: 12),
        key: originalKey,
        fileExtension: 'png',
      );

      final result = await _lastFileInfo(
        (manager as ImageCacheManager).getImageFile(
          url,
          key: originalKey,
          maxWidth: targetWidth,
        ),
      );

      expect(result.file.path, original.path);
      expect(
        await manager.getFileFromCache('resized_w${targetWidth}_$originalKey'),
        isNull,
      );
    },
  );

  test(
    'creates a bounded copy when the source exceeds the requested width',
    () async {
      const url = 'https://example.invalid/large.png';
      const originalKey = 'large-original';
      const targetWidth = 32;
      final original = await manager.putFile(
        url,
        await _pngBytes(width: 64, height: 40),
        key: originalKey,
        fileExtension: 'png',
      );

      final result = await _lastFileInfo(
        (manager as ImageCacheManager).getImageFile(
          url,
          key: originalKey,
          maxWidth: targetWidth,
        ),
      );
      final dimensions = await _imageDimensions(result.file);

      expect(result.file.path, isNot(original.path));
      expect(dimensions.width, targetWidth);
      expect(dimensions.height, 20);
      expect(
        await manager.getFileFromCache('resized_w${targetWidth}_$originalKey'),
        isNotNull,
      );
      expect(
        p.isWithin(
          p.join(cacheRoot.path, ImageCacheManagerFactory.cacheKey),
          result.file.path,
        ),
        isTrue,
      );
    },
  );
}

Future<FileInfo> _lastFileInfo(Stream<FileResponse> responses) async {
  final values = await responses.toList();
  return values.whereType<FileInfo>().last;
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
  if (data == null) {
    throw StateError('Failed to encode generated PNG fixture.');
  }
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<({int width, int height})> _imageDimensions(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final frame = await codec.getNextFrame();
  final dimensions = (width: frame.image.width, height: frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return dimensions;
}
