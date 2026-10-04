import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/reader_shared/presentation/reader_preferences/reader_preferences_provider.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets(
    'rebuild while initial restore waits for layout shares one seek',
    (tester) async {
      final recorder = _Recorder();
      final preferences = _Preferences();
      final active = ValueNotifier(_Capability(recorder, initialIndex: 80));
      addTearDown(active.dispose);
      await tester.pumpWidget(_host(active, preferences));
      await tester.pump();
      expect(recorder.restoreStarted, hasLength(1));
      expect(recorder.restoreCompleted, isEmpty);

      // The target is outside the old lazy viewport. Rebuild the same session
      // before its next layout frame releases the pending correction.
      active.value = _Capability(recorder, initialIndex: 80);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(recorder.restoreStarted, hasLength(1));
      expect(recorder.restoreCompleted, hasLength(1));
      expect(recorder.restoreCompleted.single.status, 'consumed');
      expect(_scroll(tester).offset, closeTo(80 * 800, 0.5));
      expect(tester.getTopLeft(find.byKey(const Key('image-80'))).dy, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('slider retires a restore waiting for its correction frame', (
    tester,
  ) async {
    final recorder = _Recorder();
    final preferences = _Preferences();
    final capability = _Capability(recorder, initialIndex: 80);
    final active = ValueNotifier(capability);
    addTearDown(active.dispose);
    await tester.pumpWidget(_host(active, preferences));
    await tester.pump();
    expect(recorder.restoreStarted, hasLength(1));
    expect(recorder.restoreCompleted, isEmpty);
    final progress = tester
        .widget<ReaderOverlayScaffold>(find.byType(ReaderOverlayScaffold))
        .bottomBar
        .progress!;
    progress.onChangeStart?.call(2);
    progress.onChanged(2);
    progress.onChangeEnd(2);

    await tester.pumpAndSettle();
    expect(capability.seeks, [2]);
    expect(recorder.restoreStarted, hasLength(1));
    expect(recorder.restoreCompleted, isEmpty);
    expect(recorder.reached(2), hasLength(1));
    expect(_scroll(tester).offset, closeTo(2 * 800, 0.5));
    expect(tester.getTopLeft(find.byKey(const Key('image-2'))).dy, 0);
    expect(tester.takeException(), isNull);
  });

  for (final exit in [false, true]) {
    testWidgets(
      'mode persistence completed after ${exit ? 'exit' : 'same-owner refresh'} cannot resume old positioning',
      (tester) async {
        final recorder = _Recorder();
        final preferences = _Preferences(gateSaves: true);
        addTearDown(preferences.completeSave);
        final first = _Capability(recorder, initialIndex: 3);
        final active = ValueNotifier(first);
        addTearDown(active.dispose);
        await tester.pumpWidget(_host(active, preferences));
        await tester.pumpAndSettle();
        expect(_scroll(tester).offset, closeTo(3 * 800, 0.5));

        first.actions!.cycleReaderMode();
        await tester.pumpAndSettle();
        expect(preferences.saved.single.readerMode, ReaderModePreference.ltr);
        expect(preferences.saveGate.isCompleted, isFalse);
        expect(recorder.modePositioning, isEmpty);

        if (exit) {
          await tester.pumpWidget(const SizedBox.shrink());
          expect(first.exitCalls, 1);
        } else {
          active.value = _Capability(recorder, revision: 1, initialIndex: 6);
          await tester.pumpAndSettle();
          expect(_page(tester), closeTo(6, 0.01));
          expect(active.value.latestContext!.currentIndex, 6);
        }
        final eventsBeforeSave = recorder.events.length;
        preferences.completeSave();
        await tester.pumpAndSettle();
        expect(recorder.events, hasLength(eventsBeforeSave));
        expect(recorder.modePositioning, isEmpty);
        expect(first.seeks, isEmpty);
        if (!exit) {
          expect(_page(tester), closeTo(6, 0.01));
          expect(active.value.latestContext!.currentIndex, 6);
          expect(active.value.seeks, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

ScrollController _scroll(WidgetTester tester) => tester
    .widget<ListView>(find.byKey(const Key('restore-lifecycle-list')))
    .controller!;

double? _page(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page;

Widget _host(ValueNotifier<_Capability> active, _Preferences preferences) =>
    ProviderScope(
      overrides: [
        readerPreferencesRepositoryProvider.overrideWithValue(preferences),
        forumImagePrecacheServiceProvider.overrideWithValue(_Precache()),
      ],
      child: LocalizedTestApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: Consumer(
            builder: (context, ref, child) {
              if (ref.watch(readerPreferencesControllerProvider).value ==
                  null) {
                return const SizedBox.shrink();
              }
              return ValueListenableBuilder<_Capability>(
                valueListenable: active,
                builder: (_, capability, _) => ImageReaderEngine(
                  capability: capability,
                  listKey: const Key('restore-lifecycle-list'),
                ),
              );
            },
          ),
        ),
      ),
    );

class _Capability extends ReaderCapability {
  _Capability(this.recorder, {this.revision = 0, this.initialIndex = 0});
  final _Recorder recorder;
  final int revision;
  final int initialIndex;
  final seeks = <int>[];
  ReaderEngineActions? actions;
  ReaderEngineContext? latestContext;
  int exitCalls = 0;

  @override
  ContinuousImageDiagnosticRecorder get diagnosticRecorder => recorder;
  @override
  String? get imageReferer => null;
  @override
  ReaderContent get content => ReaderContent(
    ownerId: 'restore-owner',
    sessionRevision: revision,
    initialIndex: initialIndex,
    items: List.generate(
      100,
      (index) => ContinuousImageItem(
        ownerId: 'restore-owner',
        id: 'restore-owner:$index',
        url: 'https://img.test/$index.jpg',
        cacheKey: 'restore/$index',
        index: index,
        sourceKind: ContinuousImageSourceKind.threadImageReader,
        knownWidth: 100,
        knownHeight: 100,
      ),
    ),
  );
  @override
  ReaderTitleSpec titleFor(ReaderEngineContext context) {
    actions = context.actions;
    latestContext = context;
    return const ReaderTitleSpec(title: 'restore fixture');
  }

  @override
  Widget buildImageContent(BuildContext context, ReaderImageBuildSpec spec) =>
      ColoredBox(key: Key('image-${spec.index}'), color: Colors.black);
  @override
  Future<void> onSeek({required int index, required double offset}) async {
    seeks.add(index);
  }

  @override
  Future<void> onExit() async {
    exitCalls += 1;
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
      );
}

class _Recorder implements ContinuousImageDiagnosticRecorder {
  final events = <ContinuousImageDiagnosticEvent>[];
  @override
  bool get enabled => true;
  @override
  void recordContinuousImage(ContinuousImageDiagnosticEvent event) =>
      events.add(event);
  Iterable<ContinuousImageDiagnosticEvent> get restoreStarted => events.where(
    (event) =>
        event.type == ContinuousImageDiagnosticEventType.initialRestoreStarted,
  );
  Iterable<ContinuousImageDiagnosticEvent> get restoreCompleted => events.where(
    (event) =>
        event.type ==
        ContinuousImageDiagnosticEventType.initialRestoreCompleted,
  );
  Iterable<ContinuousImageDiagnosticEvent> reached(int index) => events.where(
    (event) =>
        event.type == ContinuousImageDiagnosticEventType.seekReached &&
        event.targetIndex == index,
  );
  Iterable<ContinuousImageDiagnosticEvent> get modePositioning =>
      events.where((event) => event.status == 'modeSwitch');
}

class _Preferences implements ReaderPreferencesRepository {
  _Preferences({this.gateSaves = false});
  final bool gateSaves;
  final saved = <ReaderPreferences>[];
  final saveGate = Completer<void>();

  @override
  Future<ReaderPreferences> load() async => ReaderPreferences.defaults()
      .copyWith(readerMode: ReaderModePreference.vertical, pageSpacing: 0);
  @override
  Future<void> save(ReaderPreferences preferences) async {
    saved.add(preferences);
    if (gateSaves) await saveGate.future;
  }

  void completeSave() {
    if (!saveGate.isCompleted) saveGate.complete();
  }
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
