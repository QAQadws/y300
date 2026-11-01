import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';
import '../../tool/novel_pagination_profile_fixtures.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('packages/forum_content_renderer/ForumBodyInlineSpace')
          ..addFont(
            rootBundle.load(
              'packages/forum_content_renderer/assets/fonts/inline_space.ttf',
            ),
          ))
        .load();
  });
  test(
    'corpus selection keeps baseline identity and rejects missing matrices',
    () {
      expect(
        novelMainPageProfileFixtures('baseline'),
        same(novelProfileFixtures),
      );
      expect(
        novelMainPageProfileFixtures('ruby-gaps'),
        same(novelProfileRubyGapFixtures),
      );
      expect(novelProfileRubyGapFixtures.map((f) => f.name), [
        'ruby-gaps-ltr',
        'ruby-gaps-rtl',
        'ruby-gaps-dense',
      ]);
      expect(() => novelMainPageProfileFixtures(''), throwsArgumentError);
      expect(
        () => novelMainPageProfileFixtures('ruby-gap'),
        throwsArgumentError,
      );
    },
  );
  test(
    'visibility requires business agreement and an uncovered settled page',
    () {
      bool accepts({
        int? mountedPage = 1,
        int businessPage = 1,
        String? mountedKey = 'key',
        String? businessKey = 'key',
        bool covered = false,
        bool pending = false,
        bool routeSettled = true,
      }) => profileVisiblePageAccepted(
        mountedPage: mountedPage,
        pageCount: 3,
        businessPage: businessPage,
        mountedKey: mountedKey,
        businessKey: businessKey,
        covered: covered,
        pending: pending,
        routeSettled: routeSettled,
      );
      expect(accepts(), isTrue);
      expect(accepts(mountedPage: null), isFalse);
      expect(accepts(mountedPage: 3), isFalse);
      expect(accepts(businessPage: 0), isFalse);
      expect(accepts(mountedKey: null, businessKey: null), isFalse);
      expect(accepts(businessKey: 'old'), isFalse);
      expect(accepts(covered: true), isFalse);
      expect(accepts(pending: true), isFalse);
      expect(accepts(routeSettled: false), isFalse);
    },
  );

  test(
    'cold opens use unique identities and release all synthetic rows',
    () async {
      final data = NovelMainPageProfileData();
      final first = data.add('<p>First</p>');
      final second = data.add('<p>Second</p>');
      expect(first, isNot(second));
      expect(data.retainedChapters, 2);
      expect(
        (await data.getChapterContent(episodeId: first.episodeId))?.plainText,
        'First',
      );
      data.release(first.episodeId);
      expect(await data.getChapterContent(episodeId: first.episodeId), isNull);
      data.release(second.episodeId);
      expect(data.retainedChapters, 0);
    },
  );

  test('tiny dense profile remains an explicit issued-handle failure', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 64,
      maxEstimatedBytes: 1 << 24,
    );
    final session = ForumBodyTextPageSession(
      document: const ForumBodyParser().parse(
        html: novelProfileRubyGapOverflowHtml,
        sourceId: 'profile-gap-overflow',
        conversionIdentity: 'none',
      ),
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 18.5,
          height: 1.6,
        ),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
        paragraphBefore: 0,
        paragraphAfter: 12,
      ),
      cache: cache,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 100,
        maxFragments: 1000,
        maxParagraphs: 100,
        maxTextCodeUnits: 100000,
        maxRuns: 10000,
        maxIssuedLeases: 512,
      ),
      layoutId: 'profile-gap-overflow',
      width: 320,
      height: 560,
    );
    try {
      for (var i = 0; !session.isComplete && i < 100000; i++) {
        final builds = cache.layoutBuildCount;
        session.advance(maxEvents: 1, maxLines: 1);
        expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
      }
      expect(session.isComplete, isTrue);
      final prefix = session.snapshot.first;
      expect(
        () => session.openPagePreparation(0),
        throwsA(
          isA<ForumBodyTextPageSessionException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageSessionFailure.leaseLimit,
          ),
        ),
      );
      expect(session.snapshot.first, same(prefix));
      expect(session.activeIssuedLeases, 0);
      expect(cache.activeLeases, 0);
    } finally {
      session.close();
      cache.close();
      expect(cache.estimatedRetainedBytes, 0);
    }
  });

  for (final scenario in [
    (native: false, mixed: false, gap: null),
    (native: true, mixed: false, gap: null),
    (native: true, mixed: true, gap: null),
    for (final fixture in novelProfileRubyGapFixtures)
      (native: true, mixed: true, gap: fixture),
  ]) {
    final native = scenario.native;
    testWidgets(
      'observes real ${native ? 'native' : 'legacy'} page and exit (mixed=${scenario.mixed}, gap=${scenario.gap?.name})',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final data = NovelMainPageProfileData();
        final source = data.add(
          scenario.gap?.html ??
              (scenario.mixed
                  ? novelProfileComplexHtml
                  : List.filled(
                      12,
                      '<p>Synthetic paragraph for a real visible page. 正文分页。</p>',
                    ).join()),
        );
        final args = NovelReaderArgs(
          novelId: source.novelId,
          episodeId: source.episodeId,
        );
        final navigator = GlobalKey<NavigatorState>();
        final key = GlobalKey();
        await tester.pumpWidget(
          data.scope(
            MaterialApp(
              navigatorKey: navigator,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(),
            ),
          ),
        );
        unawaitedPush() => navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => NovelReaderPage(
              key: key,
              novelId: source.novelId,
              initialEpisodeId: source.episodeId,
              nativePagination: native,
              nativeIdleScheduler: () async {},
            ),
          ),
        );
        // The returned route future completes only after popping it.
        final popped = unawaitedPush();
        Future<ProfileReaderObservation> wait(
          bool Function(ProfileReaderObservation) accepts,
        ) async {
          for (var i = 0; i < (scenario.gap == null ? 200 : 3000); i++) {
            // Native work slices use real Stopwatch time. Do not turn every
            // short yield into 20 ms of fake stall under parallel tester load.
            // Performance and recovery deadlines use the real profile suite.
            await tester.pump(
              Duration(milliseconds: scenario.gap == null ? 20 : 1),
            );
            if (scenario.mixed) {
              // The production large-chapter executor uses Isolate.run, whose
              // result needs real event-loop time outside FakeAsync frames.
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 1)),
              );
            }
            if (key.currentContext case final context?) {
              final observation = observeProfileReader(context, args);
              expect(
                observation.failed,
                isFalse,
                reason: find
                    .byType(NovelReaderNativePagedViewport)
                    .evaluate()
                    .map(
                      (element) =>
                          (element.widget as NovelReaderNativePagedViewport)
                              .controller
                              .error,
                    )
                    .join(', '),
              );
              if (accepts(observation)) return observation;
            }
          }
          final observation = observeProfileReader(key.currentContext!, args);
          final controllers = find
              .byType(NovelReaderNativePagedViewport)
              .evaluate()
              .map(
                (element) => (element.widget as NovelReaderNativePagedViewport)
                    .controller,
              );
          throw StateError(
            'Profile never observed the mounted page: '
            'ready=${observation.ready} complete=${observation.complete} '
            'page=${observation.page} count=${observation.count} '
            'business=${observation.businessConfirmed} '
            '${controllers.map((controller) => '${controller.phase}/${controller.error}/target:${controller.readyTarget != null}').join(', ')}',
          );
        }

        var observation = await wait((value) => value.ready && value.complete);
        expect(observation.count, greaterThan(1));
        expect(observation.businessConfirmed, isTrue);
        if (native) {
          expect(observation.nativeWork, isNotNull);
          expect(observation.nativeController, isNotNull);
          expect(
            observation.nativeController!.viewForPage(observation.page!)!.work,
            same(observation.nativeWork),
          );
          expect(observation.nativeWork!.preparationFrames, greaterThan(0));
        }
        final originalKey = observation.paginationKey;
        observation.businessController!.previewPreferences(
          profileReaderPreferences.copyWith(fontSize: 22),
        );
        observation = await wait(
          (value) =>
              value.ready &&
              value.complete &&
              value.paginationKey != originalKey,
        );
        // Read-only reflow may keep the old business key. The tool observes the
        // new mounted layout without asking the reader to confirm a new anchor.
        expect(observation.paginationKey, isNot(originalKey));
        for (final page in scenario.gap == null ? [1] : [1, 2, 3, 2, 1]) {
          (page > observation.page!
              ? observation.overlay!.onRightTap!
              : observation.overlay!.onLeftTap!)();
          observation = await wait(
            (value) =>
                value.ready && value.businessConfirmed && value.page == page,
          );
        }
        final owner = observation.nativeOwner;
        final legacyReleased = observation.legacyCachesReleased;
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        await popped;
        expect(key.currentContext, isNull);
        if (native) {
          expect(owner!.isClosed, isTrue);
          expect(owner.activeCacheHandles, 0);
          expect(owner.estimatedRetainedBytes, 0);
        } else {
          expect(legacyReleased!(), isTrue);
        }
        data.release(source.episodeId);
        expect(data.retainedChapters, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
