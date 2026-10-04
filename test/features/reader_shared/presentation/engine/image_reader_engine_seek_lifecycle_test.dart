import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';

import '../../../../test_support/localized_test_app.dart';

final _sliderFinder = find.byKey(const Key('shared-reader-progress-slider'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'reader_pref_mode': 'ltr'});
  });

  for (final failOldSeek in [false, true]) {
    final completion = failOldSeek ? 'failure' : 'success';
    testWidgets(
      'same-owner refresh keeps the new seek locked after old $completion',
      (tester) async {
        final recorder = _Recorder();
        final first = _GatedCapability(recorder: recorder);
        final refreshed = _GatedCapability(recorder: recorder, revision: 1);
        final active = ValueNotifier(first);
        addTearDown(active.dispose);
        addTearDown(first.completePending);
        addTearDown(refreshed.completePending);
        await _open(tester, active);
        _seek(tester, 2);
        await tester.pump();
        expect(first.seeks.single.index, 2);
        expect(_isLocked(tester), isTrue);

        active.value = refreshed;
        await tester.pumpAndSettle();
        await _showMenu(tester);
        expect(_isLocked(tester), isFalse);
        await _passCommitThrottle(tester);
        _seek(tester, 5);
        await tester.pump();
        expect(refreshed.seeks.single.index, 5);
        expect(_isLocked(tester), isTrue);
        expect(tester.widget<Slider>(_sliderFinder).value, 5);

        first.seeks.single.complete(fail: failOldSeek);
        await tester.pump();
        expect(_isLocked(tester), isTrue);
        expect(tester.widget<Slider>(_sliderFinder).value, 5);
        expect(recorder.reached(2), isEmpty);
        expect(refreshed.seeks.single.result.isCompleted, isFalse);

        refreshed.seeks.single.complete();
        await tester.pump();
        expect(_isLocked(tester), isFalse);
        expect(recorder.reached(5), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'disposed reader ignores pending seek $completion diagnostics',
      (tester) async {
        final recorder = _Recorder();
        final capability = _GatedCapability(recorder: recorder);
        final active = ValueNotifier(capability);
        addTearDown(active.dispose);
        addTearDown(capability.completePending);
        await _open(tester, active);
        _seek(tester, 3);
        await tester.pump();
        expect(_isLocked(tester), isTrue);
        expect(capability.seeks.single.index, 3);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        final diagnosticsAfterDispose = recorder.events.length;

        capability.seeks.single.complete(fail: failOldSeek);
        await tester.pump();
        expect(recorder.events, hasLength(diagnosticsAfterDispose));
        expect(recorder.reached(3), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'same-session superseded seek $completion cannot release a newer lock',
      (tester) async {
        final recorder = _Recorder();
        final capability = _GatedCapability(recorder: recorder);
        final active = ValueNotifier(capability);
        addTearDown(active.dispose);
        addTearDown(capability.completePending);
        await _open(tester, active);
        final oldSlider = tester.widget<Slider>(_sliderFinder);
        _seek(tester, 1);
        await tester.pump();
        expect(_isLocked(tester), isTrue);
        await _passCommitThrottle(tester);
        // A callback already dispatched before the absorbing surface rebuilt can
        // still arrive while the first business callback is awaiting persistence.
        oldSlider.onChangeEnd!.call(6);
        await tester.pump();
        expect(capability.seeks.map((seek) => seek.index), [1, 6]);
        expect(_isLocked(tester), isTrue);
        expect(tester.widget<Slider>(_sliderFinder).value, 6);

        capability.seeks.first.complete(fail: failOldSeek);
        await tester.pump();
        expect(_isLocked(tester), isTrue);
        expect(tester.widget<Slider>(_sliderFinder).value, 6);
        expect(recorder.reached(1), isEmpty);
        expect(capability.seeks.last.result.isCompleted, isFalse);
        capability.seeks.last.complete();
        await tester.pump();
        expect(_isLocked(tester), isFalse);
        expect(recorder.reached(6), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  ValueNotifier<_GatedCapability> active,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        forumImagePrecacheServiceProvider.overrideWithValue(_Precache()),
      ],
      child: LocalizedTestApp(
        home: ValueListenableBuilder<_GatedCapability>(
          valueListenable: active,
          builder: (_, capability, _) =>
              ImageReaderEngine(capability: capability),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _showMenu(tester);
}

Future<void> _showMenu(WidgetTester tester) async {
  if (_sliderFinder.evaluate().isNotEmpty) return;
  await tester.tap(find.byKey(const Key('shared-reader-center-tap-zone')));
  await tester.pumpAndSettle();
  expect(_sliderFinder, findsOneWidget);
}

void _seek(WidgetTester tester, double index) {
  final slider = tester.widget<Slider>(_sliderFinder);
  slider.onChangeStart?.call(index);
  slider.onChanged!.call(index);
  slider.onChangeEnd!.call(index);
}

bool _isLocked(WidgetTester tester) => tester
    .widget<AbsorbPointer>(
      find
          .ancestor(of: _sliderFinder, matching: find.byType(AbsorbPointer))
          .first,
    )
    .absorbing;

Future<void> _passCommitThrottle(WidgetTester tester) async {
  // Commit throttling uses DateTime.now rather than animation frame time.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 140)),
  );
}

final class _Seek {
  _Seek(this.index);
  final int index;
  final result = Completer<void>();
  void complete({bool fail = false}) {
    if (result.isCompleted) return;
    if (fail) {
      result.completeError(StateError('controlled seek failure'));
    } else {
      result.complete();
    }
  }
}

class _GatedCapability extends ReaderCapability {
  _GatedCapability({required this.recorder, this.revision = 0});
  final _Recorder recorder;
  final int revision;
  final seeks = <_Seek>[];

  @override
  ContinuousImageDiagnosticRecorder get diagnosticRecorder => recorder;
  @override
  String? get imageReferer => null;
  @override
  ReaderContent get content => ReaderContent(
    ownerId: 'seek-owner',
    sessionRevision: revision,
    items: List.generate(
      8,
      (index) => ContinuousImageItem(
        ownerId: 'seek-owner',
        id: 'seek-owner:$index',
        url: 'https://img.test/$index.jpg',
        cacheKey: 'seek/$index',
        index: index,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        knownWidth: 200,
        knownHeight: 300,
      ),
    ),
  );
  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) =>
      const ReaderTitleSpec(title: 'seek fixture');
  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) =>
      ColoredBox(
        key: ValueKey('seek-image-${spec.index}'),
        color: Colors.black,
      );
  @override
  Future<void> onSeek({required int index, required double offset}) {
    final seek = _Seek(index);
    seeks.add(seek);
    return seek.result.future;
  }

  @override
  ImageCacheRequest cacheRequestFor(ContinuousImageItem item) =>
      ImageCacheRequest(
        cacheKey: item.cacheKey,
        sourceUrl: item.url,
        ownerType: ImageCacheOwnerType.thread,
        ownerId: item.ownerId,
        role: ImageCacheRole.threadInline,
        imageIndex: item.index,
        retentionClass: ImageRetentionClass.recentReader,
      );
  void completePending() {
    for (final seek in seeks) {
      seek.complete();
    }
  }
}

class _Recorder implements ContinuousImageDiagnosticRecorder {
  final events = <ContinuousImageDiagnosticEvent>[];
  @override
  bool get enabled => true;
  @override
  void recordContinuousImage(ContinuousImageDiagnosticEvent event) =>
      events.add(event);
  Iterable<ContinuousImageDiagnosticEvent> reached(int target) => events.where(
    (event) =>
        event.type == ContinuousImageDiagnosticEventType.seekReached &&
        event.targetIndex == target,
  );
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
