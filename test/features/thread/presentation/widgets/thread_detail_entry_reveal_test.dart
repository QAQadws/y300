import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_entry_reveal.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('long body lays out before either floor becomes visible', (
    tester,
  ) async {
    final host = _Host();
    await tester.pumpWidget(host.app());
    await tester.pump(const Duration(milliseconds: 350));
    final loadingElement = tester.element(find.byType(ThreadDetailLoading));
    host.loading = false;
    host.refresh();
    await tester.pump();
    expect(
      tester.element(find.byType(ThreadDetailLoading)),
      same(loadingElement),
    );
    expect(host.opacity(tester), 0);
    expect(find.text('second floor').hitTestable(), findsNothing);
    final bodyElement = tester.element(find.byKey(const Key('body')));

    host.ready = true;
    host.height = 2000;
    host.refresh();
    await tester.pump();
    expect(host.opacity(tester), 0);
    expect(
      tester.getTopLeft(find.text('second floor')).dy,
      greaterThanOrEqualTo(2000),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(host.opacity(tester), inExclusiveRange(0, 1));
    expect(find.text('second floor').hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(host.opacity(tester), 1);
    expect(find.byType(ThreadDetailLoading), findsNothing);
    expect(tester.element(find.byKey(const Key('body'))), same(bodyElement));

    // Later rebuilds do not replay entry or re-hide readable content.
    host.ready = false;
    host.refresh();
    await tester.pump();
    expect(host.opacity(tester), 1);
    expect(find.byType(ThreadDetailLoading), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('visible pending bodies wait but offscreen bodies do not', (
    tester,
  ) async {
    final host = _Host()..loading = false;
    await tester.pumpWidget(host.app());
    await tester.pump(const Duration(milliseconds: 350));
    expect(host.opacity(tester), 0);
    host.ready = true;
    host.showPendingSecondBody = true;
    host.refresh();
    await tester.pump();
    expect(host.opacity(tester), 0);
    host.height = 2000;
    host.refresh();
    await tester.pumpAndSettle();
    expect(host.opacity(tester), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('ready entry has no fixed wait, reduced motion=$reduceMotion', (
      tester,
    ) async {
      final host = _Host()
        ..reduceMotion = reduceMotion
        ..loading = reduceMotion
        ..ready = true;
      await tester.pumpWidget(host.app());
      if (reduceMotion) {
        await tester.pump(const Duration(milliseconds: 350));
        host.loading = false;
        host.refresh();
        await tester.pump();
      }
      await tester.pump();
      expect(host.opacity(tester), 1);
      expect(find.byType(ThreadDetailLoading), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('failure is visible and retry waits for the new body', (
    tester,
  ) async {
    final host = _Host();
    await tester.pumpWidget(host.app());
    await tester.pump(const Duration(milliseconds: 350));
    host.loading = false;
    host.failed = true;
    host.refresh();
    await tester.pumpAndSettle();
    expect(find.text('retry').hitTestable(), findsOneWidget);
    expect(find.byType(ThreadDetailLoading), findsNothing);
    host.failed = false;
    host.loading = true;
    host.refresh();
    await tester.pump();
    expect(find.byType(ThreadDetailLoading), findsOneWidget);
    host.loading = false;
    host.refresh();
    await tester.pump();
    expect(host.opacity(tester), 0);
    host.ready = true;
    host.refresh();
    await tester.pumpAndSettle();
    expect(host.opacity(tester), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden bodies expose no semantics or pointer targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final host = _Host()..loading = false;
    await tester.pumpWidget(host.app());
    expect(find.bySemanticsLabel('second floor'), findsNothing);
    expect(find.text('second floor').hitTestable(), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

class _Host {
  bool loading = true;
  bool failed = false;
  bool ready = false;
  bool reduceMotion = false;
  bool showPendingSecondBody = false;
  double height = 48;
  late StateSetter refreshState;

  void refresh() => refreshState(() {});

  double opacity(WidgetTester tester) => tester
      .widget<Opacity>(find.byKey(const Key('thread-detail-entry-content')))
      .opacity;

  Widget app() => LocalizedTestApp(
    home: StatefulBuilder(
      builder: (context, setState) {
        refreshState = setState;
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: ThreadDetailEntryReveal(
              loading: loading,
              failed: failed,
              loadingBuilder: (context, opacity) => ThreadDetailLoading(
                subject: 'fixture-title',
                statusOpacity: opacity,
              ),
              child: loading
                  ? const SizedBox.expand()
                  : failed
                  ? const Center(child: Text('retry'))
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          ThreadEntryBody(
                            key: const Key('body'),
                            ready: () => ready,
                            child: SizedBox(height: height),
                          ),
                          const Text('second floor'),
                          if (showPendingSecondBody)
                            ThreadEntryBody(
                              ready: () => false,
                              child: const SizedBox(height: 48),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    ),
  );
}
