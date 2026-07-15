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
        child: MaterialApp(
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
