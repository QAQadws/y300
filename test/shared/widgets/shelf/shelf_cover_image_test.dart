import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/image_downscale_policy.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_image.dart';

void main() {
  testWidgets('ShelfCoverImage keeps remote-only covers as placeholder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShelfCoverImage(
          coverKey: 'cover-1',
          remoteUrl: 'https://img.test/cover.jpg',
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('ShelfCoverImage downscales local covers and keeps gapless playback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShelfCoverImage(
          coverKey: 'cover-1',
          // The widget can be verified from the Image provider itself. Using a
          // synthetic path avoids starting real image decoding in widget tests,
          // which can hold file handles open on Windows runners.
          localPath: 'E:/synthetic/shelf-cover.jpg',
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    // 默认降采样策略下，有限显示宽度会把 FileImage 包进 ResizeImage 解码降采样。
    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).imageProvider, isA<FileImage>());
    expect(image.gaplessPlayback, isTrue);
    expect(find.byKey(const Key('placeholder')), findsNothing);
  });

  testWidgets('ShelfCoverImage skips downscaling when policy is disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ShelfCoverImage(
          coverKey: 'cover-1',
          localPath: 'E:/synthetic/shelf-cover.jpg',
          fit: BoxFit.cover,
          downscalePolicy: _NoDownscalePolicy(),
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
    expect(image.gaplessPlayback, isTrue);
  });
}

/// 测试用降采样策略：始终返回“不降采样”，用于验证策略可被替换（Strategy）。
class _NoDownscalePolicy extends ImageDownscalePolicy {
  const _NoDownscalePolicy();

  @override
  ImageDecodeTarget resolve({
    required Size displaySize,
    required double devicePixelRatio,
  }) {
    return ImageDecodeTarget.none;
  }
}
