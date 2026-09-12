import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/messages/presentation/widgets/message_avatar.dart';

Future<void> settleMessageAvatarImages(WidgetTester tester) async {
  if (find.byType(MessageAvatar).evaluate().isEmpty) return;
  // File decoding happens outside the fake clock. Wait for actual display
  // frames so visual exports cannot silently capture only placeholders.
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final images = tester.widgetList<RawImage>(
      find.descendant(
        of: find.byType(MessageAvatar),
        matching: find.byType(RawImage),
      ),
    );
    if (images.length >= find.byType(MessageAvatar).evaluate().length &&
        images.every((image) => image.image != null)) {
      await tester.pump(const Duration(milliseconds: 350));
      return;
    }
  }
  fail('Message avatar did not produce a display frame');
}

/// Generated local portraits exercise the real file decoder, with no network,
/// personal images, or dependency on another checkout's fixtures.
class MessageAvatarTestCache extends Fake implements ImageCacheService {
  static const aliceUrl = 'https://bbs.yamibo.com/avatar-fixture/alice.png';
  static const meUrl = 'https://bbs.yamibo.com/avatar-fixture/me.png';

  final entries = <String, CachedImageResult>{};
  final reads = <String>[];
  final writes = <ImageCacheRequest>[];
  final pending = <Completer<CachedImageResult?>, String>{};
  final network = MessageAvatarTestNetworkCache();
  bool blocked = false;

  static Future<MessageAvatarTestCache> create(WidgetTester tester) async {
    final cache = MessageAvatarTestCache();
    final directory = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'message-avatars-',
      );
      for (final (index, url) in [aliceUrl, meUrl].indexed) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(
          index == 0 ? const Color(0xFFE9D8E3) : const Color(0xFFD4E4EC),
          BlendMode.src,
        );
        canvas.drawOval(
          const Rect.fromLTWH(15, 78, 90, 65),
          Paint()
            ..color = (index == 0
                ? const Color(0xFF8A526B)
                : const Color(0xFF426C83)),
        );
        canvas.drawOval(
          const Rect.fromLTWH(26, 16, 68, 84),
          Paint()..color = const Color(0xFF3C3035),
        );
        canvas.drawOval(
          const Rect.fromLTWH(36, 31, 49, 60),
          Paint()..color = const Color(0xFFE8B999),
        );
        canvas.drawCircle(
          const Offset(49, 55),
          2.5,
          Paint()..color = const Color(0xFF3C3035),
        );
        canvas.drawCircle(
          const Offset(72, 55),
          2.5,
          Paint()..color = const Color(0xFF3C3035),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(120, 120);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        final file = File('${directory.path}/$index.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        final key = ImageCacheKeys.avatar(url);
        cache.entries[key] = CachedImageResult(
          success: true,
          cacheKey: key,
          localPath: file.path,
          width: 120,
          height: 120,
          fromCache: true,
        );
      }
      return directory;
    });
    addTearDown(() async {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await directory!.delete(recursive: true);
    });
    return cache;
  }

  @override
  Future<CachedImageResult?> getCached(String key) {
    reads.add(key);
    if (!blocked) return Future.value(entries[key]);
    final completer = Completer<CachedImageResult?>();
    pending[completer] = key;
    return completer.future;
  }

  void release() {
    blocked = false;
    for (final entry in pending.entries) {
      entry.key.complete(entries[entry.value]);
    }
    pending.clear();
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    writes.add(request);
    return CachedImageResult.failed;
  }
}

class MessageAvatarTestNetworkCache extends Fake implements BaseCacheManager {
  int reads = 0;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    reads++;
    throw StateError('fixture avatar unavailable');
  }
}
