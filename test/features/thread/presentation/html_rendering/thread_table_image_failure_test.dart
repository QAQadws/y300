import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/content_rendering_shared/application/host/cache_forum_html_image_host.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

void main() {
  testWidgets('failed image in a nested table remains mounted without retry', (
    tester,
  ) async {
    final cache = _FailingCache();
    final viewport = ForumHtmlImageViewportCoordinator();
    addTearDown(viewport.dispose);
    final host = CacheForumHtmlImageHost(
      dimensionIndex: CacheRecordForumImageDimensionIndex(
        imageCacheService: cache,
        imageRequestResolver: const DefaultForumImageRequestResolver(),
      ),
    ).forContent(threadId: 'table-failure');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cache)],
        child: LocalizedTestApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 376,
                height: 600,
                child: SingleChildScrollView(
                  child: ForumHtmlWidgetPostRenderer(
                    html:
                        '<div align="center"><table><tr><td>'
                        '<div align="center"><table><tr>'
                        '<td><img width="300" src="https://example.invalid/missing.png"></td>'
                        '<td><table><tr><td>Character name</td></tr>'
                        '<tr><td>Description of the character<br>Another line</td></tr>'
                        '</table></td></tr></table></div>'
                        '</td></tr></table></div>',
                    theme: forumHtmlTestTheme,
                    sourceId: 'table-failure',
                    threadId: 'table-failure',
                    imageHost: host,
                    imageViewportCoordinator: viewport,
                    buildAsync: false,
                    enableCaching: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump();
    }
    final image = find.byType(CachedLibraryImage);
    expect(image, findsOneWidget);
    expect(cache.downloads, 1);
    final element = tester.element(image);
    // This fake has no failure cooldown: stability must come from the renderer,
    // rather than hiding a per-frame remount behind the service's backoff.
    for (var frame = 0; frame < 45; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(image, findsOneWidget);
      expect(tester.element(image), same(element));
      expect(cache.downloads, 1);
    }
    expect(tester.takeException(), isNull);
  });
}

class _FailingCache extends ImageCacheService {
  int downloads = 0;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    downloads++;
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async => CachedImageResult.failed;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}
}
