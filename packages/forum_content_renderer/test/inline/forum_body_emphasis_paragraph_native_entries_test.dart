import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/emphasis_allocation_fixture.dart';

ForumBodyEmphasisParagraphMetrics _paragraph({String? body, double width = 1}) {
  final fixture = body == null
      ? EmphasisAllocationFixture(width: width)
      : EmphasisAllocationFixture(width: width, body: body);
  final job = ForumBodyEmphasisParagraphPreparation(
    content: fixture.glyphs.original,
    cache: fixture.cache,
    ensureOwner: () {},
    width: width,
  );
  while (!job.isReady) {
    job.advance(maxParts: 32);
  }
  final result = job.takeMetrics();
  fixture.cache.close();
  return result;
}

ForumBodyParagraphCache _cache([int count = 32]) {
  final cache = ForumBodyParagraphCache(
    maxEntries: count,
    maxEstimatedBytes: 1 << 25,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyEmphasisParagraphNativeEntries _finish(
  ForumBodyEmphasisParagraphNativeEntriesPreparation job,
) {
  addTearDown(job.close);
  for (var n = 0; !job.isReady && n < 200000; n++) {
    expect(job.advance(maxParts: 1), 1);
  }
  expect(job.isReady, isTrue);
  return job.take();
}

ForumBodyEmphasisFragmentInput _fragment(
  ForumBodyEmphasisParagraphMetrics plan,
  int from,
  int to,
) {
  final job = ForumBodyEmphasisFragmentInputPreparation(
    paragraph: plan,
    startLine: from,
    endLine: to,
    ensureOwner: () {},
  );
  while (!job.isReady) {
    job.advance(maxParts: 32);
  }
  return job.takeInput();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  test(
    'indexed contributions equal exact single merged scene admission for every prefix',
    () {
      final plan = _paragraph(),
          cache = _cache(),
          entries = _finish(
            ForumBodyEmphasisParagraphNativeEntriesPreparation(
              paragraph: plan,
              cache: cache,
              ensureOwner: () {},
            ),
          );
      expect(entries.paragraph, same(plan));
      expect(entries.groups, hasLength(plan.groups.length));
      expect(
        (
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.hitCount,
          cache.activeLeases,
        ),
        (0, 0, 0, 0),
      );
      for (var first = 0; first < plan.groups.length; first++) {
        var inputBytes = ForumBodyTextPictureInput.baseEstimatedInputBytes,
            pictureBytes = ForumBodyTextPictureInput.baseEstimatedPictureBytes,
            commandCount = 0;
        final metadata = <Object, int>{};
        for (var after = first + 1; after <= plan.groups.length; after++) {
          final contribution = entries.groups[after - 1],
              group = contribution.group;
          expect(group, same(plan.groups[after - 1]));
          commandCount += contribution.commandCount;
          final translated = group.top != plan.groups[first].top;
          inputBytes +=
              contribution.inputCommandBytes +
              (translated
                  ? contribution.commandCount *
                        ForumBodyTextPictureCommand
                            .translationInputEstimatedBytes
                  : 0);
          pictureBytes +=
              contribution.pictureCommandBytes +
              (translated
                  ? contribution.commandCount *
                        ForumBodyTextPictureCommand
                            .translationPictureEstimatedBytes
                  : 0);
          for (final entry in contribution.retainedMetadata.entries) {
            if (!metadata.containsKey(entry.key)) {
              metadata[entry.key] = entry.value;
              inputBytes += entry.value;
            }
          }
          final actual = _fragment(
            plan,
            plan.groups[first].startLine,
            group.endLine,
          );
          expect(inputBytes, actual.pictureInput.estimatedInputBytes);
          expect(pictureBytes, actual.pictureInput.estimatedPictureBytes);
          expect(commandCount, actual.pictureInput.commands.length);
          final fonts = <Object, int>{};
          for (final cost in entries.fontCostsInLines(
            plan.groups[first].startLine,
            group.endLine,
          )) {
            fonts[cost.identity] = cost.estimatedBytes;
          }
          final probe = cache.createBudgetProbe(captureInputEstimates: true);
          try {
            for (final slot in actual.nativeFootprint) {
              slot.request.includeBudget(
                probe,
                width: slot.width,
                textScaler: plan.textScaler,
                minimumLineCount: slot.minimumLineCount,
              );
            }
            expect(fonts, {
              for (final item in probe.snapshotNativeEstimates())
                item.identity: item.estimatedBytes,
            });
          } finally {
            probe.close();
          }
        }
      }
      cache.close();
      expect(entries.groups.first.fonts, isNotEmpty);
      expect(() => entries.groups.clear(), throwsUnsupportedError);
      expect(
        () => entries.groups.first.retainedMetadata.clear(),
        throwsUnsupportedError,
      );
      expect(() => entries.groups.first.fonts.clear(), throwsUnsupportedError);
      expect(
        () => ForumBodyTextPictureInput.estimateRetainedMetadataBytesFor(
          Object(),
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'different page marker styles do not aggregate into one chapter-wide budget',
    () {
      final plan = _paragraph(
            body: [
              for (var n = 0; n < 12; n++)
                '<span style="font-size:${20 + n}px">A</span>',
            ].join(),
          ),
          cache = _cache(5);
      final entries = _finish(
        ForumBodyEmphasisParagraphNativeEntriesPreparation(
          paragraph: plan,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      expect(entries.groups, hasLength(12));
      expect(entries.groups.every((g) => g.fonts.length == 5), isTrue);
      expect(
        entries
            .fontCostsInLines(0, plan.lines.length)
            .map((c) => c.identity)
            .toSet()
            .length,
        4 + 12,
      );
      final impossible = cache.createBudgetProbe();
      try {
        expect(() {
          for (final slot in plan.nativeFootprintFor(0, plan.lines.length)) {
            slot.request.includeBudget(
              impossible,
              width: slot.width,
              textScaler: plan.textScaler,
              minimumLineCount: slot.minimumLineCount,
            );
          }
        }, throwsA(isA<ForumBodyParagraphBudgetException>()));
      } finally {
        impossible.close();
      }
      expect(
        cache.layoutBuildCount + cache.pictureBuildCount + cache.hitCount,
        0,
      );
    },
  );
  test(
    'legal line ranges include a zero-text terminal group and reject interior graphemes',
    () {
      final plan = _paragraph(),
          cache = _cache(),
          entries = _finish(
            ForumBodyEmphasisParagraphNativeEntriesPreparation(
              paragraph: plan,
              cache: cache,
              ensureOwner: () {},
            ),
          );
      final spanning = plan.groups.firstWhere(
        (g) => g.endLine - g.startLine > 1,
      );
      expect(
        () => entries.inLines(spanning.startLine + 1, spanning.endLine),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      final terminalPlan = _paragraph(body: 'A\n', width: 140);
      expect(terminalPlan.hasTerminalEmptyLine, isTrue);
      final terminalEntries = _finish(
        ForumBodyEmphasisParagraphNativeEntriesPreparation(
          paragraph: terminalPlan,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      final last = terminalEntries
          .inLines(
            terminalPlan.groups.last.startLine,
            terminalPlan.lines.length,
          )
          .single;
      expect(last.group.startUtf16, last.group.endUtf16);
      expect(last.commandCount, 3);
      expect(last.fonts, hasLength(4));
    },
  );
  test(
    'own budget rejection, owner retirement, reentry and explicit cancellation retain no resources',
    () {
      final plan = _paragraph(body: 'AAAA'), limited = _cache(4);
      final job = ForumBodyEmphasisParagraphNativeEntriesPreparation(
        paragraph: plan,
        cache: limited,
        ensureOwner: () {},
      );
      expect(
        () => _finish(job),
        throwsA(isA<ForumBodyParagraphBudgetException>()),
      );
      expect(limited.activeLeases, 0);
      final cache = _cache();
      var active = true;
      final ready = ForumBodyEmphasisParagraphNativeEntriesPreparation(
        paragraph: plan,
        cache: cache,
        ensureOwner: () {
          if (!active) throw StateError('Retired');
        },
      );
      while (!ready.isReady) {
        ready.advance(maxParts: 32);
      }
      active = false;
      expect(ready.take, throwsStateError);
      final cancelled = ForumBodyEmphasisParagraphNativeEntriesPreparation(
        paragraph: plan,
        cache: cache,
        ensureOwner: () {},
      );
      cancelled.advance(maxParts: 1);
      cancelled.close();
      expect(cancelled.take, throwsStateError);
      late ForumBodyEmphasisParagraphNativeEntriesPreparation reentrant;
      var check = false;
      reentrant = ForumBodyEmphasisParagraphNativeEntriesPreparation(
        paragraph: plan,
        cache: cache,
        ensureOwner: () {
          if (check) reentrant.advance();
        },
      );
      check = true;
      expect(reentrant.advance, throwsStateError);
      expect(
        cache.layoutBuildCount + cache.pictureBuildCount + cache.hitCount,
        0,
      );
      expect(cache.activeLeases, 0);
    },
  );
  test(
    'a pure empty paragraph has no manufactured row or picture contribution',
    () {
      final plan = _paragraph(body: ''),
          cache = _cache(),
          entries = _finish(
            ForumBodyEmphasisParagraphNativeEntriesPreparation(
              paragraph: plan,
              cache: cache,
              ensureOwner: () {},
            ),
          );
      expect(entries.groups, isEmpty);
      expect(cache.activeLeases, 0);
      expect(cache.layoutBuildCount + cache.pictureBuildCount, 0);
    },
  );
}
