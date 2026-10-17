import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/link_copy_feedback.dart';

import '../../test_support/localized_test_app.dart';

void main() {
  late BuildContext firstContext;
  late BuildContext secondContext;
  late GlobalKey<NavigatorState> navigator;

  Future<void> pumpHost(WidgetTester tester) async {
    navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      LocalizedTestApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Column(
            children: [
              Builder(
                builder: (context) {
                  firstContext = context;
                  return const SizedBox();
                },
              ),
              Builder(
                builder: (context) {
                  secondContext = context;
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets(
    'a newer copy in the same route retires another bubble feedback',
    (tester) async {
      await pumpHost(tester);
      expect(firstContext, isNot(same(secondContext)));
      expect(ModalRoute.of(firstContext), same(ModalRoute.of(secondContext)));
      final l10n = AppLocalizations.of(firstContext);
      final pending = Completer<void>();
      final writes = <String>[];
      final first = copyLinkWithFeedback(
        firstContext,
        url: 'https://first.example.test/',
        writeText: (url) {
          writes.add(url);
          return pending.future;
        },
        isCurrent: () => true,
      );
      expect(find.byType(SnackBar), findsNothing);

      await copyLinkWithFeedback(
        secondContext,
        url: 'https://second.example.test/',
        writeText: (url) async => writes.add(url),
        isCurrent: () => true,
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.linkCopied), findsOneWidget);

      pending.completeError(StateError('first copy failed late'));
      await first;
      await tester.pumpAndSettle();

      expect(writes, [
        'https://first.example.test/',
        'https://second.example.test/',
      ]);
      expect(find.text(l10n.linkCopied), findsOneWidget);
      expect(find.text(l10n.linkCopyFailed), findsNothing);
    },
  );

  testWidgets('copying in another route does not retire this route feedback', (
    tester,
  ) async {
    await pumpHost(tester);
    final l10n = AppLocalizations.of(firstContext);
    final sourceRoute = ModalRoute.of(firstContext)!;
    final pending = Completer<void>();
    final first = copyLinkWithFeedback(
      firstContext,
      url: 'https://first.example.test/',
      writeText: (_) => pending.future,
      isCurrent: () => sourceRoute.isCurrent,
    );
    late BuildContext otherContext;
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (context) {
            otherContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ModalRoute.of(otherContext), isNot(same(sourceRoute)));
    await copyLinkWithFeedback(
      otherContext,
      url: 'https://other.example.test/',
      writeText: (_) async {},
      isCurrent: () => true,
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.linkCopied), findsOneWidget);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(sourceRoute.isCurrent, isTrue);
    pending.completeError(StateError('source route copy failed'));
    await first;
    await tester.pumpAndSettle();

    expect(find.text(l10n.linkCopyFailed), findsOneWidget);
  });

  testWidgets('an inactive source neither writes nor reports feedback', (
    tester,
  ) async {
    await pumpHost(tester);
    var writes = 0;
    await copyLinkWithFeedback(
      firstContext,
      url: 'https://example.test/',
      writeText: (_) async {
        writes++;
      },
      isCurrent: () => false,
    );
    await tester.pumpAndSettle();

    expect(writes, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final failed in [false, true]) {
    testWidgets('an unmounted source discards late failed=$failed feedback', (
      tester,
    ) async {
      await pumpHost(tester);
      final pending = Completer<void>();
      final completion = copyLinkWithFeedback(
        firstContext,
        url: 'https://example.test/',
        writeText: (_) => pending.future,
        isCurrent: () => true,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(firstContext.mounted, isFalse);
      if (failed) {
        pending.completeError(StateError('copy failed after disposal'));
      } else {
        pending.complete();
      }
      await completion;
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
