import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/image_loading/presentation/app_image.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_image.dart';

void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      child: LocalizedTestApp(home: child),
    );
  }

  testWidgets('ShelfCoverImage delegates to AppImage', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ShelfCoverImage(
          coverKey: 'cover-1',
          remoteUrl: 'https://img.test/cover.jpg',
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    expect(find.byType(AppImage), findsOneWidget);
  });

  testWidgets(
    'ShelfCoverImage shows placeholder when neither local nor remote provided',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          const ShelfCoverImage(
            coverKey: 'cover-1',
            fit: BoxFit.cover,
            placeholder: SizedBox(key: Key('placeholder')),
          ),
        ),
      );

      // 无本地路径、无网络 URL 时，AppImage 回落到占位。
      expect(find.byKey(const Key('placeholder')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('ShelfCoverImage downscales local covers via AppImage', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ShelfCoverImage(
          coverKey: 'cover-1',
          // 合成路径避免在 widget 测试里真正解码、占用文件句柄。
          localPath: 'E:/synthetic/shelf-cover.jpg',
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    // 文件不存在时 AppImage 会落到网络/占位分支；这里仅验证委托关系成立。
    expect(find.byType(AppImage), findsOneWidget);
  });
}
