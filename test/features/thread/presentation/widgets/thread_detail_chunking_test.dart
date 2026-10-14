import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/contracts/thread_body_reading_observer.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_coordinator.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_post_html_selection_copy_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projection.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  for (final paragraphs in [false, true]) {
    testWidgets(
      '3000 ${paragraphs ? 'P' : 'TextBR'} units mount nearby chunks and release them across scrolling',
      (tester) async {
        final host = _Host([
          _post('long', _html(3000, paragraphs: paragraphs), 1),
        ]);
        addTearDown(host.dispose);
        await _mount(tester, host);
        await _ready(tester, 'unit[0]');
        final firstRenderers = _renderers(tester, 'long');
        expect(firstRenderers, isNotEmpty);
        expect(
          firstRenderers.every(
            (renderer) =>
                renderer.html.length < host.posts.first.message.length,
          ),
          isTrue,
        );
        expect(_units(tester).length, lessThan(3000));
        final firstElements = _rendererElements(tester, 'long');
        await _tail(tester, host, 'unit[2999]');
        expect(
          find.byKey(const Key('thread-post-footer-entry-long')),
          findsWidgets,
        );
        expect(_units(tester), contains(2999));
        expect(firstElements.every((element) => !element.mounted), isTrue);
        expect(_units(tester).length, lessThan(3000));
        final tailElements = _rendererElements(tester, 'long');
        host.controller.jumpTo(0);
        await _ready(tester, 'unit[0]');
        expect(tailElements.every((element) => !element.mounted), isTrue);
        expect(_units(tester), contains(0));
        expect(_units(tester).length, lessThan(3000));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final floorCount in [1, 2]) {
    testWidgets(
      'quick endpoints reach real pagination and first floor with $floorCount safe long bodies',
      (tester) async {
        final host = _Host([
          for (var index = 0; index < floorCount; index++)
            _post(
              'long-$index',
              _html(3000, paragraphs: floorCount == 2, prefix: '$index-'),
              index + 1,
            ),
        ], quickScrolling: true);
        addTearDown(host.dispose);
        await _mount(tester, host);
        await _ready(tester, '0-unit[0]');
        await _tail(tester, host, '${floorCount - 1}-unit[2999]');
        final tailElements = _rendererElements(
          tester,
          'long-${floorCount - 1}',
        );
        expect(tailElements, isNotEmpty);
        expect(host.visibleTargets, isEmpty);

        host.quickCoordinator.updateUserDirection(ScrollDirection.forward);
        final observed = await _quickNavigate(tester, host, animate: false);
        expect(_atFirstFloor(tester, 'long-0'), isTrue);
        expect(_visibleMarker(tester, 'long-0', 0), isTrue);
        expect(tailElements.every((element) => !element.mounted), isTrue);
        // Sixty-three blocks per floor exist; endpoint navigation should only
        // demand blocks near its source and destination, not the whole prefix.
        expect(observed.length, lessThan(20));
        expect(_units(tester).length, lessThan(1000));
        expect(host.navigationStarts, 1);
        expect(host.confirmedOffsets, hasLength(1));

        host.quickCoordinator.updateUserDirection(ScrollDirection.reverse);
        await _quickNavigate(tester, host, animate: false);
        expect(_atPaginationEnd(tester), isTrue);
        expect(_visibleMarker(tester, 'long-${floorCount - 1}', 2999), isTrue);
        expect(host.navigationStarts, 2);
        expect(host.confirmedOffsets, hasLength(2));

        host.quickCoordinator.updateUserDirection(ScrollDirection.forward);
        await _quickNavigate(tester, host, animate: true);
        expect(
          _atFirstFloor(tester, 'long-0'),
          isTrue,
          reason: _endpointGeometry(tester, host, 'long-0'),
        );
        expect(host.confirmedOffsets, hasLength(3));
        host.quickCoordinator.updateUserDirection(ScrollDirection.reverse);
        await _quickNavigate(tester, host, animate: true);
        expect(_atPaginationEnd(tester), isTrue);
        expect(host.confirmedOffsets, hasLength(4));
        expect(host.visibleTargets, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final retirement in [
    'cancel',
    'page',
    'content',
    'theme',
    'themeFade',
    'fontScale',
  ]) {
    testWidgets('quick endpoint $retirement retires its pending navigation', (
      tester,
    ) async {
      final host = _Host(
        [_post('long', _html(3000, prefix: 'old-'), 1)],
        quickScrolling: true,
        themeAnimationDuration: retirement == 'theme'
            ? Duration.zero
            : const Duration(milliseconds: 200),
      );
      addTearDown(host.dispose);
      try {
        await _mount(tester, host);
        await _ready(tester, 'old-unit[0]');
        final changesLayout =
            retirement == 'theme' || retirement == 'fontScale';
        if (!changesLayout) await _tail(tester, host, 'old-unit[2999]');
        final originalPosition = host.controller.position;
        final originalTheme = _renderers(tester, 'long').first.theme.signature;
        host.quickCoordinator.updateUserDirection(
          changesLayout ? ScrollDirection.reverse : ScrollDirection.forward,
        );
        final pending = host.quickCoordinator.navigate(animate: true);
        expect(host.navigationStarts, 1);
        switch (retirement) {
          case 'cancel':
            host.quickCoordinator.cancelNavigation();
          case 'page':
            host.changePage(2);
          case 'content':
            host.replace([_post('long', '<p>new current body</p>', 1)]);
          case 'theme':
          case 'themeFade':
            host.changeTheme(ThemeData.dark());
          case 'fontScale':
            final preferences = ForumHtmlReaderPreferences.defaults();
            (host.container.read(
                      forumHtmlReaderPreferencesControllerProvider.notifier,
                    )
                    as _Preferences)
                .replace(
                  preferences.copyWith(
                    typography: preferences.typography.copyWith(fontScale: 1.5),
                  ),
                );
        }
        await tester.pump(const Duration(milliseconds: 16));
        if (changesLayout) {
          // Updating layout before the queued rebase's first build must preserve
          // the head's coordinate range and viewport. Theme dependency updates
          // may legitimately replace the position without rebasing the viewport.
          if (retirement == 'fontScale') {
            expect(host.controller.position, same(originalPosition));
          }
          expect(host.controller.position.minScrollExtent, closeTo(0, 1));
          expect(_atFirstFloor(tester, 'long'), isTrue);
        }
        await _pumpUntil(tester, () => !host.quickCoordinator.isNavigating);
        await pending;
        final confirmations = host.confirmedOffsets.length;
        final retiredOffset = host.controller.offset;
        for (var frame = 0; frame < 22; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        // Let real Isolate completion retire within this test's FakeAsync zone;
        // leaving a shared executor continuation behind can block later tests.
        await _pumpUntil(
          tester,
          () =>
              ForumHtmlPreparationExecutor.shared.activeCount == 0 &&
              ForumHtmlPreparationExecutor.shared.queuedCount == 0,
        );
        expect(confirmations, 0);
        expect(host.confirmedOffsets, isEmpty);
        if (retirement == 'cancel') {
          expect(host.controller.offset, closeTo(retiredOffset, 1));
        }
        if (retirement == 'content') {
          await _ready(tester, 'new current body');
          expect(_bodyText(tester), isNot(contains('old-unit[')));
        }
        if (changesLayout) {
          await _pumpUntil(
            tester,
            () =>
                _visibleMarker(tester, 'long', 0) &&
                _renderers(tester, 'long').every(
                  (renderer) => retirement == 'theme'
                      ? renderer.theme.signature != originalTheme
                      : renderer.preferences!.typography.fontScale == 1.5,
                ),
          );
          if (retirement == 'fontScale') {
            expect(host.controller.position, same(originalPosition));
          }
          expect(host.controller.position.minScrollExtent, closeTo(0, 1));
          expect(_atFirstFloor(tester, 'long'), isTrue);
          expect(_visibleMarker(tester, 'long', 2999), isFalse);
        }
        expect(host.visibleTargets, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        // Stop rebuilds first, then drain real work in its originating fake
        // clock even when an early geometry assertion fails.
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUntil(
          tester,
          () =>
              ForumHtmlPreparationExecutor.shared.activeCount == 0 &&
              ForumHtmlPreparationExecutor.shared.queuedCount == 0,
        );
      }
    });
  }

  testWidgets('quick endpoints leave the route target report unchanged', (
    tester,
  ) async {
    final host = _Host(
      [_post('long', _html(3000), 1)],
      target: 'long',
      quickScrolling: true,
    );
    addTearDown(host.dispose);
    await _mount(tester, host);
    await _ready(tester, 'unit[0]');
    await _pumpUntil(tester, () => host.visibleTargets.isNotEmpty);
    expect(host.visibleTargets, ['long']);
    host.quickCoordinator.updateUserDirection(ScrollDirection.reverse);
    await _quickNavigate(tester, host, animate: false);
    expect(_atPaginationEnd(tester), isTrue);
    host.quickCoordinator.updateUserDirection(ScrollDirection.forward);
    await _quickNavigate(tester, host, animate: false);
    expect(_atFirstFloor(tester, 'long'), isTrue);
    expect(host.target, 'long');
    expect(host.visibleTargets, ['long']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short quick scroll releases whole body while source preserves it',
    (tester) async {
      for (final sourced in [false, true]) {
        final host = _Host(
          [_post('long', _html(sourced ? 3000 : 50), 1)],
          quickScrolling: true,
          observer: sourced ? _ReadingObserver(tracked: false) : null,
        );
        addTearDown(host.dispose);
        await _mount(tester, host);
        await _ready(tester, 'unit[0]');
        final body = _rendererElements(tester, 'long').single;
        host.quickCoordinator.updateUserDirection(ScrollDirection.reverse);
        await _quickNavigate(tester, host, animate: false);
        expect(_atPaginationEnd(tester), isTrue);
        if (sourced) {
          expect(body.mounted, isTrue);
          expect(_rendererElements(tester, 'long').single, same(body));
        } else {
          expect(body.mounted, isFalse);
          host.quickCoordinator.updateUserDirection(ScrollDirection.forward);
          await _quickNavigate(tester, host, animate: false);
          await _ready(tester, 'unit[0]');
          expect(_atFirstFloor(tester, 'long'), isTrue);
          expect(_visibleMarker(tester, 'long', 0), isTrue);
          expect(_rendererElements(tester, 'long').single, isNot(same(body)));
          expect(
            _renderers(tester, 'long').single.html,
            host.posts.single.message,
          );
          expect(
            RegExp(r'unit\[').allMatches(_bodyText(tester, 'long')),
            hasLength(50),
          );
          expect(_bodyText(tester, 'long'), contains('unit[49]'));
        }
        expect(
          _renderers(tester, 'long').single.preparedDocument!.safeDisplayPlan,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'comment expansion survives endpoint rebases and retires with the page',
    (tester) async {
      final host = _Host([
        _post(
          'long',
          _html(3000, paragraphs: true),
          1,
          comments: const [
            ThreadPostCommentEntry(
              author: 'a',
              message: 'comment-a',
              dateline: 'local',
            ),
            ThreadPostCommentEntry(
              author: 'b',
              message: 'comment-b',
              dateline: 'local',
            ),
            ThreadPostCommentEntry(
              author: 'c',
              message: 'comment-c',
              dateline: 'local',
            ),
          ],
        ),
      ], quickScrolling: true);
      addTearDown(host.dispose);
      await _mount(tester, host);
      await _ready(tester, 'unit[0]');
      await _tail(tester, host, 'unit[2999]');
      expect(find.byType(ThreadPostCommentRow), findsNWidgets(3));
      final oldSection = find
          .byType(ThreadPostCommentSection)
          .evaluate()
          .single;
      await tester.tap(find.byKey(const Key('thread-post-comment-header')));
      await tester.pump();
      expect(find.byType(ThreadPostCommentRow), findsNothing);

      host.quickCoordinator.updateUserDirection(ScrollDirection.forward);
      await _quickNavigate(tester, host, animate: false);
      expect(_atFirstFloor(tester, 'long'), isTrue);
      expect(oldSection.mounted, isFalse);
      host.quickCoordinator.updateUserDirection(ScrollDirection.reverse);
      await _quickNavigate(tester, host, animate: false);
      expect(_atPaginationEnd(tester), isTrue);
      expect(find.byType(ThreadPostCommentSection), findsOneWidget);
      expect(find.byType(ThreadPostCommentRow), findsNothing);

      await tester.tap(find.byKey(const Key('thread-post-comment-header')));
      await tester.pump();
      expect(find.byType(ThreadPostCommentRow), findsNWidgets(3));
      host.quickCoordinator.updateUserDirection(ScrollDirection.forward);
      await _quickNavigate(tester, host, animate: false);
      host.quickCoordinator.updateUserDirection(ScrollDirection.reverse);
      await _quickNavigate(tester, host, animate: false);
      expect(find.byType(ThreadPostCommentRow), findsNWidgets(3));

      await tester.tap(find.byKey(const Key('thread-post-comment-header')));
      await tester.pump();
      expect(find.byType(ThreadPostCommentRow), findsNothing);
      host.changePage(2);
      await _tail(tester, host, 'unit[2999]');
      expect(find.byType(ThreadPostCommentRow), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('far floors stay unprepared until actual list demand', (
    tester,
  ) async {
    final posts = [
      for (var i = 0; i < 50; i++) _post('short-$i', _html(3), i + 1),
      _post('far-long', _html(3000), 51),
    ];
    final host = _Host(posts);
    addTearDown(host.dispose);
    await _mount(tester, host);
    await _ready(tester, 'unit[0]');
    expect(_renderers(tester, 'far-long'), isEmpty);
    expect(find.byKey(const Key('thread-post-header-far-long')), findsNothing);
    expect(_renderers(tester, 'short-49'), isEmpty);
    expect(_renderers(tester).length, lessThan(posts.length));
    await _tail(tester, host, 'unit[2999]');
    expect(_renderers(tester, 'far-long'), isNotEmpty);
    expect(_units(tester), contains(2999));
    expect(
      _renderers(
        tester,
        'far-long',
      ).every((renderer) => renderer.html.length < posts.last.message.length),
      isTrue,
    );
  });

  for (final landing in [ThreadPostLanding.top, ThreadPostLanding.bodyEnd]) {
    testWidgets(
      'PID ${landing.name} keeps its real requested edge and footer',
      (tester) async {
        final host = _Host(
          [
            _post('before', _html(3), 1),
            _post('long', _html(3000), 2),
            _post('after', _html(3), 3),
          ],
          target: 'long',
          landing: landing,
        );
        addTearDown(host.dispose);
        await _mount(tester, host);
        if (landing == ThreadPostLanding.top) {
          await _pumpUntil(
            tester,
            () => _bodyText(tester, 'long').contains('unit[0]'),
          );
          expect(
            find.byKey(const Key('thread-post-header-entry-long')),
            findsWidgets,
          );
          expect(_renderers(tester, 'long'), isNotEmpty);
        } else {
          await _ready(tester, 'unit[2999]');
          expect(
            find.byKey(const Key('thread-post-footer-entry-long')),
            findsWidgets,
          );
          final footer = tester.getRect(
            find.byKey(const Key('thread-post-footer-entry-long')).first,
          );
          expect(footer.top, greaterThanOrEqualTo(0));
          expect(footer.top, lessThan(720));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('replacement, theme and typography cannot retain stale chunks', (
    tester,
  ) async {
    final host = _Host([_post('long', _html(3000, prefix: '繁體'), 1)]);
    addTearDown(host.dispose);
    await _mount(tester, host);
    await _ready(tester, '繁體unit[0]');
    final oldElements = _rendererElements(tester, 'long');
    host.replace([_post('long', _html(3000, prefix: '简体'), 1)]);
    await _ready(tester, '简体unit[0]');
    expect(_bodyText(tester), isNot(contains('繁體unit[')));
    expect(
      oldElements
          .where((element) => element.mounted)
          .every(
            (element) => !(element.widget as ForumHtmlWidgetPostRenderer).html
                .contains('繁體unit['),
          ),
      isTrue,
    );
    final oldTheme = _renderers(tester, 'long').first.theme.signature;
    host.changeTheme(ThemeData.dark());
    await _pumpUntil(
      tester,
      () =>
          _renderers(tester, 'long').isNotEmpty &&
          _renderers(
            tester,
            'long',
          ).every((renderer) => renderer.theme.signature != oldTheme),
    );
    expect(_bodyText(tester), contains('简体unit[0]'));
    final prefs =
        host.container.read(
              forumHtmlReaderPreferencesControllerProvider.notifier,
            )
            as _Preferences;
    prefs.replace(
      ForumHtmlReaderPreferences.defaults().copyWith(
        conversionMode: TextConversionMode.toSimplified,
        typography: ForumHtmlReaderPreferences.defaults().typography.copyWith(
          fontScale: 1.7,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () =>
          _renderers(tester, 'long').isNotEmpty &&
          _renderers(tester, 'long').every(
            (renderer) => renderer.preferences!.typography.fontScale == 1.7,
          ),
    );
    expect(_bodyText(tester), contains('简体unit[0]'));
    expect(_units(tester).length, lessThan(3000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('decorated ancestors and styled BR retain complete rendering', (
    tester,
  ) async {
    final decorated =
        '<div style="border:1px solid #999;padding:12px;background:white">${_html(3000, paragraphs: true)}</div>';
    final host = _Host([_post('long', decorated, 1)]);
    addTearDown(host.dispose);
    await _mount(tester, host);
    await _ready(tester, 'unit[2999]');
    expect(_renderers(tester, 'long'), hasLength(1));
    expect(_units(tester), hasLength(3000));
    final styled = [
      for (var i = 0; i < 3000; i++)
        '<font size="4"><span style="color:#222">unit[$i]正文内容</span></font>',
    ].join('<br>');
    host.replace([_post('long', styled, 1)]);
    await _ready(tester, 'unit[2999]');
    expect(_renderers(tester, 'long'), hasLength(1));
    expect(_units(tester), hasLength(3000));
  });

  testWidgets(
    'display conversion retains the middle chunk anchor with unchanged source',
    (tester) async {
      final source = _post(
        'long',
        _html(3000, paragraphs: true, prefix: '繁體'),
        1,
      );
      final host = _Host([source], useProjection: true);
      addTearDown(host.dispose);
      await _mount(tester, host);
      await _ready(tester, '繁體unit[0]');
      final first = _markerRect(tester, 'long', 0)!;
      final second = _markerRect(tester, 'long', 1)!;
      host.controller.jumpTo(96 * (second.top - first.top) + first.top - 100);
      await _pumpUntil(tester, () {
        final box = _markerRect(tester, 'long', 96);
        return box != null && box.top >= 0 && box.top < 720;
      });
      final before = _markerRect(tester, 'long', 96)!;
      final prefs =
          host.container.read(
                forumHtmlReaderPreferencesControllerProvider.notifier,
              )
              as _Preferences;
      prefs.replace(
        ForumHtmlReaderPreferences.defaults().copyWith(
          conversionMode: TextConversionMode.toSimplified,
        ),
      );
      host.replaceProjection([
        _post(
          'long',
          source.message
              .replaceAll('繁體', '简体')
              .replaceAll('正文阅读内容。', '转换后的正文阅读内容更长。'),
          1,
        ),
      ]);
      try {
        await _pumpUntil(tester, () {
          final box = _markerRect(tester, 'long', 96);
          return _bodyText(tester, 'long').contains('简体unit[96]') &&
              box != null &&
              box.top >= 0 &&
              box.top < 720;
        });
      } catch (error) {
        final body = _bodyText(tester);
        final preview = body.length > 100 ? body.substring(0, 100) : body;
        fail(
          '$error; before=$before, current=${_markerRect(tester, 'long', 96)}, offset=${host.controller.offset}, max=${host.controller.position.maxScrollExtent}, mountedUnits=${(_units(tester).toList()..sort())}, rendererText=$preview',
        );
      }
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final after = _markerRect(tester, 'long', 96)!;
      expect(after.top, closeTo(before.top, 1));
      expect(host.posts.single, same(source));
      expect(_bodyText(tester), isNot(contains('繁體unit[')));
      expect(_units(tester).length, lessThan(3000));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection copy page keeps all 3000 units outside the lazy host',
    (tester) async {
      final post = _post('long', _html(3000, paragraphs: true), 1);
      final container = ProviderContainer(
        overrides: [
          forumHtmlReaderPreferencesControllerProvider.overrideWith(
            _Preferences.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.binding.setSurfaceSize(const Size(440, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ThreadPostHtmlSelectionCopyPage(
              post: post,
              threadId: '100',
              imageReferer: '',
              onOpenPostLink: (_) {},
              onOpenPostImage: null,
              onImageFallback: (_, _) {},
            ),
          ),
        ),
      );
      await _ready(tester, 'unit[2999]');
      expect(_renderers(tester, 'long'), hasLength(1));
      expect(_renderers(tester, 'long').single.html, post.message);
      expect(_units(tester), hasLength(3000));
      expect(find.byType(SelectionArea), findsOneWidget);
    },
  );

  testWidgets(
    'source reading coordinator keeps complete bodies before and after tracking admission',
    (tester) async {
      for (final tracked in [false, true]) {
        final observer = _ReadingObserver(tracked: tracked);
        final post = _post('long', _html(3000, paragraphs: true), 1);
        final host = _Host([post], target: 'long', observer: observer);
        addTearDown(host.dispose);
        await _mount(tester, host);
        await _pumpUntil(
          tester,
          () => _bodyText(tester, 'long').contains('unit[2999]'),
        );
        expect(_renderers(tester, 'long'), hasLength(1));
        expect(_renderers(tester, 'long').single.html, post.message);
        expect(
          _renderers(tester, 'long').single.preparedDocument!.safeDisplayPlan,
          isNull,
        );
        expect(_units(tester), hasLength(3000));
        if (!tracked) {
          expect(observer.restoreCalls, 0);
          expect(
            observer.viewports.every((viewport) => viewport.samples.isEmpty),
            isTrue,
          );
        } else {
          await _pumpUntil(
            tester,
            () =>
                observer.lastReady != null &&
                observer.viewports.last.restoreSettled,
          );
          final viewport = observer.viewports.last;
          final sample = observer.lastReady!;
          expect(sample.bodyHeight, greaterThan(100000));
          expect(
            -sample.relativeBodyTop /
                (sample.bodyHeight - sample.effectiveViewportHeight),
            closeTo(.6, .001),
          );
          expect(sample.finalBoundaryKnown, isTrue);
          expect(viewport.userNavigationRevision, 0);
          expect(observer.restoreCalls, 1);
          host.controller.jumpTo(host.controller.offset + 120);
          await tester.pumpAndSettle();
          expect(observer.restoreCalls, 1);
          expect(observer.viewports.last.userNavigationRevision, 0);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'twenty long floors stay chunked across cache eviction and endpoint navigation',
    (tester) async {
      final posts = [
        for (var i = 0; i < 20; i++)
          _post('long-$i', _html(3000, paragraphs: true, prefix: '$i-'), i + 1),
      ];
      // Keep the same page/Content owner. This visits every floor rather than
      // clearing the old budget through page replacement or skipping to twenty.
      final host = _Host(posts, target: 'long-0', quickScrolling: true);
      addTearDown(host.dispose);
      try {
        await _mount(tester, host);
        for (final i in [...List.generate(20, (index) => index), 9, 0, 19]) {
          host.navigate('long-$i');
          await _pumpUntil(tester, () => _visibleMarker(tester, 'long-$i', 0));
          final renderers = _renderers(tester, 'long-$i');
          expect(renderers, isNotEmpty);
          expect(
            renderers.every(
              (renderer) =>
                  renderer.html.length < posts[i].message.length &&
                  renderer.preparedDocument!.safeDisplayPlan == null,
            ),
            isTrue,
          );
          expect(
            RegExp(r'unit\[').allMatches(_bodyText(tester)).length,
            lessThan(3000),
          );
          // Traverse an actual chunk boundary after cache replacement. Returning
          // must materialize the requested chunks, never one whole HTML renderer.
          host.controller.jumpTo(host.controller.offset + 1800);
          await _pumpUntil(tester, () {
            if (_visibleMarker(tester, 'long-$i', 48)) return true;
            final marker = _markerRect(tester, 'long-$i', 48);
            final viewport = tester.getRect(
              find.byKey(const Key('thread-detail-list')),
            );
            host.controller.jumpTo(
              host.controller.offset +
                  (marker == null ? 300 : marker.top - viewport.top - 80),
            );
            return false;
          });
        }
        host.quickCoordinator.updateUserDirection(ScrollDirection.forward);
        await _quickNavigate(tester, host, animate: false);
        await _pumpUntil(tester, () => _visibleMarker(tester, 'long-0', 0));
        expect(_atFirstFloor(tester, 'long-0'), isTrue);
        expect(
          _renderers(tester, 'long-0').every(
            (renderer) => renderer.html.length < posts.first.message.length,
          ),
          isTrue,
        );
        host.quickCoordinator.updateUserDirection(ScrollDirection.reverse);
        await _quickNavigate(tester, host, animate: false);
        await _pumpUntil(tester, () => _visibleMarker(tester, 'long-19', 2999));
        expect(_atPaginationEnd(tester), isTrue);
        expect(host.confirmedOffsets, hasLength(2));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _drainPreparation(tester);
      }
    },
  );
}

class _Preferences extends ForumHtmlReaderPreferencesController {
  @override
  Future<ForumHtmlReaderPreferences> build() async =>
      ForumHtmlReaderPreferences.defaults();
  void replace(ForumHtmlReaderPreferences preferences) =>
      state = AsyncData(preferences);
}

class _Host {
  _Host(
    this.posts, {
    this.target,
    this.landing = ThreadPostLanding.top,
    this.useProjection = false,
    this.quickScrolling = false,
    this.themeAnimationDuration = const Duration(milliseconds: 200),
    ThreadBodyReadingObserver? observer,
  }) : container = ProviderContainer(
         overrides: [
           forumHtmlReaderPreferencesControllerProvider.overrideWith(
             _Preferences.new,
           ),
         ],
       ) {
    readingCoordinator = observer == null
        ? null
        : ThreadBodyReadingCoordinator(
            observer: observer,
            scrollController: controller,
            initialTargetPid: target,
          );
    quickCoordinator = ThreadDetailQuickScrollCoordinator(
      scrollController: controller,
      onNavigationStarted: () => navigationStarts++,
      onUserNavigation: () => confirmedOffsets.add(controller.offset),
    );
  }
  final ProviderContainer container;
  final controller = ScrollController();
  final key = GlobalKey<_PageState>();
  List<ThreadPost> posts;
  List<ThreadPost>? displayPosts;
  String? target;
  final ThreadPostLanding landing;
  final bool useProjection;
  final bool quickScrolling;
  final Duration themeAnimationDuration;
  int currentPage = 1;
  int navigationStarts = 0;
  final confirmedOffsets = <double>[];
  final visibleTargets = <String>[];
  late final ThreadDetailQuickScrollCoordinator quickCoordinator;
  late final ThreadBodyReadingCoordinator? readingCoordinator;
  void navigate(String pid) {
    target = pid;
    key.currentState!.replacePosts();
  }

  void replace(List<ThreadPost> value) {
    posts = value;
    key.currentState!.replacePosts();
  }

  void changeTheme(ThemeData theme) => key.currentState!.changeTheme(theme);
  void changePage(int page) {
    currentPage = page;
    key.currentState!.replacePosts();
  }

  void replaceProjection(List<ThreadPost> value) {
    displayPosts = value;
    key.currentState!.replacePosts();
  }

  void dispose() {
    quickCoordinator.dispose();
    readingCoordinator?.dispose();
    controller.dispose();
    container.dispose();
  }
}

class _Page extends StatefulWidget {
  const _Page({super.key, required this.host});
  final _Host host;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  ThemeData theme = ThemeData.light();
  void replacePosts() => setState(() {});
  void changeTheme(ThemeData value) => setState(() => theme = value);
  ThreadDetailPageState _state() =>
      ThreadDetailPageState.initial(tid: '100', subject: 'fixture').copyWith(
        posts: widget.host.posts,
        currentPage: widget.host.currentPage,
        lastPage: widget.host.currentPage,
        hasMore: false,
        isLoadingInitial: false,
      );
  ThreadDetailContentProjection? _projection() {
    final display = widget.host.displayPosts;
    if (!widget.host.useProjection && display == null) return null;
    return ThreadDetailContentProjection(
      sourceState: _state(),
      displaySubject: 'fixture',
      displayForumName: null,
      displayTypeName: null,
      displaySourceTagName: null,
      posts: [
        for (var i = 0; i < widget.host.posts.length; i++)
          ThreadDetailPostProjection(
            sourcePost: widget.host.posts[i],
            displayPost: display?[i] ?? widget.host.posts[i],
          ),
      ],
      displayRatingsByPostId: const {},
      mode: display == null
          ? TextConversionMode.none
          : TextConversionMode.toSimplified,
      converterId: 'fixture-independent',
      sourceRevision: 'unchanged-source',
      isConverted: display != null,
    );
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: widget.host.container,
    child: MaterialApp(
      theme: theme,
      themeAnimationDuration: widget.host.themeAnimationDuration,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 720,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              if (notification.depth == 0) {
                widget.host.quickCoordinator.updateMetrics(
                  notification.metrics,
                );
              }
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) {
                  widget.host.readingCoordinator?.handleScroll(notification);
                  if (notification case UserScrollNotification(
                    :final direction,
                  )) {
                    widget.host.quickCoordinator.updateUserDirection(direction);
                  }
                  widget.host.quickCoordinator.updateMetrics(
                    notification.metrics,
                  );
                }
                return false;
              },
              child: ThreadDetailContent(
                enableBodyChunking: true,
                state: _state(),
                projection: _projection(),
                targetPid: widget.host.target,
                landing: widget.host.landing,
                scrollController: widget.host.controller,
                bodyReadingCoordinator: widget.host.readingCoordinator,
                quickScrollCoordinator: widget.host.quickScrolling
                    ? widget.host.quickCoordinator
                    : null,
                onTargetVisible: widget.host.visibleTargets.add,
                imageReferer: '',
                onLoadPreviousPage: () {},
                onLoadNextPage: () {},
                onLoadPageNumber: (_) {},
                onOpenAuthorProfile: (_) {},
                onOpenCommentAuthorProfile: (_) {},
                onCopyActionUrl: (_, _) {},
                onOpenPostLink: (_) {},
                onOpenPostActions: (_) {},
                onTogglePollOption: (_, _) {},
                onSubmitPollVote: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReadingObserver implements ThreadBodyReadingObserver {
  _ReadingObserver({required this.tracked});
  final bool tracked;
  final viewports = <ThreadBodyReadingViewport>[];
  var restoreCalls = 0;
  ThreadBodyReadingSample? get lastReady {
    for (final viewport in viewports.reversed) {
      for (final sample in viewport.samples) {
        if (sample.bodyReady) return sample;
      }
    }
    return null;
  }

  @override
  bool tracks(String tid, String pid) =>
      tracked && tid == '100' && pid == 'long';
  @override
  ThreadBodyRestoreTarget? restoreTarget({
    required String tid,
    required String pid,
    required Object bodyIdentity,
  }) {
    restoreCalls++;
    return const ThreadBodyRestoreTarget(
      fraction: .6,
      requestIdentity: 'fixture',
    );
  }

  @override
  void onViewport(ThreadBodyReadingViewport viewport) =>
      viewports.add(viewport);
  @override
  void onContentChanged(Object contentIdentity) {}
  @override
  void onVisibility({required bool frontmost, required bool resumed}) {}
  @override
  void cancelPendingCompletion() {}
  @override
  Future<void> flush() async {}
  @override
  void retire() {}
}

Future<void> _mount(WidgetTester tester, _Host host) async {
  await tester.binding.setSurfaceSize(const Size(440, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_Page(key: host.key, host: host));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var frame = 0; frame < 500; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (predicate()) return;
    final exception = tester.takeException();
    if (exception != null) throw exception;
  }
  fail('Requested real body never became ready');
}

Future<void> _ready(WidgetTester tester, String text) =>
    _pumpUntil(tester, () => _bodyText(tester).contains(text));
Future<void> _drainPreparation(WidgetTester tester) => _pumpUntil(
  tester,
  () =>
      ForumHtmlPreparationExecutor.shared.activeCount == 0 &&
      ForumHtmlPreparationExecutor.shared.queuedCount == 0,
);
Future<void> _tail(WidgetTester tester, _Host host, String text) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    host.controller.jumpTo(host.controller.position.maxScrollExtent);
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      if (_bodyText(tester).contains(text) &&
          (host.controller.offset - host.controller.position.maxScrollExtent)
                  .abs() <
              1) {
        return;
      }
    }
  }
  fail('Real tail could not be reached');
}

Future<Set<(String, int)>> _quickNavigate(
  WidgetTester tester,
  _Host host, {
  required bool animate,
}) async {
  final observed = <(String, int)>{};
  void capture() {
    for (final renderer in _renderers(tester)) {
      final marker = RegExp(r'unit\[(\d+)\]').firstMatch(renderer.html);
      if (marker != null) {
        observed.add((renderer.sourceId ?? '', int.parse(marker.group(1)!)));
      }
    }
  }

  capture();
  final navigation = host.quickCoordinator.navigate(animate: animate);
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    capture();
    if (!host.quickCoordinator.isNavigating) break;
  }
  expect(host.quickCoordinator.isNavigating, isFalse);
  await navigation;
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    capture();
  }
  return observed;
}

bool _atFirstFloor(WidgetTester tester, String pid) {
  final header = find.byKey(Key('thread-post-header-entry-$pid'));
  final card = find.byKey(Key('thread-post-card-entry-$pid'));
  final first = header.evaluate().isNotEmpty ? header.first : card.first;
  if (first.evaluate().isEmpty) return false;
  final viewport = tester.getRect(find.byKey(const Key('thread-detail-list')));
  final edge = tester.getRect(first).top;
  return edge >= viewport.top - 1 && edge < viewport.top + 32;
}

bool _atPaginationEnd(WidgetTester tester) {
  final pagination = find.byKey(const Key('thread-detail-pagination'));
  if (pagination.evaluate().isEmpty) return false;
  final viewport = tester.getRect(find.byKey(const Key('thread-detail-list')));
  final edge = tester.getRect(pagination.first).bottom;
  return edge > viewport.bottom - 40 && edge <= viewport.bottom + 1;
}

bool _visibleMarker(WidgetTester tester, String pid, int unit) {
  final marker = _markerRect(tester, pid, unit);
  if (marker == null) return false;
  return marker.overlaps(
    tester.getRect(find.byKey(const Key('thread-detail-list'))),
  );
}

String _endpointGeometry(WidgetTester tester, _Host host, String pid) {
  final header = find.byKey(Key('thread-post-header-entry-$pid'));
  final card = find.byKey(Key('thread-post-card-entry-$pid'));
  final first = header.evaluate().isNotEmpty ? header.first : card.first;
  return 'offset=${host.controller.offset}, '
      'min=${host.controller.position.minScrollExtent}, '
      'max=${host.controller.position.maxScrollExtent}, '
      'first=${first.evaluate().isEmpty ? null : tester.getRect(first)}, '
      'viewport=${tester.getRect(find.byKey(const Key('thread-detail-list')))}, '
      'confirmed=${host.confirmedOffsets}';
}

List<ForumHtmlWidgetPostRenderer> _renderers(
  WidgetTester tester, [
  String? pid,
]) => tester
    .widgetList<ForumHtmlWidgetPostRenderer>(
      find.byType(ForumHtmlWidgetPostRenderer),
    )
    .where((renderer) => pid == null || renderer.sourceId == pid)
    .toList();
List<Element> _rendererElements(WidgetTester tester, String pid) => find
    .byType(ForumHtmlWidgetPostRenderer)
    .evaluate()
    .where(
      (element) =>
          (element.widget as ForumHtmlWidgetPostRenderer).sourceId == pid,
    )
    .toList();
String _bodyText(WidgetTester tester, [String? pid]) => find
    .byType(ForumHtmlWidgetPostRenderer)
    .evaluate()
    .where(
      (root) =>
          pid == null ||
          (root.widget as ForumHtmlWidgetPostRenderer).sourceId == pid,
    )
    .map((root) {
      final values = <String>[];
      void visit(Element element) {
        if (element is RenderObjectElement &&
            element.renderObject is RenderParagraph) {
          final object = element.renderObject as RenderParagraph;
          if (object.hasSize) {
            values.add(object.text.toPlainText(includeSemanticsLabels: false));
          }
        }
        element.visitChildren(visit);
      }

      root.visitChildren(visit);
      return values.join('\n');
    })
    .join('\n');
Rect? _markerRect(WidgetTester tester, String pid, int unit) {
  Rect? found;
  void visit(Element element) {
    if (element is RenderObjectElement &&
        element.renderObject is RenderParagraph) {
      final paragraph = element.renderObject as RenderParagraph;
      if (paragraph.hasSize) {
        final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
        final marker = 'unit[$unit]';
        final offset = text.indexOf(marker);
        if (offset >= 0) {
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: offset,
              extentOffset: offset + marker.length,
            ),
          );
          if (boxes.isNotEmpty) {
            found = boxes.first.toRect().shift(
              paragraph.localToGlobal(Offset.zero),
            );
          }
        }
      }
    }
    element.visitChildren(visit);
  }

  for (final element in _rendererElements(tester, pid)) {
    element.visitChildren(visit);
  }
  return found;
}

Set<int> _units(WidgetTester tester) => {
  for (final match in RegExp(r'unit\[(\d+)\]').allMatches(_bodyText(tester)))
    int.parse(match.group(1)!),
};
ThreadPost _post(
  String pid,
  String html,
  int number, {
  List<ThreadPostCommentEntry> comments = const [],
}) => ThreadPost(
  pid: pid,
  author: 'fixture',
  authorId: '',
  message: html,
  number: number,
  isFirst: number == 1,
  dateline: 'local',
  comments: comments,
);
String _html(int count, {bool paragraphs = false, String prefix = ''}) {
  final values = <String>[];
  for (var i = 0; i < count; i++) {
    final value = '${prefix}unit[$i]：正文阅读内容。正文阅读内容。正文阅读内容。正文阅读内容。';
    values.add(paragraphs ? '<p>$value</p>' : value);
  }
  return values.join(paragraphs ? '' : '<br>');
}
