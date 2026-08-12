import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';
import 'package:y300/features/library_shared/data/services/library_cover_decode_scheduler.dart';
import 'package:y300/features/library_shared/data/services/library_cover_store.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_header.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_palette.dart';
import 'package:y300/features/library_shared/presentation/images/library_cover_original_page.dart';
import 'package:y300/shared/widgets/library_cover_placeholder.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('detail cover opens original without Hero transitions', (
    tester,
  ) async {
    const asset = LibraryCoverAssetRef(
      assetId: 'comic/1/source',
      revision: 1,
      kind: LibraryCoverAssetKind.source,
    );
    final store = _UnavailableCoverStore();
    final scheduler = LibraryCoverDecodeScheduler(maxConcurrent: 3);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryCoverStoreProvider.overrideWithValue(store),
          libraryCoverDecodeSchedulerProvider.overrideWithValue(scheduler),
        ],
        child: LocalizedTestApp(
          home: Scaffold(
            body: UnifiedDetailHeaderSection(
              header: const LibraryDetailHeader(
                workId: 'comic:1',
                title: '测试作品',
                coverAsset: asset,
                inShelf: true,
              ),
              moduleKey: LibraryModuleKey.comic,
              topInset: 0,
              palette: _palette,
              imageHeaderBuilder: null,
              onToggleShelf: _noop,
              onRefresh: _noop,
              onOpenThread: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Hero), findsNothing);
    expect(
      find.byKey(const Key('unified-detail-cover-placeholder')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('unified-detail-background-placeholder')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
    final placeholders = tester.widgetList<LibraryCoverPlaceholder>(
      find.byType(LibraryCoverPlaceholder),
    );
    expect(
      placeholders.every(
        (placeholder) =>
            placeholder.color == _palette.headerPlaceholderBackground,
      ),
      isTrue,
    );
    await tester.tap(
      find.byKey(const Key('unified-detail-cover-open-original')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibraryCoverOriginalPage), findsOneWidget);
    expect(find.byType(Hero), findsNothing);
    expect(
      find.byKey(const Key('library-cover-original-placeholder')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });
}

void _noop() {}

const _palette = UnifiedDetailPalette(
  pageBackground: Colors.white,
  headerGradientStart: Colors.black12,
  headerGradientMiddle: Colors.white70,
  headerGradientEnd: Colors.white,
  headerFallbackBackground: Colors.grey,
  headerPlaceholderBackground: Colors.black12,
  onHeader: Colors.white,
  heroInfoForeground: Colors.black,
  collapsedAppBarBackground: Colors.white,
  collapsedAppBarForeground: Colors.black,
);

class _UnavailableCoverStore implements LibraryCoverStore {
  @override
  Future<int> calculateUsageBytes() async => 0;

  @override
  Future<void> deleteAsset(String assetId) async {}

  @override
  Future<void> deleteOlderRevisions(LibraryCoverAssetRef asset) async {}

  @override
  Future<io.File> ensureAvailable(LibraryCoverAssetRef asset) async {
    throw StateError('Cover unavailable in widget test');
  }

  @override
  Future<io.File> fileFor(LibraryCoverAssetRef asset) async {
    throw StateError('Cover unavailable in widget test');
  }

  @override
  Future<void> installLocalFile({
    required LibraryCoverAssetRef asset,
    required String sourcePath,
  }) async {}

  @override
  Future<void> invalidate(LibraryCoverAssetRef asset) async {}
}
