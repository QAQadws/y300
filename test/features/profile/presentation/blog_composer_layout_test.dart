import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/presentation/blog/blog_composer_layout.dart';

const _bodyKey = Key('layout-body');
const _toolbarKey = Key('layout-toolbar');
const _actionsKey = Key('layout-actions');
const _viewport = Size(320, 600);

void main() {
  testWidgets(
    'keyboard movement preserves toolbar height, side safety and child builds',
    (tester) async {
      final metrics = ValueNotifier(const _Metrics());
      addTearDown(metrics.dispose);
      var bodyBuilds = 0;
      var toolbarBuilds = 0;
      await _pump(
        tester,
        metrics,
        body: Builder(
          builder: (context) {
            bodyBuilds++;
            MediaQuery.of(context);
            return const SizedBox.expand(key: _bodyKey);
          },
        ),
        toolbar: Builder(
          builder: (context) {
            toolbarBuilds++;
            MediaQuery.of(context);
            return const SafeArea(
              key: _toolbarKey,
              top: false,
              child: SizedBox(key: _actionsKey, height: 56),
            );
          },
        ),
      );
      final initialBuilds = (bodyBuilds, toolbarBuilds);
      final closed = tester.getRect(find.byKey(_toolbarKey));
      expect(closed.height, 56);
      expect(closed.bottom, 576);

      metrics.value = const _Metrics(inset: 280);
      await tester.pump();
      expect(tester.getRect(find.byKey(_toolbarKey)), closed);
      await tester.pump(const Duration(milliseconds: 60));
      final opening = tester.getRect(find.byKey(_toolbarKey));
      expect(opening.bottom, lessThan(closed.bottom));
      expect(opening.bottom, greaterThan(320));
      expect(opening.height, 56);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_toolbarKey)).bottom, 320);

      metrics.value = const _Metrics();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final closing = tester.getRect(find.byKey(_toolbarKey));
      expect(closing.bottom, greaterThan(320));
      expect(closing.bottom, lessThan(closed.bottom));
      expect(closing.height, 56);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_toolbarKey)), closed);
      final actions = tester.getRect(find.byKey(_actionsKey));
      expect(actions.left, 12);
      expect(actions.right, 302);
      expect((bodyBuilds, toolbarBuilds), initialBuilds);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tall keyboards leave a valid short viewport', (tester) async {
    final metrics = ValueNotifier(const _Metrics());
    addTearDown(metrics.dispose);
    await _pump(tester, metrics, size: const Size(320, 120));
    metrics.value = const _Metrics(inset: 280);
    await tester.pump();
    await tester.pumpAndSettle();
    final body = tester.getRect(find.byKey(_bodyKey));
    final toolbar = tester.getRect(find.byKey(_toolbarKey));
    expect(body.height, 0);
    expect(toolbar.height, 56);
    expect(toolbar.top, greaterThanOrEqualTo(0));
    expect(toolbar.bottom, lessThanOrEqualTo(120));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inset retargets and reversal continue from the visible position',
    (tester) async {
      final metrics = ValueNotifier(const _Metrics());
      addTearDown(metrics.dispose);
      await _pump(tester, metrics);
      final closedBottom = tester.getRect(find.byKey(_toolbarKey)).bottom;
      metrics.value = const _Metrics(inset: 220);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      final firstBottom = tester.getRect(find.byKey(_toolbarKey)).bottom;
      expect(firstBottom, lessThan(closedBottom));

      metrics.value = const _Metrics(inset: 300);
      await tester.pump();
      expect(
        tester.getRect(find.byKey(_toolbarKey)).bottom,
        closeTo(firstBottom, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 45));
      final nextBottom = tester.getRect(find.byKey(_toolbarKey)).bottom;
      expect(nextBottom, lessThan(firstBottom));
      expect(nextBottom, greaterThan(300));

      metrics.value = const _Metrics();
      await tester.pump();
      expect(
        tester.getRect(find.byKey(_toolbarKey)).bottom,
        closeTo(nextBottom, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 45));
      final reversing = tester.getRect(find.byKey(_toolbarKey));
      expect(reversing.bottom, greaterThan(nextBottom));
      expect(reversing.bottom, lessThan(closedBottom));
      expect(tester.getRect(find.byKey(_bodyKey)).bottom, reversing.top);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_toolbarKey)).bottom, closedBottom);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hidden actions and reduced motion keep one bottom inset', (
    tester,
  ) async {
    final metrics = ValueNotifier(const _Metrics(disableAnimations: true));
    addTearDown(metrics.dispose);
    await _pump(tester, metrics);
    metrics.value = const _Metrics(
      inset: 280,
      disableAnimations: true,
      showToolbar: false,
    );
    await tester.pump();
    expect(find.byKey(_toolbarKey), findsNothing);
    expect(tester.getRect(find.byKey(_bodyKey)).bottom, 320);

    metrics.value = const _Metrics(disableAnimations: true, showToolbar: false);
    await tester.pump();
    expect(tester.getRect(find.byKey(_bodyKey)).bottom, 576);
    metrics.value = const _Metrics(disableAnimations: true);
    await tester.pump();
    expect(tester.getRect(find.byKey(_toolbarKey)).bottom, 576);
    expect(tester.getRect(find.byKey(_bodyKey)).bottom, 520);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  ValueNotifier<_Metrics> metrics, {
  Size size = _viewport,
  Widget body = const SizedBox.expand(key: _bodyKey),
  Widget toolbar = const SafeArea(
    key: _toolbarKey,
    top: false,
    child: SizedBox(key: _actionsKey, height: 56),
  ),
}) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: ValueListenableBuilder<_Metrics>(
          valueListenable: metrics,
          builder: (context, value, _) => MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: EdgeInsets.only(
                left: 12,
                right: 18,
                bottom: math.max(0, 24 - value.inset),
              ),
              viewPadding: const EdgeInsets.only(
                left: 12,
                right: 18,
                bottom: 24,
              ),
              viewInsets: EdgeInsets.only(bottom: value.inset),
              disableAnimations: value.disableAnimations,
            ),
            child: BlogComposerLayout(
              body: body,
              toolbar: value.showToolbar ? toolbar : null,
            ),
          ),
        ),
      ),
    ),
  ),
);

class _Metrics {
  const _Metrics({
    this.inset = 0,
    this.showToolbar = true,
    this.disableAnimations = false,
  });

  final double inset;
  final bool showToolbar;
  final bool disableAnimations;
}
