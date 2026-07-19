import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';

void main() {
  testWidgets('LTR reaches tail and advance without extending image progress', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'reader_pref_mode': 'ltr',
    });
    final tail = _RecordingTailSurface();
    await tester.pumpWidget(_host(tail));
    await tester.pump();

    final page = find.byKey(const Key('tail-test-page'));
    await tester.drag(page, const Offset(-700, 0));
    await tester.pumpAndSettle();
    await tester.drag(page, const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-tail-tail')), findsOneWidget);
    expect(tail.visibleCount, 1);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('comic-reader-page-indicator-text')),
          )
          .data,
      '评论',
    );

    await tester.drag(page, const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-tail-advance-tail')), findsOneWidget);
    expect(tail.advanceCount, 1);

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('shared-reader-center-tap-zone'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const Key('shared-reader-progress-slider')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('shared-reader-total-label')))
          .data,
      '2',
    );
  });

  testWidgets(
    'RTL reaches the same logical tail in reverse physical direction',
    (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'reader_pref_mode': 'rtl',
      });
      final tail = _RecordingTailSurface();
      await tester.pumpWidget(_host(tail));
      await tester.pump();

      final page = find.byKey(const Key('tail-test-page'));
      await tester.drag(page, const Offset(700, 0));
      await tester.pumpAndSettle();
      await tester.drag(page, const Offset(700, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reader-tail-tail')), findsOneWidget);
      expect(tail.visibleCount, 1);
    },
  );
}

Widget _host(_RecordingTailSurface tail) {
  return ProviderScope(
    overrides: [
      forumImagePrecacheServiceProvider.overrideWithValue(
        _NoopForumImagePrecacheService(),
      ),
    ],
    child: MaterialApp(
      home: ImageReaderEngine(
        key: const Key('tail-test-engine'),
        pageKey: const Key('tail-test-page'),
        listKey: const Key('tail-test-list'),
        capability: _TailCapability(tail),
      ),
    ),
  );
}

class _TailCapability extends ReaderCapability {
  _TailCapability(this._tail);

  final _RecordingTailSurface _tail;

  @override
  ReaderContent get content => ReaderContent(
    ownerId: 'tail-owner',
    items: List<ContinuousImageItem>.generate(2, (index) {
      return ContinuousImageItem(
        ownerId: 'tail-owner',
        id: 'tail-image-$index',
        url: 'https://img.test/$index.jpg',
        cacheKey: 'tail-image-$index',
        index: index,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        knownWidth: 100,
        knownHeight: 100,
      );
    }),
  );

  @override
  ReaderTailSurface get tailSurface => _tail;

  @override
  ImageRequestHeaderBuilder? get imageHeaderBuilder => null;

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    return const ReaderTitleSpec(title: 'tail test');
  }

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) {
    return ColoredBox(
      color: Colors.black,
      child: Center(child: Text('${spec.index}')),
    );
  }

  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) {
    return ImageCacheRequest(
      cacheKey: item.cacheKey,
      sourceUrl: item.url,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: item.ownerId,
      role: ImageCacheRole.threadInline,
    );
  }
}

class _RecordingTailSurface implements ReaderTailSurface {
  int visibleCount = 0;
  int retryCount = 0;
  int advanceCount = 0;

  @override
  String get id => 'tail';

  @override
  String get indicatorLabel => '评论';

  @override
  int get verticalItemCount => 1;

  @override
  bool get hasAdvance => true;

  @override
  Widget buildPaged(BuildContext context, ReaderTailActions actions) {
    return const ColoredBox(
      key: Key('tail-paged-content'),
      color: Colors.blue,
      child: Center(child: Text('评论')),
    );
  }

  @override
  Widget buildVertical(BuildContext context, ReaderTailActions actions) {
    return const SizedBox(key: Key('tail-vertical-content'), height: 80);
  }

  @override
  Widget buildVerticalItem(
    BuildContext context,
    ReaderTailActions actions,
    int index,
  ) {
    return buildVertical(context, actions);
  }

  @override
  Widget buildAdvance(BuildContext context, ReaderTailActions actions) {
    return const ColoredBox(
      key: Key('tail-advance-content'),
      color: Colors.green,
      child: Center(child: Text('继续')),
    );
  }

  @override
  Future<void> onVisible() async => visibleCount++;

  @override
  Future<void> onVerticalVisible() async {}

  @override
  Future<void> onRetry() async => retryCount++;

  @override
  Future<void> onAdvance() async => advanceCount++;

  @override
  void dispose() {}
}

class _NoopForumImagePrecacheService implements ForumImagePrecacheService {
  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async {
    return const ForumImagePrecacheResult(success: true);
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    return const ForumImagePrecacheResult(success: true, decoded: true);
  }
}
