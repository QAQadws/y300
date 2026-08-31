import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/encoded_image_dimension_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads intrinsic PNG dimensions without creating a codec', () async {
    final directory = io.Directory.systemTemp.createTempSync(
      'encoded_image_dimension_probe_test_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = io.File('${directory.path}/image.png')
      ..writeAsBytesSync(base64Decode(_onePixelPngBase64), flush: true);

    final size = await loadEncodedImageDimensions(file.path);

    expect(size, const Size(1, 1));
  });

  test('shares one in-flight read for the same cache entry and path', () async {
    final pending = Completer<Size>();
    var calls = 0;
    final probe = SerialEncodedImageDimensionProbe(
      loader: (path) {
        calls += 1;
        return pending.future;
      },
    );

    final first = probe.probe(cacheKey: 'image', localPath: 'cache/image.png');
    final second = probe.probe(cacheKey: 'image', localPath: 'cache/image.png');
    await Future<void>.delayed(Duration.zero);

    expect(calls, 1);
    pending.complete(const Size(1200, 1800));
    expect(await first, const Size(1200, 1800));
    expect(await second, const Size(1200, 1800));
  });

  test('serializes probes for different resources', () async {
    final pending = <String, Completer<Size>>{};
    final started = <String>[];
    var running = 0;
    var maxRunning = 0;
    final probe = SerialEncodedImageDimensionProbe(
      loader: (path) async {
        started.add(path);
        running += 1;
        maxRunning = running > maxRunning ? running : maxRunning;
        try {
          return await pending.putIfAbsent(path, Completer<Size>.new).future;
        } finally {
          running -= 1;
        }
      },
    );

    final first = probe.probe(cacheKey: 'first', localPath: 'cache/first.png');
    final second = probe.probe(
      cacheKey: 'second',
      localPath: 'cache/second.png',
    );
    await Future<void>.delayed(Duration.zero);

    expect(started, <String>['cache/first.png']);
    pending['cache/first.png']!.complete(const Size(10, 20));
    expect(await first, const Size(10, 20));
    await Future<void>.delayed(Duration.zero);
    expect(started, <String>['cache/first.png', 'cache/second.png']);

    pending['cache/second.png']!.complete(const Size(30, 40));
    expect(await second, const Size(30, 40));
    expect(maxRunning, 1);
  });
}

const _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
