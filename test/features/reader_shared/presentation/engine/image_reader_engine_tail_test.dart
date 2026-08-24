import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  testWidgets(
    'ready tail submits adjacent lookahead through shared coordinator',
    (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'reader_pref_mode': 'ltr',
      });
      final tail = _RecordingTailSurface()..adjacentReady = true;
      final service = _RecordingForumImagePrecacheService();
      await tester.pumpWidget(
        _host(tail, precacheService: service, adjacentPlan: _adjacentPlan()),
      );
      await tester.pump();

      final page = find.byKey(const Key('tail-test-page'));
      await tester.drag(page, const Offset(-700, 0));
      await tester.pumpAndSettle();
      await tester.drag(page, const Offset(-700, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reader-tail-tail')), findsOneWidget);
      final adjacentDecoded = service.decodedSpecs.where(
        (spec) => spec.episodeId == 'next-episode',
      );
      final adjacentDisk = service.diskSpecs.where(
        (spec) => spec.episodeId == 'next-episode',
      );
      expect(adjacentDecoded.map((spec) => spec.imageIndex), <int>[0, 1]);
      expect(adjacentDisk.map((spec) => spec.imageIndex), <int>[2, 3]);
      expect(
        service.allSpecs
            .where((spec) {
              return spec.episodeId == 'next-episode';
            })
            .every((spec) {
              return spec.kind == ForumImageKind.comicReaderPage &&
                  spec.episodeId == 'next-episode';
            }),
        isTrue,
      );
    },
  );

  testWidgets(
    'owner switch from the tail settles on the next owner first image',
    (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'reader_pref_mode': 'ltr',
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumImagePrecacheServiceProvider.overrideWithValue(
              _NoopForumImagePrecacheService(),
            ),
          ],
          child: LocalizedTestApp(
            home: PageStorage(
              bucket: PageStorageBucket(),
              child: const _OwnerSwitchHarness(),
            ),
          ),
        ),
      );
      await tester.pump();

      final page = find.byKey(const Key('owner-switch-page'));
      await tester.drag(page, const Offset(-700, 0));
      await tester.pumpAndSettle();
      await tester.drag(page, const Offset(-700, 0));
      await tester.pumpAndSettle();
      await tester.drag(page, const Offset(-700, 0));
      await tester.pumpAndSettle();

      expect(find.text('chapter-2:0'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('comic-reader-page-indicator-text')),
            )
            .data,
        '1 / 2',
      );
    },
  );

  testWidgets(
    'paged image cache construction does not report a cached page as visible',
    (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'reader_pref_mode': 'ltr',
      });
      final tail = _RecordingTailSurface();
      final capability = _TailCapability(tail, imageCount: 4);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumImagePrecacheServiceProvider.overrideWithValue(
              _NoopForumImagePrecacheService(),
            ),
          ],
          child: LocalizedTestApp(
            home: ImageReaderEngine(
              key: const Key('visibility-test-engine'),
              pageKey: const Key('visibility-test-page'),
              capability: capability,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(capability.visibleIndexes, <int>[0]);
    },
  );
}

Widget _host(
  _RecordingTailSurface tail, {
  ForumImagePrecacheService? precacheService,
  ReaderAdjacentPreloadPlan? adjacentPlan,
}) {
  return ProviderScope(
    overrides: [
      forumImagePrecacheServiceProvider.overrideWithValue(
        precacheService ?? _NoopForumImagePrecacheService(),
      ),
    ],
    child: LocalizedTestApp(
      home: ImageReaderEngine(
        key: const Key('tail-test-engine'),
        pageKey: const Key('tail-test-page'),
        listKey: const Key('tail-test-list'),
        capability: _TailCapability(tail, adjacentPlan: adjacentPlan),
      ),
    ),
  );
}

class _TailCapability extends ReaderCapability {
  _TailCapability(
    this._tail, {
    this.adjacentPlan,
    this.ownerId = 'tail-owner',
    this.imageCount = 2,
  });

  final _RecordingTailSurface _tail;
  final ReaderAdjacentPreloadPlan? adjacentPlan;
  final String ownerId;
  final int imageCount;
  final List<int> visibleIndexes = <int>[];

  @override
  Future<ReaderAdjacentPreloadPlan?> buildAdjacentPreloadPlan() async {
    return adjacentPlan;
  }

  @override
  ReaderContent get content => ReaderContent(
    ownerId: ownerId,
    items: List<ContinuousImageItem>.generate(imageCount, (index) {
      return ContinuousImageItem(
        ownerId: ownerId,
        id: '$ownerId-image-$index',
        url: 'https://img.test/$ownerId/$index.jpg',
        cacheKey: '$ownerId-image-$index',
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
  String? get imageReferer => null;

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    return const ReaderTitleSpec(title: 'tail test');
  }

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) {
    return ColoredBox(
      color: Colors.black,
      child: Center(child: Text('$ownerId:${spec.index}')),
    );
  }

  @override
  void onImageVisible(int index) {
    visibleIndexes.add(index);
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
  _RecordingTailSurface({this.onAdvanceCallback});

  final VoidCallback? onAdvanceCallback;
  int visibleCount = 0;
  int retryCount = 0;
  int advanceCount = 0;
  bool adjacentReady = false;

  @override
  String get id => 'tail';

  @override
  String indicatorLabel(BuildContext context) => '评论';

  @override
  int get verticalItemCount => 1;

  @override
  bool get hasAdvance => true;

  @override
  bool get isAdjacentPreloadReady => adjacentReady;

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
  Future<void> onAdvance() async {
    advanceCount++;
    onAdvanceCallback?.call();
  }

  @override
  void dispose() {}
}

class _OwnerSwitchHarness extends StatefulWidget {
  const _OwnerSwitchHarness();

  @override
  State<_OwnerSwitchHarness> createState() => _OwnerSwitchHarnessState();
}

class _OwnerSwitchHarnessState extends State<_OwnerSwitchHarness> {
  late final _RecordingTailSurface _tail;
  String _ownerId = 'chapter-1';

  @override
  void initState() {
    super.initState();
    _tail = _RecordingTailSurface(
      onAdvanceCallback: () {
        if (mounted) {
          setState(() => _ownerId = 'chapter-2');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ImageReaderEngine(
      key: const Key('owner-switch-engine'),
      pageKey: const Key('owner-switch-page'),
      listKey: const Key('owner-switch-list'),
      capability: _TailCapability(_tail, ownerId: _ownerId),
    );
  }
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

ReaderAdjacentPreloadPlan _adjacentPlan() {
  return ReaderAdjacentPreloadPlan(
    ownerId: 'next-episode',
    images: List<ReaderAdjacentPreloadImage>.generate(4, (index) {
      return ReaderAdjacentPreloadImage(
        itemId: 'next-episode:$index',
        imageIndex: index,
        spec: ForumImageLoadSpec(
          kind: ForumImageKind.comicReaderPage,
          url: Uri.parse('https://img.test/next-$index.jpg'),
          ownerId: 'comic-1',
          ownerType: ImageCacheOwnerType.comic,
          episodeId: 'next-episode',
          imageIndex: index,
          cacheKey: 'next-cache-$index',
        ),
      );
    }),
  );
}

class _RecordingForumImagePrecacheService implements ForumImagePrecacheService {
  final decodedSpecs = <ForumImageLoadSpec>[];
  final diskSpecs = <ForumImageLoadSpec>[];

  Iterable<ForumImageLoadSpec> get allSpecs sync* {
    yield* decodedSpecs;
    yield* diskSpecs;
  }

  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async {
    diskSpecs.add(spec);
    return ForumImagePrecacheResult(
      success: true,
      decoded: false,
      cacheKey: spec.cacheKey,
    );
  }

  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async {
    decodedSpecs.add(spec);
    return ForumImagePrecacheResult(
      success: true,
      decoded: true,
      cacheKey: spec.cacheKey,
    );
  }
}
