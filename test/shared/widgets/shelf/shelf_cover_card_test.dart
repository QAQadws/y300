import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_image_provider.dart';
import 'package:y300/shared/widgets/library_cover_placeholder.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_card.dart';
import 'package:y300/shared/widgets/shelf/shelf_theme_palette.dart';

import '../../../test_support/localized_test_app.dart';
import '../../../test_support/unavailable_library_cover_store.dart';

void main() {
  testWidgets(
    'ShelfCoverCard renders title and badge over a neutral placeholder',
    (tester) async {
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 180,
              child: ShelfCoverCard(
                title: '测试标题',
                coverImageUrl: null,
                onTap: () {},
                topLeftBadge: const Text('角标'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('测试标题'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('测试标题')).style?.fontWeight,
        FontWeight.w500,
      );
      expect(find.text('角标'), findsOneWidget);
      expect(find.byType(ShelfCoverCard), findsOneWidget);
    },
  );

  testWidgets('ShelfCoverCard uses compact shared cover geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: ShelfCoverCard(
              title: 'Compact Cover',
              coverImageUrl: null,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    final cardFinder = find.byType(ShelfCoverCard);
    final container = tester.widget<AnimatedContainer>(
      find.descendant(of: cardFinder, matching: find.byType(AnimatedContainer)),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(8));

    final clip = tester.widget<ClipRRect>(
      find.descendant(of: cardFinder, matching: find.byType(ClipRRect)).first,
    );
    expect(clip.borderRadius, BorderRadius.circular(7));
  });

  testWidgets('cover provider uses the actual inner image size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryCoverStoreProvider.overrideWithValue(
            const UnavailableLibraryCoverStore(),
          ),
          libraryCoverDecodeSchedulerProvider.overrideWithValue(
            LibraryCoverDecodeScheduler(maxConcurrent: 3),
          ),
        ],
        child: LocalizedTestApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 180,
              child: ShelfCoverCard(
                title: 'Sized Cover',
                coverImageUrl: null,
                coverAsset: const LibraryCoverAssetRef(
                  assetId: 'comic/sized/source',
                  revision: 1,
                  kind: LibraryCoverAssetKind.source,
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final imageFinder = find.descendant(
      of: find.byType(ShelfCoverCard),
      matching: find.byType(Image),
    );
    final imageSize = tester.getSize(imageFinder);
    final provider = tester.widget<Image>(imageFinder).image;

    expect(imageSize, const Size(112, 172));
    expect(provider, isA<LibraryCoverImageProvider>());
    final coverProvider = provider as LibraryCoverImageProvider;
    expect(coverProvider.decodeTarget.targetWidthPx, imageSize.width * 2);
    expect(coverProvider.decodeTarget.targetHeightPx, imageSize.height * 2);
    expect(coverProvider.decodeTarget.targetWidthPx, isNot(240));
    expect(coverProvider.decodeTarget.targetHeightPx, isNot(360));
  });

  testWidgets('ShelfCoverCard supports custom two-line ellipsis mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: ShelfCoverCard(
              title: '这是一个非常非常长的标题用于验证通用书架卡片的两行中文省略逻辑是否生效',
              coverImageUrl: null,
              onTap: () {},
              showTwoLineCustomEllipsis: true,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('···'), findsOneWidget);
  });

  testWidgets('ShelfCoverCard uses shelf placeholder color from app theme', (
    tester,
  ) async {
    final theme = AppTheme.dark();
    final palette = const ShelfThemePaletteResolver().resolve(theme);

    await tester.pumpWidget(
      LocalizedTestApp(
        theme: theme,
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 180,
            child: ShelfCoverCard(
              title: 'No Cover',
              coverImageUrl: null,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    final fallback = tester.widget<LibraryCoverPlaceholder>(
      find.byKey(const Key('shelf-cover-placeholder')),
    );

    expect(fallback.color, palette.coverPlaceholderBackground);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('ShelfCoverCard applies focus only to custom covers', (
    tester,
  ) async {
    final alignments = <AlignmentGeometry>[];

    Future<void> pumpCard({
      String? customCoverLocalPath,
      double? focusX,
      double? focusY,
    }) {
      return tester.pumpWidget(
        LocalizedTestApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 180,
              child: ShelfCoverCard(
                title: 'Focused Cover',
                coverImageUrl: 'https://example.com/cover.jpg',
                customCoverLocalPath: customCoverLocalPath,
                customCoverFocusX: focusX,
                customCoverFocusY: focusY,
                onTap: () {},
                coverLayerBuilder: (context, config) {
                  alignments.add(config.alignment);
                  return config.placeholder;
                },
              ),
            ),
          ),
        ),
      );
    }

    await pumpCard(
      customCoverLocalPath: 'cache/custom-cover.jpg',
      focusX: 0.75,
      focusY: -0.5,
    );
    expect(alignments.last, const Alignment(0.75, -0.5));

    await pumpCard(focusX: 0.75, focusY: -0.5);
    expect(alignments.last, Alignment.center);

    await pumpCard(customCoverLocalPath: 'cache/custom-cover.jpg', focusX: 1);
    expect(alignments.last, Alignment.center);
  });
}
