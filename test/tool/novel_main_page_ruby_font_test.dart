import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/data/services/flutter_font_runtime_loader.dart';
import 'package:y300/features/fonts/domain/repositories/font_library_repository.dart';
import 'package:y300/features/fonts/domain/services/font_file_validator.dart';
import 'package:y300/features/fonts/domain/services/font_import_picker.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';
import '../features/fonts/test_support/font_test_fixtures.dart';

final class _Picker implements FontImportPicker {
  int calls = 0;
  @override
  Future<FontImportFile?> pickFont() async {
    calls++;
    return FontImportFile(fileName: 'ruby-font.otf', bytes: loadTestCffFont());
  }
}

final class _Fonts implements FontLibraryRepository {
  final _entries = <String, ({ImportedFont font, Uint8List bytes})>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<List<ImportedFont>> listFonts() async => [
    for (final entry in _entries.values) entry.font,
  ];
  @override
  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final font = const FontFileValidator().validate(
      fileName: fileName,
      bytes: bytes,
    );
    _entries[font.id] = (font: font, bytes: Uint8List.fromList(bytes));
    _changes.add(null);
    return font;
  }

  @override
  Future<Uint8List> readFont(String id) async =>
      Uint8List.fromList(_entries[id]!.bytes);
  @override
  Future<void> deleteFont(String id) async {
    _entries.remove(id);
    _changes.add(null);
  }

  @override
  Future<void> dispose() => _changes.close();
}

Object _position(NovelReaderProgressSnapshot snapshot) => (
  snapshot.anchorNodeId,
  snapshot.anchorTextOffset,
  snapshot.anchorFormatVersion,
  snapshot.anchorTextIdentity,
);

List<ForumBodyInlineParagraphView> _visibleInline(
  BuildContext context,
  ProfileReaderObservation observation,
) {
  final target = observation.nativeController!.viewForPage(observation.page!)!;
  final result = <ForumBodyInlineParagraphView>[];
  void collect(Element element) {
    final widget = element.widget;
    if (widget is ForumBodyInlineParagraphSurface && widget.view.isActive) {
      result.add(widget.view);
    }
    element.visitChildElements(collect);
  }

  void findTarget(Element element) {
    if (element.widget.key case ObjectKey(value: final value)
        when identical(value, target)) {
      collect(element);
    } else {
      element.visitChildElements(findTarget);
    }
  }

  context.visitChildElements(findTarget);
  return result;
}

ForumBodyInlineParagraphView _completeInline(
  BuildContext context,
  ProfileReaderObservation observation,
) => _visibleInline(context, observation).firstWhere(
  (view) =>
      view.coverageStartUtf16 == 0 &&
      view.coverageEndUtf16 == view.content.projection.display.text.length &&
      view.content.contexts.any((c) => c.content.projection.text == '12F') &&
      view.content.contexts.any((c) => c.content.projection.text == '345'),
);

Future<Uint8List> _pixels(
  ForumBodyInlineParagraphView view,
  String text,
) async {
  final window = view.content.contexts.singleWhere(
    (c) => c.content.projection.text == text,
  );
  final boxes = view.glyphBoxes(window.startUtf16, window.endUtf16);
  final region = boxes
      .map((b) => b.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..clipRect(
      Rect.fromLTWH(20, 20, region.width, region.height),
      doAntiAlias: false,
    );
  view.paint(canvas, Offset(20 - region.left, 20 - region.top));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (region.width + 40).ceil(),
      (region.height + 40).ceil(),
    );
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  late _Fonts repository;
  late FontLibraryService service;
  setUp(() {
    repository = _Fonts();
    service = FontLibraryService(
      repository: repository,
      runtimeLoader: FlutterFontRuntimeLoader(),
    );
  });
  tearDown(() async {
    service.dispose();
    await repository.dispose();
  });
  setUpAll(() async {
    await (FontLoader('packages/forum_content_renderer/ForumBodyInlineSpace')
          ..addFont(
            rootBundle.load(
              'packages/forum_content_renderer/assets/fonts/inline_space.ttf',
            ),
          ))
        .load();
  });
  testWidgets(
    'real imported font reaches single-level ruby, styles and restored source position',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final picker = _Picker();
      final data = NovelMainPageProfileData();
      // This existing App-owned CFF fixture covers digits and F. The live-device
      // CJK audit uses a real imported CJK font, without shipping that font here.
      const paragraph =
          '<p>Read synthetic body <ruby><rb>'
          '<font face="missing-author-font" color="#a00000"><span style="font-size:22px">12F</span></font>'
          '</rb><rp>(</rp><rt><span style="font-size:9px;color:#007000">345</span></rt><rp>)</rp></ruby>'
          ' and continue to the next paragraph.</p>';
      final identity = data.add(List.filled(32, paragraph).join());
      final args = NovelReaderArgs(
        novelId: identity.novelId,
        episodeId: identity.episodeId,
      );
      final navigator = GlobalKey<NavigatorState>();
      var reader = GlobalKey();
      final ioScope = data.scope(
        MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(),
        ),
      ) as ProviderScope;
      // Font overrides share the I/O scope, so dependent reader providers cannot
      // be instantiated by an ancestor outside the synthetic repository boundary.
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...ioScope.overrides,
              fontLibraryServiceProvider.overrideWithValue(service),
              fontImportPickerProvider.overrideWithValue(picker),
            ],
            child: ioScope.child,
          ),
        );
        Future<void> open() => navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => NovelReaderPage(
              key: reader,
              novelId: args.novelId,
              initialEpisodeId: args.episodeId,
              nativePagination: true,
              nativeIdleScheduler: () async {},
            ),
          ),
        );
        NovelReaderViewState state() => ProviderScope.containerOf(
          reader.currentContext!,
          listen: false,
        ).read(novelReaderControllerProvider(args)).requireValue;
        Future<void> waitUntil(bool Function() accepts) async {
          for (var i = 0; i < 2000; i++) {
            await tester.pump(const Duration(milliseconds: 5));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)),
            );
            if (reader.currentContext case final context?) {
              final observation = observeProfileReader(context, args);
              expect(
                observation.failed,
                isFalse,
                reason: '${observation.nativeController?.error}',
              );
            }
            if (accepts()) return;
          }
          fail('Reader/font UI did not reach the expected current state');
        }

        Future<ProfileReaderObservation> ready() async {
          await waitUntil(() {
            if (reader.currentContext == null) return false;
            final observation = observeProfileReader(
              reader.currentContext!,
              args,
            );
            return observation.ready && observation.complete;
          });
          return observeProfileReader(reader.currentContext!, args);
        }

        Future<void> tap(Key key) async {
          final target = find.byKey(key).hitTestable();
          await waitUntil(() => target.evaluate().isNotEmpty);
          await tester.tap(target);
        }

        var popped = open();
        var observation = await ready();
        expect(observation.count, greaterThan(2));
        observation.overlay!.onRightTap!();
        await waitUntil(() {
          final current = observeProfileReader(reader.currentContext!, args);
          return current.ready &&
              current.businessConfirmed &&
              current.page == 1;
        });
        observation = observeProfileReader(reader.currentContext!, args);
        final before = state().progressSnapshot;
        final anchor = NovelReaderTextAnchor(
          episodeId: args.episodeId,
          nodeId: before.anchorNodeId,
          textOffset: before.anchorTextOffset,
          formatVersion: before.anchorFormatVersion,
          textIdentity: before.anchorTextIdentity,
        );
        expect(anchor.hasCanonicalTextOffset, isTrue);
        final originalController = observation.nativeController!;
        final originalKey = observation.paginationKey;
        final beforeInline = _completeInline(
          reader.currentContext!,
          observation,
        );
        final paragraphText = beforeInline.content.projection.display.text;
        final beforePixels = <String, Uint8List>{};
        for (final text in ['12F', '345']) {
          beforePixels[text] = (await tester.runAsync(
            () => _pixels(beforeInline, text),
          ))!;
        }
        final l10n = AppLocalizations.of(reader.currentContext!);
        observation.overlay!.controller!.showMenu();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(l10n.novelDisplay));
        await waitUntil(
          () => find
              .byKey(const Key('novel-reader-font-selector'))
              .evaluate()
              .isNotEmpty,
        );
        await tap(const Key('novel-reader-font-selector'));
        BodyFontSelector selector() =>
            tester.widget<BodyFontSelector>(find.byType(BodyFontSelector));
        await waitUntil(
          () =>
              find.byType(BodyFontSelector).evaluate().isNotEmpty &&
              selector().controller.canMutate,
        );
        await tap(const Key('body-font-import'));
        await waitUntil(
          () =>
              selector().controller.canConfirm &&
              !selector().controller.selectedFont.isSystem,
        );
        final font = selector().controller.selectedFont;
        expect(picker.calls, 1);
        expect(font.fontFamily, FontIdentity.runtimeFamily(font.id));
        await tap(const Key('body-font-apply'));
        await waitUntil(() => find.byType(BodyFontSelector).evaluate().isEmpty);
        navigator.currentState!
            .pop(); // Dismiss display settings and flush its real coordinator.
        await waitUntil(() {
          final current = observeProfileReader(reader.currentContext!, args);
          return current.ready &&
              current.complete &&
              current.paginationKey != originalKey &&
              state().bodyFont.id == font.id &&
              state().persistedPreferences.fontFamily == font.id;
        });
        observation = observeProfileReader(reader.currentContext!, args);
        expect(state().bodyFont.id, font.id);
        expect(observation.paginationKey, isNot(originalKey));
        expect(originalController.isClosed, isTrue);
        expect(_position(state().progressSnapshot), _position(before));
        final view = observation.nativeController!.viewForPage(
          observation.page!,
        )!;
        expect(view.coverage.locate(anchor), isNotNull);
        expect(view.coverage.hasClippedGlyphs, isFalse);
        final inline = _visibleInline(reader.currentContext!, observation);
        expect(inline, isNotEmpty);
        for (final fragment in inline) {
          expect(
            fragment.content.projection.display.text,
            isNot(contains('(')),
          );
          for (final window in fragment.content.contexts) {
            expect(window.content.style.textStyle.fontFamily, font.fontFamily);
            final text = window.content.projection.text;
            if (text != '12F' && text != '345') continue;
            // Nested spans style actual source runs, not the context's root strut.
            for (final part in window.content.projection.parts) {
              if (part.text.isEmpty) continue;
              final style = window.content.runs[part.runIndex].style.textStyle;
              expect(style.fontFamily, font.fontFamily);
              expect(style.fontSize, text == '12F' ? 22 : 9);
              expect(
                style.color,
                text == '12F'
                    ? const Color(0xffa00000)
                    : const Color(0xff007000),
              );
            }
            for (final box in fragment.glyphBoxes(
              window.startUtf16,
              window.endUtf16,
            )) {
              final hit = fragment.sourceHitAt(box.toRect().center);
              expect(hit.position.isExact, isTrue);
              expect(hit.window, same(window));
            }
          }
        }
        // Compare the actual mounted base and annotation separately. Normalizing
        // each source region removes parent reflow offsets; a family-name check
        // alone would also pass if native shaping silently kept the default face.
        final afterInline = _completeInline(
          reader.currentContext!,
          observation,
        );
        expect(afterInline.content.projection.display.text, paragraphText);
        for (final text in ['12F', '345']) {
          final native = (await tester.runAsync(
            () => _pixels(afterInline, text),
          ))!;
          expect(
            [for (var i = 3; i < native.length; i += 4) native[i]]
                .any((alpha) => alpha > 0),
            isTrue,
          );
          expect(native, isNot(orderedEquals(beforePixels[text]!)));
        }

        final owner = observation.nativeOwner!;
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await popped;
        expect(owner.isClosed, isTrue);
        expect(owner.activeCacheHandles, 0);
        expect(owner.estimatedRetainedBytes, 0);
        reader = GlobalKey();
        popped = open();
        observation = await ready();
        expect(state().bodyFont.id, font.id);
        expect(_position(state().progressSnapshot), _position(before));
        expect(
          observation.nativeController!
              .viewForPage(observation.page!)!
              .coverage
              .locate(anchor),
          isNotNull,
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await popped;
        data.release(args.episodeId);
        expect(data.retainedChapters, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}
