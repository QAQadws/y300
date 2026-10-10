import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/clipboard/forum_clipboard_link_policy.dart';
import 'package:y300/app/clipboard/forum_clipboard_snack_bar_presenter.dart';

import '../../test_support/localized_test_app.dart';

const _bodyKey = Key('presenter-test-body');
const _businessKey = Key('presenter-test-business-feedback');
const _candidate = ForumClipboardLinkCandidate(
  url: 'https://bbs.yamibo.com/thread-123-1-1.html',
  kind: ForumClipboardLinkKind.thread,
  fingerprint: 'presenter-test-thread',
);

void main() {
  for (final accessibleHide in [false, true]) {
    for (final externalFirst in [true, false]) {
      testWidgets(
        '${accessibleHide ? 'accessible hide' : 'remove'} in same frame '
        '${externalFirst ? 'before' : 'after'} retirement preserves successor',
        (tester) async {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(accessibleNavigation: accessibleHide);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          final fixture = _Fixture(accessibleNavigation: accessibleHide);
          await tester.pumpWidget(fixture.build());
          addTearDown(() async {
            fixture.presenter.dispose();
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          });
          expect(
            MediaQuery.accessibleNavigationOf(
              fixture.messenger.currentContext!,
            ),
            accessibleHide,
          );
          fixture.show(tester, _candidate);
          await tester.pumpAndSettle();
          expect(fixture.shown, 1);

          final business = fixture.messenger.currentState!.showSnackBar(
            const SnackBar(
              key: _businessKey,
              persist: true,
              content: Text('Business feedback'),
            ),
          );
          var businessClosed = false;
          unawaited(business.closed.then((_) => businessClosed = true));
          await tester.pump();
          expect(find.byKey(_businessKey), findsNothing);

          void scheduleExternalClose() {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final messenger = fixture.messenger.currentState!;
              if (accessibleHide) {
                messenger.hideCurrentSnackBar();
              } else {
                messenger.removeCurrentSnackBar();
              }
            });
          }

          // Both callbacks run in one frame. The SDK advances the queue
          // synchronously, before delivering controller.closed in a microtask.
          if (externalFirst) scheduleExternalClose();
          fixture.show(tester, null);
          if (!externalFirst) scheduleExternalClose();
          await tester.pump();
          await tester.pumpAndSettle();

          expect(businessClosed, isFalse);
          expect(find.byKey(_businessKey), findsOneWidget);
          expect(fixture.dismissed, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

final class _Fixture {
  _Fixture({required this.accessibleNavigation});

  final bool accessibleNavigation;
  final messenger = GlobalKey<ScaffoldMessengerState>();
  final presenter = ForumClipboardSnackBarPresenter();
  int shown = 0;
  int dismissed = 0;

  Widget build() => LocalizedTestApp(
    scaffoldMessengerKey: messenger,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(accessibleNavigation: accessibleNavigation),
      child: child!,
    ),
    home: const Scaffold(body: SizedBox.expand(key: _bodyKey)),
  );

  void show(WidgetTester tester, ForumClipboardLinkCandidate? candidate) {
    presenter.show(
      context: tester.element(find.byKey(_bodyKey)),
      candidate: candidate,
      isCurrent: () => true,
      onOpen: () {},
      onShown: () => shown++,
      onDismiss: () => dismissed++,
    );
  }
}
