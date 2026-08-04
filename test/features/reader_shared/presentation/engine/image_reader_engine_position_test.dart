import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'reader_pref_mode': 'ltr',
    });
  });

  testWidgets('slider unlocks when capability seek callback fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recorder = _RecordingDiagnosticRecorder();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumImagePrecacheServiceProvider.overrideWithValue(
            _NoopForumImagePrecacheService(),
          ),
        ],
        child: LocalizedTestApp(
          home: ImageReaderEngine(
            capability: _ThrowingSeekCapability(recorder),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('shared-reader-center-tap-zone'))),
    );
    await tester.pump(const Duration(milliseconds: 330));
    await tester.pump(const Duration(milliseconds: 260));

    final sliderFinder = find.byKey(const Key('shared-reader-progress-slider'));
    final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
    await gesture.moveBy(Offset(tester.getSize(sliderFinder).width * 0.42, 0));
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(tester.widget<Slider>(sliderFinder).onChanged, isNotNull);
    expect(
      recorder.events.any(
        (event) =>
            event.type == ContinuousImageDiagnosticEventType.seekFailed &&
            event.result == 'StateError',
      ),
      isTrue,
    );
  });

  testWidgets(
    'height-fit wide page pans internally and only edge turn saves progress',
    (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'reader_pref_mode': 'ltr',
        'reader_pref_page_fit': 'fitHeight',
      });
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final capability = _RecordingPagedCapability();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumImagePrecacheServiceProvider.overrideWithValue(
              _NoopForumImagePrecacheService(),
            ),
          ],
          child: LocalizedTestApp(
            home: ImageReaderEngine(capability: capability),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final activeSurface = find.byKey(
        const ValueKey<String>(
          'reader-paged-fit-paged-owner-paged-owner:1-fitHeight-ltr',
        ),
      );
      expect(activeSurface, findsOneWidget);
      expect(
        tester.widget<PageView>(find.byType(PageView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      final innerScroll = find.descendant(
        of: activeSurface,
        matching: find.byType(SingleChildScrollView),
      );
      final innerController = tester
          .widget<SingleChildScrollView>(innerScroll)
          .controller!;

      await tester.drag(innerScroll, const Offset(-120, 0));
      await tester.pump();
      expect(innerController.offset, greaterThan(0));
      expect(capability.progressIndexes, isEmpty);

      innerController.jumpTo(innerController.position.maxScrollExtent);
      await tester.drag(innerScroll, const Offset(-80, 0));
      await tester.pumpAndSettle();

      expect(capability.progressIndexes, <int>[2]);
    },
  );

  testWidgets('vertical mode does not build the paged fit surface', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'reader_pref_mode': 'vertical',
      'reader_pref_page_fit': 'fitWidth',
    });
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumImagePrecacheServiceProvider.overrideWithValue(
            _NoopForumImagePrecacheService(),
          ),
        ],
        child: LocalizedTestApp(
          home: ImageReaderEngine(capability: _RecordingPagedCapability()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ReaderPagedImageFitSurface), findsNothing);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets(
    'decoded dimensions remove internal vertical slot padding at zero spacing',
    (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{
        'reader_pref_mode': 'vertical',
        'reader_pref_page_fit': 'fitWidth',
        'reader_pref_page_spacing': 0.0,
      });
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumImagePrecacheServiceProvider.overrideWithValue(
              _NoopForumImagePrecacheService(),
            ),
          ],
          child: LocalizedTestApp(
            home: ImageReaderEngine(
              capability: _DecodedVerticalDimensionCapability(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final reader = tester.widget<ContinuousImageReaderView>(
        find.byType(ContinuousImageReaderView),
      );
      expect(reader.items, hasLength(2));
      expect(reader.items.map((item) => item.spacingAfter), everyElement(0));
      expect(
        reader.items.map((item) => item.knownDimensionSource),
        everyElement(ContinuousImageDimensionSource.decodedImage),
      );

      final firstSlot = tester.getRect(
        find.byKey(const ValueKey<String>('image-reader-engine-image-slot-0')),
      );
      final secondSlot = tester.getRect(
        find.byKey(const ValueKey<String>('image-reader-engine-image-slot-1')),
      );
      final firstImage = tester.getRect(
        find.byKey(const ValueKey<String>('decoded-vertical-image-0')),
      );

      // The HTML hint reserves 1200dp (600 / 0.5), while the decoded image is
      // 600x300. The final slot must follow the decoded 2:1 ratio so the
      // image does not sit inside a taller box that looks like page spacing.
      expect(firstSlot.height, closeTo(300, 0.5));
      expect(firstImage.height, closeTo(firstSlot.height, 0.5));
      expect(secondSlot.top - firstSlot.bottom, closeTo(0, 0.5));
    },
  );

  testWidgets('loading indicator color contrasts reader backgrounds', (
    tester,
  ) async {
    Future<Color> resolveColor(String background) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reader_pref_mode': 'ltr',
        'reader_pref_background': background,
      });
      final capability = _RecordingPagedCapability();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forumImagePrecacheServiceProvider.overrideWithValue(
              _NoopForumImagePrecacheService(),
            ),
          ],
          child: LocalizedTestApp(
            home: ImageReaderEngine(capability: capability),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final color = capability.loadingIndicatorColors.last;
      await tester.pumpWidget(const SizedBox.shrink());
      return color;
    }

    expect(await resolveColor('black'), Colors.white70);
    expect(await resolveColor('gray'), Colors.white70);
    expect(await resolveColor('white'), Colors.black54);
  });

  testWidgets('decoded dimensions replace a paged fallback aspect ratio', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'reader_pref_mode': 'ltr',
      'reader_pref_page_fit': 'fitHeight',
    });
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final capability = _DecodedDimensionCapability();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumImagePrecacheServiceProvider.overrideWithValue(
            _NoopForumImagePrecacheService(),
          ),
        ],
        child: LocalizedTestApp(
          home: ImageReaderEngine(capability: capability),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final surface = find.byKey(
      const ValueKey<String>(
        'reader-paged-fit-decoded-owner-decoded-item-fitHeight-ltr',
      ),
    );
    expect(
      find.descendant(
        of: surface,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    expect(
      capability.expectedDisplaySizes.last.width,
      greaterThan(tester.view.physicalSize.width),
    );
  });
}

class _ThrowingSeekCapability extends ReaderCapability {
  _ThrowingSeekCapability(this._recorder);

  final ContinuousImageDiagnosticRecorder _recorder;

  @override
  ContinuousImageDiagnosticRecorder get diagnosticRecorder => _recorder;

  @override
  ReaderContent get content => ReaderContent(
    ownerId: 'reader-owner',
    initialIndex: 2,
    items: List<ContinuousImageItem>.generate(5, (index) {
      return ContinuousImageItem(
        ownerId: 'reader-owner',
        id: 'reader-owner:$index',
        url: 'https://img.test/$index.jpg',
        cacheKey: 'reader/$index',
        index: index,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        knownWidth: 200,
        knownHeight: 300,
      );
    }),
  );

  @override
  ImageRequestHeaderBuilder? get imageHeaderBuilder => null;

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    return ReaderTitleSpec(
      title: 'reader',
      subtitle: '${context.currentIndex + 1} / ${context.totalCount}',
    );
  }

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) {
    return ColoredBox(
      color: Colors.black,
      child: Center(child: Text('${spec.index}')),
    );
  }

  @override
  Future<void> onSeek({required int index, required double offset}) {
    throw StateError('seek failed');
  }

  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) {
    return ImageCacheRequest(
      cacheKey: item.cacheKey,
      sourceUrl: item.url,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: item.ownerId,
      role: ImageCacheRole.threadInline,
      imageIndex: item.index,
      retentionClass: ImageRetentionClass.recentReader,
    );
  }
}

class _RecordingPagedCapability extends ReaderCapability {
  final List<int> progressIndexes = <int>[];
  final List<Color> loadingIndicatorColors = <Color>[];

  @override
  ReaderContent get content => ReaderContent(
    ownerId: 'paged-owner',
    initialIndex: 1,
    items: List<ContinuousImageItem>.generate(3, (index) {
      return ContinuousImageItem(
        ownerId: 'paged-owner',
        id: 'paged-owner:$index',
        url: 'https://img.test/paged-$index.jpg',
        cacheKey: 'reader/paged-$index',
        index: index,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        knownWidth: 1200,
        knownHeight: 400,
      );
    }),
  );

  @override
  ImageRequestHeaderBuilder? get imageHeaderBuilder => null;

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    return ReaderTitleSpec(
      title: 'reader',
      subtitle: '${context.currentIndex + 1} / ${context.totalCount}',
    );
  }

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) {
    loadingIndicatorColors.add(spec.loadingIndicatorColor);
    return ColoredBox(
      color: Colors.black,
      child: Center(child: Text('${spec.index}')),
    );
  }

  @override
  void onScrollProgress({required int index, required double offset}) {
    progressIndexes.add(index);
  }

  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) {
    return ImageCacheRequest(
      cacheKey: item.cacheKey,
      sourceUrl: item.url,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: item.ownerId,
      role: ImageCacheRole.threadInline,
      imageIndex: item.index,
      retentionClass: ImageRetentionClass.recentReader,
    );
  }
}

class _DecodedDimensionCapability extends ReaderCapability {
  bool _reportedDimensions = false;
  final List<Size> expectedDisplaySizes = <Size>[];

  @override
  ReaderContent get content => const ReaderContent(
    ownerId: 'decoded-owner',
    initialIndex: 0,
    items: <ContinuousImageItem>[
      ContinuousImageItem(
        ownerId: 'decoded-owner',
        id: 'decoded-item',
        url: 'https://img.test/decoded.jpg',
        cacheKey: 'reader/decoded',
        index: 0,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        fallbackAspectRatio: 0.7,
      ),
    ],
  );

  @override
  ImageRequestHeaderBuilder? get imageHeaderBuilder => null;

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    return const ReaderTitleSpec(title: 'reader', subtitle: '1 / 1');
  }

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) {
    expectedDisplaySizes.add(spec.expectedDisplaySize);
    if (!_reportedDimensions) {
      _reportedDimensions = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        spec.onDimensionsResolved(const Size(1200, 400));
      });
    }
    return const ColoredBox(color: Colors.black);
  }

  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) {
    return ImageCacheRequest(
      cacheKey: item.cacheKey,
      sourceUrl: item.url,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: item.ownerId,
      role: ImageCacheRole.threadInline,
      imageIndex: item.index,
      retentionClass: ImageRetentionClass.recentReader,
    );
  }
}

class _DecodedVerticalDimensionCapability extends ReaderCapability {
  final Set<String> _reportedItemIds = <String>{};

  @override
  ReaderContent get content => const ReaderContent(
    ownerId: 'decoded-vertical-owner',
    initialIndex: 0,
    items: <ContinuousImageItem>[
      ContinuousImageItem(
        ownerId: 'decoded-vertical-owner',
        id: 'decoded-vertical-item-0',
        url: 'https://img.test/decoded-vertical-0.jpg',
        cacheKey: 'reader/decoded-vertical-0',
        index: 0,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        knownWidth: 200,
        knownHeight: 400,
        knownDimensionSource: ContinuousImageDimensionSource.html,
      ),
      ContinuousImageItem(
        ownerId: 'decoded-vertical-owner',
        id: 'decoded-vertical-item-1',
        url: 'https://img.test/decoded-vertical-1.jpg',
        cacheKey: 'reader/decoded-vertical-1',
        index: 1,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        knownWidth: 200,
        knownHeight: 400,
        knownDimensionSource: ContinuousImageDimensionSource.html,
      ),
    ],
  );

  @override
  ImageRequestHeaderBuilder? get imageHeaderBuilder => null;

  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    return ReaderTitleSpec(
      title: 'reader',
      subtitle: '${context.currentIndex + 1} / ${context.totalCount}',
    );
  }

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) {
    if (_reportedItemIds.add(spec.item.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        spec.onDimensionsResolved(const Size(600, 300));
      });
    }
    return Align(
      child: AspectRatio(
        aspectRatio: 2,
        child: ColoredBox(
          key: ValueKey<String>('decoded-vertical-image-${spec.index}'),
          color: Colors.black,
        ),
      ),
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
      imageIndex: item.index,
      retentionClass: ImageRetentionClass.recentReader,
    );
  }
}

class _RecordingDiagnosticRecorder
    implements ContinuousImageDiagnosticRecorder {
  final events = <ContinuousImageDiagnosticEvent>[];

  @override
  bool get enabled => true;

  @override
  void recordContinuousImage(ContinuousImageDiagnosticEvent event) {
    events.add(event);
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
