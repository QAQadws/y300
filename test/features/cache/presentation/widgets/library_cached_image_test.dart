import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';

void main() {
  testWidgets('network image uses headers from header builder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryCachedImage(
          imageUrl: 'https://bbs.yamibo.com/data/attachment/test.jpg',
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
          headerBuilder: const _StaticImageHeaderBuilder(<String, String>{
            'Referer': 'https://bbs.yamibo.com/',
            'Cookie': 'auth=token123',
          }),
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;
    expect(provider.headers, <String, String>{
      'Referer': 'https://bbs.yamibo.com/',
      'Cookie': 'auth=token123',
    });
  });

  testWidgets('network image keeps one placeholder while waiting for headers and first frame', (tester) async {
    final headerBuilder = _DeferredImageHeaderBuilder();
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryCachedImage(
          imageUrl: 'https://bbs.yamibo.com/data/attachment/test.jpg',
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
          headerBuilder: headerBuilder,
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    headerBuilder.complete(const <String, String>{
      'Referer': 'https://bbs.yamibo.com/',
    });
    await tester.pump();

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('network image normalizes relative Yamibo attachment urls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LibraryCachedImage(
          imageUrl: 'data/attachment/forum/page-1.jpg',
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      image.image,
      isA<NetworkImage>().having(
        (provider) => provider.url,
        'url',
        'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
      ),
    );
  });

  testWidgets('local image reports decoded dimensions', (tester) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final provider = _SynchronousImageProvider(testImage);

    Size? resolvedSize;
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryCachedImage(
          imageProviderOverride: provider,
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
          onImageResolved: (size) => resolvedSize = size,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(resolvedSize, const Size(3, 5));
  });
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder(this.headers);

  final Map<String, String> headers;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async => headers;
}

class _DeferredImageHeaderBuilder implements ImageRequestHeaderBuilder {
  final Completer<Map<String, String>> _completer =
      Completer<Map<String, String>>();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) {
    return _completer.future;
  }

  void complete(Map<String, String> headers) {
    _completer.complete(headers);
  }
}

class _SynchronousImageProvider extends ImageProvider<_SynchronousImageProvider> {
  const _SynchronousImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_SynchronousImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_SynchronousImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _SynchronousImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
    );
  }
}
