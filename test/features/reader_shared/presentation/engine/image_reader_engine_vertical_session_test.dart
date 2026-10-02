import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_reader_view.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/reader_shared/presentation/reader_preferences/reader_preferences_provider.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'reader_pref_mode': 'vertical',
      'reader_pref_page_spacing': 0.0,
    });
  });

  for (final imageCount in [1, 2, 20]) {
    for (final fromTail in [false, true]) {
      testWidgets(
        'owner switch from ${fromTail ? 'tail' : 'images'} starts $imageCount images at the top',
        (tester) async {
          final first = _Capability(tail: _Tail());
          final active = ValueNotifier(first);
          addTearDown(active.dispose);
          await tester.pumpWidget(_host(active));
          await tester.pumpAndSettle();
          final oldScroll = _scroll(tester);
          oldScroll.jumpTo(fromTail ? 5300 : 1600);
          await tester.pumpAndSettle();
          expect(oldScroll.offset, greaterThan(0));
          final staleView = tester.widget<ContinuousImageReaderView>(
            find.byType(ContinuousImageReaderView),
          );
          final staleDimensions = first.dimensions[0]!;

          final next = _Capability(owner: 'next', count: imageCount);
          active.value = next;
          await tester.pumpAndSettle();
          expect(identical(_scroll(tester), oldScroll), isFalse);
          expect(_scroll(tester).keepScrollOffset, isFalse);
          expect(_scroll(tester).offset, 0);
          expect(next.visible, [0]);
          expect(next.progress, isEmpty);
          expect(
            tester.getTopLeft(find.byKey(const Key('image-next-0'))).dy,
            0,
          );

          // Delayed layout/decode notifications from an unmounted owner must
          // not resize the new slots or enqueue compensation on its controller.
          staleDimensions(const Size(100, 500));
          staleView.onExtentResolved(_extent(first.owner, 5000));
          await tester.pumpAndSettle();
          expect(_scroll(tester).offset, 0);
          expect(
            tester.getSize(find.byKey(const Key('image-next-0'))).height,
            800,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'same-owner refresh restores its index using the new controller',
    (tester) async {
      final first = _Capability();
      final active = ValueNotifier(first);
      addTearDown(active.dispose);
      await tester.pumpWidget(_host(active));
      await tester.pumpAndSettle();
      final oldView = tester.widget<ContinuousImageReaderView>(
        find.byType(ContinuousImageReaderView),
      );
      final staleDimensions = first.dimensions[0]!;
      _scroll(tester).jumpTo(900);
      await tester.pumpAndSettle();
      final oldScroll = _scroll(tester);
      active.value = _Capability(revision: 1, initialIndex: 4);
      await tester.pumpAndSettle();
      final scroll = _scroll(tester);
      expect(identical(scroll, oldScroll), isFalse);
      expect(scroll.offset, closeTo(3200, 0.5));
      // The existing progress policy includes the image ending exactly at
      // the viewport start; the requested image itself is aligned at the top.
      expect(active.value.visible, [3]);
      expect(tester.getTopLeft(find.byKey(const Key('image-first-4'))).dy, 0);

      staleDimensions(const Size(100, 500));
      oldView.onExtentResolved(_extent(first.owner, 5000));
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(3200, 0.5));

      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      active.value = _Capability(revision: 1, initialIndex: 4);
      await tester.pumpAndSettle();
      expect(identical(_scroll(tester), scroll), isTrue);
      expect(
        scroll.offset,
        0,
        reason: 'A normal rebuild must not restore again.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a saved offset belongs only to its opening session', (
    tester,
  ) async {
    final active = ValueNotifier(_Capability(offset: 1250, initialIndex: 1));
    addTearDown(active.dispose);
    await tester.pumpWidget(_host(active));
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, 1250);
    active.value = _Capability(owner: 'next', offset: 0);
    await tester.pumpAndSettle();
    expect(_scroll(tester).offset, 0);
    expect(active.value.visible, [0]);
  });

  testWidgets(
    'replacing an owner during an initial seek cancels old corrections',
    (tester) async {
      final active = ValueNotifier(_Capability(count: 30, initialIndex: 25));
      addTearDown(active.dispose);
      await tester.pumpWidget(_host(active));
      await tester.pump();
      active.value = _Capability(owner: 'next');
      await tester.pumpAndSettle();
      expect(_scroll(tester).offset, 0);
      expect(active.value.visible, [0]);
      expect(active.value.progress, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final tailHeight in [80.0, 3000.0]) {
    for (final safeBottom in [0.0, 34.0]) {
      for (final hasNext in [false, true]) {
        testWidgets(
          'tail $tailHeight, safe inset $safeBottom, next $hasNext reserves actions only at the end',
          (tester) async {
            final tail = _Tail(
              height: tailHeight,
              barHeight: safeBottom == 0 ? 64 : 112,
            );
            final active = ValueNotifier(
              _Capability(tail: tail, hasNext: hasNext),
            );
            addTearDown(active.dispose);
            await tester.pumpWidget(_host(active, safeBottom: safeBottom));
            await tester.pumpAndSettle();
            final scroll = _scroll(tester);
            // Lazy extent estimates settle after the final rows are built.
            for (var i = 0; i < 3; i++) {
              scroll.jumpTo(scroll.position.maxScrollExtent);
              await tester.pumpAndSettle();
            }
            final tailRect = tester.getRect(
              find.byKey(const Key('tail-content')),
            );
            final end = hasNext
                ? tester.getRect(find.byKey(const Key('next-content')))
                : tailRect;
            if (hasNext) {
              expect(end.top - tailRect.bottom, closeTo(0, 0.5));
            }
            final bar = tester.getRect(find.byKey(const Key('action-bar')));
            expect(bar.height, tail.barHeight + safeBottom);
            expect(end.bottom, closeTo(bar.top, 0.5));
            expect(tail.visibility.last, isTrue);
            tail.visibility.clear();
            scroll.jumpTo(scroll.offset - 10);
            await tester.pumpAndSettle();
            scroll.jumpTo(scroll.position.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(tail.visibility.where((visible) => !visible), isEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

ScrollController _scroll(WidgetTester tester) =>
    tester.widget<ListView>(find.byKey(const Key('session-list'))).controller!;

ContinuousImageExtent _extent(String owner, double height) =>
    ContinuousImageExtent(
      ownerId: owner,
      itemId: '$owner-0',
      index: 0,
      mainAxisExtent: height,
      crossAxisExtent: 800,
      aspectRatio: 800 / height,
      dimensionSource: ContinuousImageDimensionSource.decodedImage,
      measuredAt: DateTime(2026),
    );

Widget _host(
  ValueNotifier<_Capability> active, {
  double safeBottom = 0,
}) => ProviderScope(
  overrides: [forumImagePrecacheServiceProvider.overrideWithValue(_Precache())],
  child: LocalizedTestApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        padding: EdgeInsets.only(bottom: safeBottom),
      ),
      child: PageStorage(
        bucket: PageStorageBucket(),
        child: Consumer(
          builder: (context, ref, child) {
            if (ref.watch(readerPreferencesControllerProvider).value == null) {
              return const SizedBox.shrink();
            }
            return ValueListenableBuilder<_Capability>(
              valueListenable: active,
              builder: (context, capability, child) => ImageReaderEngine(
                capability: capability,
                listKey: const Key('session-list'),
              ),
            );
          },
        ),
      ),
    ),
  ),
);

class _Capability extends ReaderCapability {
  _Capability({
    this.owner = 'first',
    this.revision = 0,
    this.count = 6,
    this.initialIndex = 0,
    this.offset,
    this.tail,
    this.hasNext = false,
  });
  final String owner;
  final int revision;
  final int count;
  final int initialIndex;
  final double? offset;
  final _Tail? tail;
  final bool hasNext;
  final visible = <int>[];
  final progress = <int>[];
  final dimensions = <int, ValueChanged<Size>>{};

  @override
  ReaderContent get content => ReaderContent(
    ownerId: owner,
    sessionRevision: revision,
    initialIndex: initialIndex,
    items: List.generate(
      count,
      (index) => ContinuousImageItem(
        ownerId: owner,
        id: '$owner-$index',
        url: 'https://img.test/$owner/$index.jpg',
        cacheKey: '$owner-$index',
        index: index,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        knownWidth: 100,
        knownHeight: 100,
      ),
    ),
  );
  @override
  String? get imageReferer => null;
  @override
  double? get initialVerticalScrollOffset => offset;
  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) =>
      const ReaderTitleSpec(title: 'test');
  @override
  ReaderTailSurface? get tailSurface => tail;
  @override
  WidgetBuilder? verticalTrailingBuilder(ReaderEngineContext context) => hasNext
      ? (_) => const SizedBox(key: Key('next-content'), height: 100)
      : null;
  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) {
    dimensions[spec.index] = spec.onDimensionsResolved;
    return ColoredBox(
      key: Key('image-$owner-${spec.index}'),
      color: Colors.black,
    );
  }

  @override
  void onImageVisible(int index) => visible.add(index);
  @override
  void onScrollProgress({required int index, required double offset}) =>
      progress.add(index);
  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) =>
      ImageCacheRequest(
        cacheKey: item.cacheKey,
        sourceUrl: item.url,
        ownerType: ImageCacheOwnerType.thread,
        ownerId: item.ownerId,
        role: ImageCacheRole.threadInline,
      );
}

class _Tail implements ReaderTailSurface, ReaderTailActionSurface {
  _Tail({this.height = 3000, this.barHeight = 64});
  final double height;
  final double barHeight;
  final visibility = <bool>[];
  @override
  String get id => 'tail';
  @override
  bool get hasAdvance => false;
  @override
  bool get isAdjacentPreloadReady => false;
  @override
  int get verticalItemCount => 1;
  @override
  String indicatorLabel(BuildContext context) => 'tail';
  @override
  Widget buildVertical(BuildContext context, ReaderTailActions actions) =>
      SizedBox(key: const Key('tail-content'), height: height);
  @override
  Widget buildVerticalItem(
    BuildContext context,
    ReaderTailActions actions,
    int index,
  ) => buildVertical(context, actions);
  @override
  Widget buildPaged(BuildContext context, ReaderTailActions actions) =>
      buildVertical(context, actions);
  @override
  Widget buildAdvance(BuildContext context, ReaderTailActions actions) =>
      const SizedBox.shrink();
  @override
  Widget buildActionBar(BuildContext context) => Material(
    key: const Key('action-bar'),
    child: SafeArea(
      top: false,
      child: SizedBox(height: barHeight, width: double.infinity),
    ),
  );
  @override
  void onVisibilityChanged(bool visible) => visibility.add(visible);
  @override
  void onVisible() {}
  @override
  void onVerticalVisible() {}
  @override
  void onRetry() {}
  @override
  void onAdvance() {}
  @override
  void dispose() {}
}

class _Precache implements ForumImagePrecacheService {
  @override
  Future<ForumImagePrecacheResult> ensureDiskCached(
    ForumImageLoadSpec spec,
  ) async => const ForumImagePrecacheResult(success: true);
  @override
  Future<ForumImagePrecacheResult> precacheDecoded({
    required BuildContext context,
    required ForumImageLoadSpec spec,
    Size? expectedDisplaySize,
  }) async => const ForumImagePrecacheResult(success: true, decoded: true);
}
