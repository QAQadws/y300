import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/emphasis_allocation_fixture.dart';

ForumBodyEmphasisParagraphMetrics _paragraph({
  String? body,
  double width = 1,
  TextDirection direction = TextDirection.ltr,
}) {
  final f = body == null
      ? EmphasisAllocationFixture(width: width, direction: direction)
      : EmphasisAllocationFixture(
          body: body,
          width: width,
          direction: direction,
        );
  final job = ForumBodyEmphasisParagraphPreparation(
    content: f.glyphs.original,
    cache: f.cache,
    ensureOwner: () {},
    width: width,
  );
  addTearDown(job.close);
  for (var n = 0; !job.isReady && n < 200000; n++) {
    job.advance(maxParts: 1);
  }
  expect(job.isReady, isTrue);
  final result = job.takeMetrics();
  f.cache.close();
  return result;
}

ForumBodyEmphasisFragmentInput _fragment(
  ForumBodyEmphasisParagraphMetrics plan, {
  int? start,
  int? end,
}) {
  final job = ForumBodyEmphasisFragmentInputPreparation(
    paragraph: plan,
    startLine: start ?? 0,
    endLine: end ?? plan.lines.length,
    ensureOwner: () {},
  );
  addTearDown(job.close);
  var parts = 0;
  while (!job.isReady) {
    expect(job.advance(maxParts: 1), 1);
    parts++;
  }
  final result = job.takeInput();
  expect(parts, greaterThan(result.pictureInput.commands.length));
  return result;
}

ForumBodyParagraphLineFrames _frames(ForumBodyParagraphLease parent) {
  final job = ForumBodyParagraphLineFramePreparation(
    parent: parent,
    ensureOwner: () {},
  );
  while (!job.isReady) {
    job.advance(maxParts: 1);
  }
  return job.takeFrames();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final width in [1.0, 140.0]) {
      test(
        'selected complete groups keep one local scene $direction width=$width',
        () {
          final plan = _paragraph(direction: direction, width: width);
          final selected = plan.groups
              .getRange(1, plan.groups.length - 1)
              .toList();
          final result = _fragment(
            plan,
            start: selected.first.startLine,
            end: selected.last.endLine,
          );
          expect(result.paragraph, same(plan));
          expect(result.coverageStartUtf16, selected.first.startUtf16);
          expect(result.coverageEndUtf16, selected.last.endUtf16);
          expect(result.visibleHandleCount, 2);
          var index = 0;
          for (final group in selected) {
            final delta = Offset(0, group.top - result.selection.top);
            for (final original in group.sceneInput.pictureInput.commands) {
              final actual = result.pictureInput.commands[index++];
              expect(actual.offset, original.offset + delta);
              expect(
                actual.nativeInputIdentity,
                same(original.nativeInputIdentity),
              );
              expect(actual.physicalLine, same(original.physicalLine));
              expect(actual.paragraphRow, original.paragraphRow);
              expect(actual.fitScale, original.fitScale);
            }
          }
          expect(index, result.pictureInput.commands.length);
          expect(
            result.height,
            closeTo(selected.fold<double>(0, (n, g) => n + g.height), 1e-8),
          );
          if (selected.length > 1) {
            expect(
              result.pictureInput.estimatedBytes,
              lessThan(
                selected.fold<int>(
                  0,
                  (n, g) => n + g.sceneInput.pictureInput.estimatedBytes,
                ),
              ),
            );
          }
        },
      );
    }
  }
  test('four groups share five native fonts and ONE scene budget entry', () {
    final fragment = _fragment(_paragraph(body: 'AAAA'));
    final cache = ForumBodyParagraphCache(
      maxEntries: 6,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
    final probe = cache.createBudgetProbe(captureInputEstimates: true);
    try {
      for (final slot in fragment.nativeFootprint) {
        slot.request.includeBudget(
          probe,
          width: slot.width,
          textScaler: fragment.paragraph.textScaler,
          minimumLineCount: slot.minimumLineCount,
        );
      }
      probe.includeTextPicture(fragment.pictureInput);
      expect(probe.snapshotNativeEstimates(), hasLength(6));
    } finally {
      probe.close();
    }
    expect(cache.layoutBuildCount, 0);
    expect(cache.pictureBuildCount, 0);
    expect(cache.activeLeases, 0);
  });

  for (final direction in TextDirection.values) {
    test(
      'one merged picture matches independent allocated views $direction',
      () async {
        final plan = _paragraph(body: 'AAAA', direction: direction),
            fragment = _fragment(plan);
        final cache = ForumBodyParagraphCache(
          maxEntries: 6,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(cache.close);
        final paints = plan.groups.first.allocation.paintInput;
        final parents = [
          for (final content in [
            paints.background,
            paints.foreground,
            paints.decoration,
          ])
            cache.acquire(
              content: content,
              width: plan.width,
              textScaler: plan.textScaler,
              rowIsolationPitch: plan.reference.rowIsolationPitch,
            ),
        ];
        final rows = <ForumBodyParagraphRowView>[];
        for (final parent in parents) {
          cache.prepareTextPaint(parent);
          final table = _frames(parent);
          for (final group in fragment.groups) {
            final r = ForumBodyParagraphRowPreparation(
              parent: parent,
              startLine: group.startLine,
              ensureOwner: () {},
            );
            while (!r.isReady) {
              r.advance(maxParts: 1);
            }
            final view = ForumBodyParagraphRowView.bind(
              parent: parent,
              metrics: r.takeMetrics(),
              ensureOwner: () {},
            );
            final physical = ForumBodyParagraphPhysicalLinePreparation(
              group: view,
              frames: table,
              ensureOwner: () {},
            );
            while (!physical.isReady) {
              physical.advance(maxParts: 1);
            }
            for (final actual in physical.takeSelectors()) {
              final command = fragment.pictureInput.commands.singleWhere(
                (cmd) =>
                    cmd.nativeInputIdentity == parent.nativeInputIdentity &&
                    cmd.paragraphRow == view.selector &&
                    cmd.physicalLine?.lineIndex == actual.lineIndex,
              );
              expect(command.physicalLine, actual);
            }
            rows.add(view);
          }
        }
        final markerInputs = {
          for (final group in fragment.groups)
            for (final mark in group.allocation.source.marks) mark.input,
        };
        final marks = [
          for (final input in markerInputs)
            cache.acquireEmphasisMark(
              input: input,
              textScaler: plan.textScaler,
            ),
        ];
        final before = cache.pictureBuildCount, handles = cache.activeLeases;
        final scene = ForumBodyTextPicturePreparation(
          cache: cache,
          input: fragment.pictureInput,
          text: const [],
          paragraphRows: rows,
          marks: marks,
          ensureOwner: () {},
        );
        addTearDown(scene.close);
        // Three phase parent aliases are shared across all four row selectors.
        expect(scene.nativeLeases, hasLength(3 + marks.length));
        expect(cache.activeLeases, handles + 3 + marks.length);
        while (!scene.isReady) {
          scene.advance(maxParts: 1);
        }
        final picture = scene.takeLease();
        addTearDown(picture.release);
        expect(cache.pictureBuildCount, before + 1);
        expect(cache.activeLeases, handles + 1);
        final reference = ForumBodyParagraphCache(
          maxEntries: 32,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(reference.close);
        final views = <ForumBodyEmphasisAllocatedLayout>[];
        for (final group in fragment.groups) {
          final job = ForumBodyEmphasisAllocatedPreparation(
            input: group.allocation.source.rowInput!,
            allocation: group.allocation,
            plannedSceneInput: group.sceneInput,
            cache: reference,
            ensureOwner: () {},
            width: plan.width,
            expectedTextScaler: plan.textScaler,
          );
          while (!job.isReady) {
            job.advance(maxParts: 1);
          }
          final view = job.takeLayout();
          views.add(view);
          addTearDown(view.close);
        }
        final captures = <ui.Picture>[];
        addTearDown(() {
          for (final p in captures) {
            p.dispose();
          }
        });
        Future<List<int>> pixels(void Function(Canvas) draw, int dpr) async {
          final recorder = ui.PictureRecorder();
          draw(
            Canvas(recorder)
              ..scale(dpr.toDouble())
              ..translate(25, 25),
          );
          final p = recorder.endRecording();
          captures.add(p);
          final image = await p.toImage(
            220 * dpr,
            (fragment.height.ceil() + 50) * dpr,
          );
          try {
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List().toList();
          } finally {
            image.dispose();
          }
        }

        for (final dpr in [1, 3]) {
          final expected = await pixels((canvas) {
            for (var index = 0; index < views.length; index++) {
              views[index].paint(canvas, Offset(0, plan.groups[index].top));
            }
          }, dpr);
          expect(
            await pixels((canvas) => picture.paint(canvas, Offset.zero), dpr),
            expected,
          );
        }
        picture.release();
        for (final p in parents) {
          p.release();
        }
        for (final m in marks) {
          m.release();
        }
        expect(cache.activeLeases, 0);
      },
    );
  }
  test(
    'interior grapheme cuts, budgets and late owner retirement never publish',
    () {
      final plan = _paragraph(),
          spanning = plan.groups.firstWhere((g) => g.endLine - g.startLine > 1);
      expect(
        () => ForumBodyEmphasisFragmentInputPreparation(
          paragraph: plan,
          startLine: spanning.startLine + 1,
          endLine: spanning.endLine,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      expect(
        () => ForumBodyEmphasisFragmentInputPreparation(
          paragraph: plan,
          startLine: 0,
          endLine: plan.lines.length,
          maxGroups: 1,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyEmphasisParagraphException>()),
      );
      final limited = ForumBodyEmphasisFragmentInputPreparation(
        paragraph: plan,
        startLine: 0,
        endLine: plan.lines.length,
        maxCommands: 1,
        ensureOwner: () {},
      );
      expect(() {
        while (!limited.isReady) {
          limited.advance(maxParts: 1);
        }
      }, throwsArgumentError);
      var active = true;
      final ready = ForumBodyEmphasisFragmentInputPreparation(
        paragraph: plan,
        startLine: 0,
        endLine: plan.lines.length,
        ensureOwner: () {
          if (!active) throw StateError('Retired');
        },
      );
      while (!ready.isReady) {
        ready.advance(maxParts: 1);
      }
      active = false;
      expect(ready.takeInput, throwsStateError);
      final cancelled = ForumBodyEmphasisFragmentInputPreparation(
        paragraph: plan,
        startLine: 0,
        endLine: plan.lines.length,
        ensureOwner: () {},
      );
      cancelled.advance(maxParts: 1);
      cancelled.close();
      expect(cancelled.takeInput, throwsStateError);
    },
  );
}
