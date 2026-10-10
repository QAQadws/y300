import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/clipboard/forum_clipboard_route_observer.dart';

void main() {
  late ForumClipboardRouteObserver observer;
  late GlobalKey<NavigatorState> navigator;
  late ModalRoute<dynamic> homeRoute;
  late List<bool> changes;

  setUp(() {
    observer = ForumClipboardRouteObserver();
    navigator = GlobalKey<NavigatorState>();
    changes = [];
    observer.addListener(() => changes.add(observer.isTransitioning));
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) {
            homeRoute = ModalRoute.of(context)!;
            return const Scaffold();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    changes.clear();
    expect(observer.isTransitioning, isFalse);
  }

  Future<void> disposeHost(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    observer.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('waits for page entrance and reverse transition', (tester) async {
    await pumpHost(tester);
    final page = _pageRoute();
    unawaited(navigator.currentState!.push(page));
    expect(
      observer.isTransitioning,
      isTrue,
      reason: 'animation: ${page.animation}',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(observer.isTransitioning, isTrue);
    await tester.pumpAndSettle();
    expect(observer.isTransitioning, isFalse);

    navigator.currentState!.pop();
    expect(homeRoute.isCurrent, isTrue);
    expect(observer.isTransitioning, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(observer.isTransitioning, isTrue);
    await tester.pumpAndSettle();
    expect(observer.isTransitioning, isFalse);
    expect(changes, [true, false, true, false]);
    await disposeHost(tester);
  });

  testWidgets('popup exit stays blocked after home becomes current', (
    tester,
  ) async {
    await pumpHost(tester);
    final popup = _PopupRoute();
    unawaited(navigator.currentState!.push(popup));
    await tester.pumpAndSettle();
    expect(observer.isTransitioning, isFalse);
    expect(homeRoute.secondaryAnimation!.status, AnimationStatus.dismissed);

    navigator.currentState!.pop();
    expect(homeRoute.isCurrent, isTrue);
    expect(homeRoute.secondaryAnimation!.status, AnimationStatus.dismissed);
    expect(observer.isTransitioning, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('popup')), findsOneWidget);
    expect(observer.isTransitioning, isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('popup')), findsNothing);
    expect(observer.isTransitioning, isFalse);
    await disposeHost(tester);
  });

  testWidgets('old exit completion cannot release another entrance', (
    tester,
  ) async {
    await pumpHost(tester);
    unawaited(navigator.currentState!.push(_PopupRoute()));
    await tester.pumpAndSettle();
    changes.clear();
    navigator.currentState!.pop();
    unawaited(
      navigator.currentState!.push(
        _pageRoute(duration: const Duration(milliseconds: 600)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(observer.isTransitioning, isTrue);
    expect(changes, [true]);
    await tester.pumpAndSettle();
    expect(observer.isTransitioning, isFalse);
    expect(changes, [true, false]);
    await disposeHost(tester);
  });

  testWidgets('pushReplacement waits for the incoming animation', (
    tester,
  ) async {
    await pumpHost(tester);
    unawaited(navigator.currentState!.push(_pageRoute()));
    await tester.pumpAndSettle();
    final replacement = _pageRoute();
    unawaited(navigator.currentState!.pushReplacement(replacement));
    expect(observer.isTransitioning, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(observer.isTransitioning, isTrue);
    await tester.pumpAndSettle();
    expect(observer.isTransitioning, isFalse);
    await disposeHost(tester);
  });

  testWidgets('non-animated replace during entrance does not remain blocked', (
    tester,
  ) async {
    await pumpHost(tester);
    final oldRoute = _pageRoute();
    unawaited(navigator.currentState!.push(oldRoute));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final replacement = _pageRoute();
    navigator.currentState!.replace(oldRoute: oldRoute, newRoute: replacement);
    await tester.pump();
    expect(observer.isTransitioning, isFalse);
    await disposeHost(tester);
  });

  testWidgets('remove retires a pending entrance and releases after disposal', (
    tester,
  ) async {
    await pumpHost(tester);
    final page = _pageRoute();
    unawaited(navigator.currentState!.push(page));
    await tester.pump();
    expect(observer.isTransitioning, isTrue);
    navigator.currentState!.removeRoute(page);
    expect(observer.isTransitioning, isTrue);
    await tester.pump();
    expect(homeRoute.isCurrent, isTrue);
    expect(observer.isTransitioning, isFalse);
    await disposeHost(tester);
  });

  testWidgets('zero-duration routes release without an animation wait', (
    tester,
  ) async {
    await pumpHost(tester);
    final page = _pageRoute(duration: Duration.zero);
    unawaited(navigator.currentState!.push(page));
    await tester.pumpAndSettle();
    expect(observer.isTransitioning, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.isTransitioning, isFalse);
    await disposeHost(tester);
  });

  testWidgets('dispose detaches listeners and ignores late route completion', (
    tester,
  ) async {
    await pumpHost(tester);
    final popup = _PopupRoute();
    unawaited(navigator.currentState!.push(popup));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    expect(observer.isTransitioning, isTrue);
    final count = changes.length;
    observer.dispose();
    expect(observer.isTransitioning, isFalse);
    await tester.pumpAndSettle();
    expect(changes, hasLength(count));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dispose during entrance ignores later animation status', (
    tester,
  ) async {
    await pumpHost(tester);
    unawaited(navigator.currentState!.push(_pageRoute()));
    expect(observer.isTransitioning, isTrue);
    final count = changes.length;
    observer.dispose();
    await tester.pumpAndSettle();
    expect(changes, hasLength(count));
    expect(observer.isTransitioning, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

PageRoute<void> _pageRoute({
  Duration duration = const Duration(milliseconds: 300),
}) => PageRouteBuilder<void>(
  transitionDuration: duration,
  reverseTransitionDuration: duration,
  pageBuilder: (_, _, _) => const Scaffold(),
  transitionsBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);

final class _PopupRoute extends PopupRoute<void> {
  @override
  Color? get barrierColor => Colors.black12;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'test barrier';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const Center(child: SizedBox(key: Key('popup'), width: 40, height: 40));
}
