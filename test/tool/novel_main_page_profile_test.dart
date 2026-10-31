import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../tool/novel_main_page_profile_data.dart';
import '../../tool/novel_main_page_profile_observation.dart';

void main() {
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

  for (final native in [false, true]) {
    testWidgets('observes real ${native ? 'native' : 'legacy'} page and exit', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final data = NovelMainPageProfileData();
      final source = data.add(
        List.filled(
          12,
          '<p>Synthetic paragraph for a real visible page. 正文分页。</p>',
        ).join(),
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
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          if (key.currentContext case final context?) {
            final observation = observeProfileReader(context, args);
            expect(observation.failed, isFalse);
            if (accepts(observation)) return observation;
          }
        }
        throw StateError('Profile never observed the mounted page');
      }

      var observation = await wait((value) => value.ready && value.complete);
      expect(observation.count, greaterThan(1));
      expect(observation.businessConfirmed, isTrue);
      final originalKey = observation.paginationKey;
      observation.businessController!.previewPreferences(
        profileReaderPreferences.copyWith(fontSize: 22),
      );
      observation = await wait(
        (value) =>
            value.ready && value.complete && value.paginationKey != originalKey,
      );
      // Read-only reflow may keep the old business key. The tool observes the
      // new mounted layout without asking the reader to confirm a new anchor.
      expect(observation.paginationKey, isNot(originalKey));
      observation.overlay!.onRightTap!();
      observation = await wait(
        (value) => value.ready && value.businessConfirmed && value.page == 1,
      );
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
    });
  }
}
