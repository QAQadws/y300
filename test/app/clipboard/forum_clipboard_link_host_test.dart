import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/clipboard/clipboard_link_settings_controller.dart';
import 'package:y300/app/clipboard/clipboard_link_settings_repository.dart';
import 'package:y300/app/clipboard/forum_clipboard_link_host.dart';
import 'package:y300/app/clipboard/forum_clipboard_runtime.dart';
import 'package:y300/app/navigation/forum_link_routes.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/clipboard/clipboard_text_reader.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/application/auth_session_controller.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../test_support/localized_test_app.dart';

void main() {
  const url = 'https://bbs.yamibo.com/thread-123-2-1.html';
  const other = 'https://bbs.yamibo.com/thread-124-1-1.html';
  const noticeKey = Key('forum-clipboard-link-notice');

  testWidgets('cold check runs once and normal shell rebuilds never reread', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    expect(fixture.reader.reads, hasLength(1));
    await fixture.complete(tester, 0, null);
    fixture.tab = 1;
    await fixture.pump(tester);
    fixture.tab = 0;
    await fixture.pump(tester);
    expect(fixture.reader.reads, hasLength(1));
    expect(find.byKey(noticeKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cold check waits for settings, authentication and shell readiness',
    (tester) async {
      final settings = Completer<bool>();
      final auth = Completer<AuthSessionViewState>();
      final fixture = _Fixture(settingsLoad: settings, authLoad: auth)
        ..ready = false;
      await fixture.mount(tester);
      expect(fixture.reader.reads, isEmpty);
      settings.complete(true);
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, isEmpty);
      auth.complete(const AuthSessionViewState.signedOut());
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, isEmpty);
      fixture.ready = true;
      await fixture.pump(tester);
      expect(fixture.reader.reads, hasLength(1));
      await fixture.complete(tester, 0, url);
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('allowed-prompt gating defers one cold intent until usable', (
    tester,
  ) async {
    final fixture = _Fixture()..allowPrompt = false;
    await fixture.mount(tester);
    expect(fixture.reader.reads, isEmpty);
    fixture.allowPrompt = true;
    await fixture.pump(tester);
    expect(fixture.reader.reads, hasLength(1));
    await fixture.complete(tester, 0, null);
    fixture.allowPrompt = false;
    await fixture.pump(tester);
    fixture.allowPrompt = true;
    await fixture.pump(tester);
    expect(fixture.reader.reads, hasLength(1));
  });

  testWidgets(
    'unavailable settings do not consume clipboard data or cold intent',
    (tester) async {
      final settings = Completer<bool>();
      final fixture = _Fixture(settingsLoad: settings);
      await fixture.mount(tester);
      settings.completeError(StateError('synthetic settings unavailable'));
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, isEmpty);
      expect(fixture.runtime.needsColdCheck, isTrue);
      expect(
        fixture.container
            .read(clipboardLinkSettingsControllerProvider)
            .hasError,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('WAF and update gates postpone initial clipboard work', (
    tester,
  ) async {
    final fixture = _Fixture();
    fixture.runtime
      ..setWafBusy(true)
      ..setUpdateBlocked(true);
    await fixture.mount(tester);
    expect(fixture.reader.reads, isEmpty);
    fixture.runtime.setWafBusy(false);
    await tester.pumpAndSettle();
    expect(fixture.reader.reads, isEmpty);
    fixture.runtime.setUpdateBlocked(false);
    await tester.pumpAndSettle();
    expect(fixture.reader.reads, hasLength(1));
    await fixture.complete(tester, 0, url);
    expect(find.byKey(noticeKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'WAF gate rejects late detection and releases one pending check',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      fixture.runtime.setWafBusy(true);
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.reader.reads, hasLength(1));
      fixture.runtime.setWafBusy(false);
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, hasLength(2));
      await fixture.complete(tester, 1, other);
      expect(fixture.runtime.coordinator.candidate?.url, other);
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'WAF released before the host pause observer cannot start a read',
    (tester) async {
      final fixture = _Fixture();
      fixture.runtime.setWafBusy(true);
      final earlyObserver = _ReleaseWafBeforePause(fixture.runtime);
      tester.binding.addObserver(earlyObserver);
      addTearDown(() => tester.binding.removeObserver(earlyObserver));
      await fixture.mount(tester);
      expect(fixture.reader.reads, isEmpty);
      await _lifecycle(tester, AppLifecycleState.paused);
      expect(fixture.reader.reads, isEmpty);
      await _lifecycle(tester, AppLifecycleState.resumed);
      expect(fixture.reader.reads, hasLength(1));
      await fixture.complete(tester, 0, url);
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(fixture.reader.reads, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inactive does not create a new check but paused resume does', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await fixture.complete(tester, 0, null);
    await _lifecycle(tester, AppLifecycleState.inactive);
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(fixture.reader.reads, hasLength(1));
    await _lifecycle(tester, AppLifecycleState.paused);
    expect(fixture.reader.reads, hasLength(1));
    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(fixture.reader.reads, hasLength(2));
    await fixture.complete(tester, 1, url);
    expect(find.byKey(noticeKey), findsOneWidget);
  });

  testWidgets(
    'late background reads are dropped before a fresh foreground read',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await _lifecycle(tester, AppLifecycleState.paused);
      await fixture.complete(tester, 0, url);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(fixture.reader.reads, hasLength(1));
      await _lifecycle(tester, AppLifecycleState.resumed);
      expect(fixture.reader.reads, hasLength(2));
      await fixture.complete(tester, 1, other);
      expect(fixture.runtime.coordinator.candidate?.url, other);
      expect(find.byKey(noticeKey), findsOneWidget);
    },
  );

  testWidgets(
    'focus changes retire old reads without creating empty opportunities',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      _focus(tester, focused: false);
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(fixture.reader.reads, hasLength(1));
      _focus(tester, focused: true);
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, hasLength(2));
      await fixture.complete(tester, 1, null);
      _focus(tester, focused: false);
      await tester.pumpAndSettle();
      _focus(tester, focused: true);
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'another view focus event does not change this host eligibility',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      _focus(tester, focused: false, viewId: tester.view.viewId + 100);
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(fixture.reader.reads, hasLength(1));
    },
  );

  testWidgets(
    'covered popup drops old candidates and waits for exit completion',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final context = tester.element(
        find.byKey(const Key('clipboard-shell-body')),
      );
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Fixture popup')),
        ),
      );
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(fixture.reader.reads, hasLength(1));
      fixture.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(fixture.reader.reads, hasLength(1));
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, hasLength(2));
      await fixture.complete(tester, 1, other);
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard inset defers an existing intent until text entry ends',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(fixture.reader.reads, hasLength(1));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, hasLength(2));
      await fixture.complete(tester, 1, other);
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same UID session replacement rejects an old account clipboard read',
    (tester) async {
      final fixture = _Fixture();
      fixture.sessions.saveExtracted(_snapshot('101'));
      await fixture.mount(tester);
      fixture.sessions
        ..clear()
        ..saveExtracted(_snapshot('101'));
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(fixture.reader.reads, hasLength(2));
      await fixture.complete(tester, 1, other);
      expect(fixture.runtime.coordinator.candidate?.url, other);
      expect(find.byKey(noticeKey), findsOneWidget);
    },
  );

  testWidgets('auth refresh keeps a late candidate out until confirmed ready', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    fixture.auth.loading();
    await tester.pumpAndSettle();
    await fixture.complete(tester, 0, url);
    expect(fixture.runtime.coordinator.candidate, isNull);
    expect(fixture.reader.reads, hasLength(1));
    fixture.auth.ready();
    await tester.pumpAndSettle();
    expect(fixture.reader.reads, hasLength(2));
    await fixture.complete(tester, 1, other);
    expect(find.byKey(noticeKey), findsOneWidget);
  });

  testWidgets(
    'disabling settings retires late clipboard work and future resumes',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await fixture.container
          .read(clipboardLinkSettingsControllerProvider.notifier)
          .setEnabled(false);
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.runtime.coordinator.candidate, isNull);
      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.resumed);
      expect(fixture.reader.reads, hasLength(1));
      expect(fixture.settings.saves, [false]);
    },
  );

  testWidgets(
    'removed host rejects late work and rebuilt host retains one cold check',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      fixture.showHost = false;
      await fixture.pump(tester);
      await fixture.complete(tester, 0, url);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(fixture.reader.reads, hasLength(1));
      fixture.showHost = true;
      await fixture.pump(tester);
      expect(fixture.reader.reads, hasLength(2));
      await fixture.complete(tester, 1, null);
      fixture.showHost = false;
      await fixture.pump(tester);
      fixture.showHost = true;
      await fixture.pump(tester);
      expect(fixture.reader.reads, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'swiped or shown targets do not reappear after foreground resume',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await fixture.complete(tester, 0, url);
      await _swipeClipboardSnackBar(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(noticeKey), findsNothing);
      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await fixture.complete(tester, 1, 'different explanation $url');
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(fixture.destinations, isEmpty);
    },
  );

  testWidgets(
    'notice opens exactly one native target without prefetch or new reads',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await fixture.complete(tester, 0, url);
      expect(fixture.destinations, isEmpty);
      await tester.tap(find.byKey(const Key('forum-clipboard-link-open')));
      await tester.pumpAndSettle();
      expect(fixture.destinations, hasLength(1));
      expect(fixture.destinations.single.tid, '123');
      expect(fixture.destinations.single.page, 2);
      expect(find.text('Native target'), findsOneWidget);
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.reader.reads, hasLength(1));
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, hasLength(1));
      expect(find.byKey(noticeKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final invalidation in [
    'pause',
    'inactive',
    'focus',
    'owner',
    'disable',
    'host',
    'auth',
  ]) {
    testWidgets(
      'pending notice floor navigation is rejected after $invalidation',
      (tester) async {
        final fixture = _Fixture();
        fixture.sessions.saveExtracted(_snapshot('101'));
        await fixture.mount(tester);
        await fixture.complete(
          tester,
          0,
          'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=123&pid=456',
        );
        expect(fixture.locator.requests, isEmpty);
        await tester.tap(find.byKey(const Key('forum-clipboard-link-open')));
        await tester.pumpAndSettle();
        expect(fixture.locator.requests, hasLength(1));
        switch (invalidation) {
          case 'pause':
            await _lifecycle(tester, AppLifecycleState.paused);
          case 'inactive':
            await _lifecycle(tester, AppLifecycleState.inactive);
          case 'focus':
            _focus(tester, focused: false);
            await tester.pumpAndSettle();
          case 'owner':
            fixture.sessions
              ..clear()
              ..saveExtracted(_snapshot('101'));
            await tester.pumpAndSettle();
          case 'disable':
            await fixture.container
                .read(clipboardLinkSettingsControllerProvider.notifier)
                .setEnabled(false);
            await tester.pumpAndSettle();
          case 'host':
            fixture.showHost = false;
            await fixture.pump(tester);
          case 'auth':
            fixture.auth.loading();
            await tester.pumpAndSettle();
        }
        fixture.locator.requests.single.complete(
          const ApiSuccess(
            ThreadPostLocation(tid: '123', pid: '456', page: 3, url: ''),
          ),
        );
        await tester.idle();
        expect(fixture.navigator.currentState!.canPop(), isFalse);
        await tester.pumpAndSettle();
        expect(find.byKey(noticeKey), findsNothing);
        expect(fixture.destinations, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final gate in ['WAF', 'update']) {
    testWidgets(
      '$gate gate preserves confirmed floor navigation through recovery',
      (tester) async {
        final fixture = _Fixture();
        await fixture.mount(tester);
        await fixture.complete(
          tester,
          0,
          'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=123&pid=456',
        );
        final sourceContext = tester.element(
          find.byKey(const Key('clipboard-shell-body')),
        );
        await tester.tap(find.byKey(const Key('forum-clipboard-link-open')));
        await tester.pumpAndSettle();
        expect(fixture.locator.requests, hasLength(1));
        fixture.observer.pushed.clear();

        void setBlocked(bool blocked) {
          if (gate == 'WAF') {
            fixture.runtime.setWafBusy(blocked);
          } else {
            fixture.runtime.setUpdateBlocked(blocked);
          }
        }

        setBlocked(true);
        await tester.pumpAndSettle();
        expect(find.byKey(noticeKey), findsNothing);
        setBlocked(false);
        await tester.pumpAndSettle();
        fixture.locator.requests.single.complete(
          const ApiSuccess(
            ThreadPostLocation(tid: '123', pid: '456', page: 3, url: ''),
          ),
        );
        await tester.idle();

        expect(fixture.observer.pushed, hasLength(1));
        final route = fixture.observer.pushed.single as MaterialPageRoute<void>;
        final page = route.builder(sourceContext) as ThreadDetailPage;
        expect(page.tid, '123');
        expect(page.targetPid, '456');
        expect(page.initialPage, 3);
        // Inspect before the frame mounts the real page: no remote forum
        // request belongs in a clipboard-host test.
        fixture.navigator.currentState!.removeRoute(route);
        await tester.pumpAndSettle();
        expect(fixture.reader.reads, hasLength(1));
        expect(find.byKey(noticeKey), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'clipboard SnackBar expires without moving layout or renewing on rebuild',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final body = find.byKey(const Key('clipboard-shell-body'));
      final navigation = find.byKey(const Key('clipboard-shell-navigation'));
      final bodyRect = tester.getRect(body);
      final navigationRect = tester.getRect(navigation);
      await fixture.complete(tester, 0, url);
      expect(find.byKey(noticeKey), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.duration, const Duration(seconds: 6));
      expect(snackBar.persist, isFalse);
      expect(tester.getRect(body), bodyRect);
      expect(tester.getRect(navigation), navigationRect);

      await tester.pump(const Duration(seconds: 3));
      fixture.tab = 1;
      await fixture.pump(tester);
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(tester.getRect(body), bodyRect);
      expect(tester.getRect(navigation), navigationRect);
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pumpAndSettle();
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(tester.getRect(body), bodyRect);
      expect(tester.getRect(navigation), navigationRect);
      expect(fixture.reader.reads, hasLength(1));

      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await fixture.complete(tester, 1, url);
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clipboard notice waits behind ordinary feedback without replacing it',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final business = _showBusinessSnackBar(tester, 'Business feedback');
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      expect(find.text('Business feedback'), findsOneWidget);
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.runtime.coordinator.candidate?.url, url);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Business feedback'), findsOneWidget);
      expect(find.byKey(noticeKey), findsNothing);

      business.close();
      await tester.pumpAndSettle();
      expect(await business.closed, SnackBarClosedReason.hide);
      expect(find.byKey(noticeKey), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 5500));
      expect(find.byKey(noticeKey), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid unseen notice preserves business queue and does not mark history',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final first = _showBusinessSnackBar(tester, 'First business feedback');
      final second = _showBusinessSnackBar(tester, 'Second business feedback');
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      expect(find.byKey(noticeKey), findsNothing);
      final stale = fixture.runtime.coordinator.candidate!;
      var firstClosed = false;
      var secondClosed = false;
      unawaited(first.closed.then((_) => firstClosed = true));
      unawaited(second.closed.then((_) => secondClosed = true));
      await fixture.container
          .read(clipboardLinkSettingsControllerProvider.notifier)
          .setEnabled(false);
      await tester.pumpAndSettle();
      expect(fixture.runtime.coordinator.candidate, isNull);
      expect(fixture.runtime.coordinator.takeForOpen(stale), isNull);
      expect(find.text('First business feedback'), findsOneWidget);
      expect(firstClosed, isFalse);
      expect(secondClosed, isFalse);
      first.close();
      await tester.pumpAndSettle();
      expect(find.text('Second business feedback'), findsOneWidget);
      expect(find.byKey(noticeKey), findsNothing);
      expect(secondClosed, isFalse);
      second.close();
      await tester.pumpAndSettle();
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.destinations, isEmpty);
      expect(fixture.locator.requests, isEmpty);

      await fixture.container
          .read(clipboardLinkSettingsControllerProvider.notifier)
          .setEnabled(true);
      await tester.pumpAndSettle();
      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.resumed);
      expect(fixture.reader.reads, hasLength(2));
      await fixture.complete(tester, 1, url);
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fresh candidate waits for stale queued entry and preserves business order',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final first = _showBusinessSnackBar(tester, 'First queued business');
      await tester.pumpAndSettle();
      await fixture.complete(tester, 0, url);
      final stale = fixture.runtime.coordinator.candidate!;
      expect(find.byKey(noticeKey), findsNothing);
      _focus(tester, focused: false);
      await tester.pumpAndSettle();
      _focus(tester, focused: true);
      await tester.pumpAndSettle();
      expect(fixture.reader.reads, hasLength(2));
      await fixture.complete(tester, 1, other);
      expect(fixture.runtime.coordinator.takeForOpen(stale), isNull);
      await fixture.pump(tester);
      await fixture.pump(tester);
      expect(find.text('First queued business'), findsOneWidget);
      expect(fixture.reader.reads, hasLength(2));
      final second = _showBusinessSnackBar(tester, 'Second queued business');
      first.close();
      await tester.pumpAndSettle();
      expect(find.text('Second queued business'), findsOneWidget);
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.runtime.coordinator.candidate?.url, other);

      second.close();
      await tester.pumpAndSettle();
      expect(find.byKey(noticeKey), findsOneWidget);
      await tester.tap(find.byKey(const Key('forum-clipboard-link-open')));
      await tester.pumpAndSettle();
      expect(fixture.destinations, hasLength(1));
      expect(fixture.destinations.single.tid, '124');
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(noticeKey), findsNothing);
      expect(fixture.runtime.coordinator.candidate, isNull);
      await _lifecycle(tester, AppLifecycleState.paused);
      await _lifecycle(tester, AppLifecycleState.resumed);
      await fixture.complete(tester, 2, url);
      expect(find.byKey(noticeKey), findsOneWidget);
      expect(fixture.runtime.coordinator.candidate?.url, url);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retiring visible notice keeps the next business feedback alive',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await fixture.complete(tester, 0, url);
      final business = _showBusinessSnackBar(
        tester,
        'Queued business feedback',
      );
      var closed = false;
      unawaited(business.closed.then((_) => closed = true));
      _focus(tester, focused: false);
      await tester.pumpAndSettle();
      expect(find.byKey(noticeKey), findsNothing);
      expect(find.text('Queued business feedback'), findsOneWidget);
      expect(closed, isFalse);
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Queued business feedback'), findsOneWidget);
      expect(closed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Open does not double-hide business feedback queued behind its action',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await fixture.complete(
        tester,
        0,
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=123&pid=456',
      );
      final business = _showBusinessSnackBar(tester, 'Business after Open');
      var closed = false;
      unawaited(business.closed.then((_) => closed = true));
      await tester.tap(find.byKey(const Key('forum-clipboard-link-open')));
      await tester.pumpAndSettle();
      expect(fixture.locator.requests, hasLength(1));
      expect(find.byKey(noticeKey), findsNothing);
      expect(find.text('Business after Open'), findsOneWidget);
      expect(closed, isFalse);
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Business after Open'), findsOneWidget);
      expect(closed, isFalse);
      expect(fixture.reader.reads, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'traditional Chinese notice remains usable on narrow large-text layouts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      try {
        final fixture = _Fixture()
          ..locale = const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
          )
          ..textScale = 2;
        await fixture.mount(tester);
        await fixture.complete(tester, 0, url);
        final context = tester.element(find.byKey(noticeKey));
        final l10n = AppLocalizations.of(context);
        expect(find.text(l10n.clipboardLinkFoundThread), findsOneWidget);
        expect(find.text(l10n.clipboardLinkOpen), findsOneWidget);
        expect(
          find.byTooltip(MaterialLocalizations.of(context).closeButtonTooltip),
          findsNothing,
        );
        expect(
          tester
              .getSemantics(find.text(l10n.clipboardLinkFoundThread))
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(
          tester
              .getSemantics(find.byKey(const Key('forum-clipboard-link-open')))
              .flagsCollection
              .isButton,
          isTrue,
        );
        expect(
          tester
              .getSize(find.byKey(const Key('forum-clipboard-link-open')))
              .height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
        await _swipeClipboardSnackBar(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(noticeKey), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  tester.binding.handleAppLifecycleStateChanged(state);
  await tester.pumpAndSettle();
}

Future<void> _swipeClipboardSnackBar(WidgetTester tester) async {
  await tester.drag(
    find.ancestor(
      of: find.byKey(const Key('forum-clipboard-link-notice')),
      matching: find.byType(SnackBar),
    ),
    const Offset(0, 200),
  );
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _showBusinessSnackBar(
  WidgetTester tester,
  String label,
) =>
    ScaffoldMessenger.of(
      tester.element(find.byKey(const Key('clipboard-shell-body'))),
    ).showSnackBar(
      SnackBar(content: Text(label), duration: const Duration(hours: 1)),
    );

void _focus(WidgetTester tester, {required bool focused, int? viewId}) =>
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: viewId ?? tester.view.viewId,
        state: focused ? ViewFocusState.focused : ViewFocusState.unfocused,
        direction: ViewFocusDirection.forward,
      ),
    );

YamiboSessionSnapshot _snapshot(String uid) => YamiboSessionSnapshot(
  isLoggedIn: true,
  uid: uid,
  username: 'fixture',
  formhash: '',
  updatedAt: DateTime.utc(2026, 10, 10),
  source: 'synthetic-test',
);

final class _Fixture {
  _Fixture({
    Completer<bool>? settingsLoad,
    Completer<AuthSessionViewState>? authLoad,
  }) : settings = _SettingsRepository(settingsLoad),
       auth = _AuthController(authLoad) {
    container = ProviderContainer(
      overrides: [
        clipboardTextReaderProvider.overrideWithValue(reader),
        clipboardLinkSettingsRepositoryProvider.overrideWithValue(settings),
        authSessionControllerProvider.overrideWith(
          () => auth = _AuthController(auth.load),
        ),
        yamiboSessionStoreProvider.overrideWithValue(sessions),
        threadPostLocatorProvider.overrideWithValue(locator),
        nativeForumLinkPageFactoryProvider.overrideWithValue((
          destination, {
          isActive = true,
        }) {
          destinations.add(destination);
          return Scaffold(appBar: AppBar(title: const Text('Native target')));
        }),
      ],
    );
  }

  late final ProviderContainer container;
  final _Reader reader = _Reader();
  final _SettingsRepository settings;
  _AuthController auth;
  final YamiboSessionStore sessions = YamiboSessionStore();
  final _Locator locator = _Locator();
  final navigator = GlobalKey<NavigatorState>();
  final observer = _PushObserver();
  final destinations = <YamiboForumLinkDestination>[];
  bool ready = true;
  bool allowPrompt = true;
  bool showHost = true;
  int tab = 0;
  Locale locale = const Locale('zh');
  double textScale = 1;

  ForumClipboardRuntime get runtime =>
      container.read(forumClipboardRuntimeProvider);

  Widget build() => UncontrolledProviderScope(
    container: container,
    child: LocalizedTestApp(
      navigatorKey: navigator,
      navigatorObservers: [
        container.read(forumClipboardRouteObserverProvider),
        observer,
      ],
      locale: locale,
      theme: ThemeData(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: showHost
          ? ForumClipboardLinkHost(
              key: const ValueKey('clipboard-test-host'),
              isReady: ready,
              allowPrompt: allowPrompt,
              builder: (_) => Scaffold(
                body: SizedBox.expand(
                  key: const Key('clipboard-shell-body'),
                  child: Text('Tab $tab'),
                ),
                bottomNavigationBar: NavigationBar(
                  key: const Key('clipboard-shell-navigation'),
                  selectedIndex: tab,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.forum_outlined),
                      label: 'Forum',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.book_outlined),
                      label: 'Library',
                    ),
                  ],
                ),
              ),
            )
          : const Scaffold(body: Text('Host removed')),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      container.dispose();
      tester.view.resetViewInsets();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await pump(tester);
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
  }

  Future<void> complete(WidgetTester tester, int index, String? value) async {
    reader.reads[index].complete(value);
    await tester.pumpAndSettle();
  }
}

final class _Reader implements ClipboardTextReader {
  final reads = <Completer<String?>>[];

  @override
  Future<String?> readText() {
    final read = Completer<String?>();
    reads.add(read);
    return read.future;
  }
}

final class _PushObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

final class _Locator implements ThreadPostLocator {
  final requests = <Completer<ApiResult<ThreadPostLocation>>>[];

  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) {
    final request = Completer<ApiResult<ThreadPostLocation>>();
    requests.add(request);
    return request.future;
  }
}

final class _SettingsRepository implements ClipboardLinkSettingsRepository {
  _SettingsRepository(this.load);
  final Completer<bool>? load;
  final saves = <bool>[];

  @override
  Future<bool> loadEnabled() async => load == null ? true : await load!.future;

  @override
  Future<void> saveEnabled(bool value) async => saves.add(value);
}

class _AuthController extends AuthSessionController {
  _AuthController(this.load);
  final Completer<AuthSessionViewState>? load;

  @override
  Future<AuthSessionViewState> build() async => load == null
      ? const AuthSessionViewState.signedOut()
      : await load!.future;

  void loading() => state = const AsyncLoading();

  void ready() => state = const AsyncData(AuthSessionViewState.signedOut());
}

final class _ReleaseWafBeforePause extends WidgetsBindingObserver {
  _ReleaseWafBeforePause(this.runtime);

  final ForumClipboardRuntime runtime;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) runtime.setWafBusy(false);
  }
}
