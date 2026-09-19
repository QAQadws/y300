import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/providers/thread_quick_scroll_preferences_providers.dart';
import 'package:y300/features/thread/domain/models/thread_quick_scroll_dock_side.dart';
import 'package:y300/features/thread/domain/repositories/thread_quick_scroll_preferences_repository.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';
import 'package:y300/features/thread/presentation/thread_quick_scroll_preferences_controller.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_quick_scroll_dock.dart';
import 'package:y300/features/thread/presentation/widgets/thread_quick_scroll_dock_location.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../../test_support/localized_test_app.dart';

const _left = ThreadQuickScrollDockSide.left;
const _right = ThreadQuickScrollDockSide.right;
final _button = find.byKey(const Key('thread-detail-quick-scroll-button'));
final _feedback = find.byKey(const Key('thread-quick-scroll-drag-feedback'));

void main() {
  for (final source in ThreadQuickScrollDockSide.values) {
    testWidgets(
      'long press from $source follows the grip and snaps on release',
      (tester) async {
        final h = await _pump(tester, side: source);
        final original = tester.getCenter(_button);
        final grip = original + const Offset(9, 6);
        final gesture = await tester.startGesture(grip);
        await tester.pump(
          kLongPressTimeout + const Duration(milliseconds: 150),
        );
        expect(_feedback, findsOneWidget);
        expect(tester.getCenter(_feedback), offsetMoreOrLessEquals(original));
        final label = AppLocalizations.of(
          tester.element(_button),
        ).threadDetailScrollBottom;
        expect(find.text(label), findsNothing);

        final destination = Offset(source == _right ? 110 : 690, 190);
        await gesture.moveTo(destination + const Offset(9, 6));
        await tester.pump();
        expect(
          tester.getCenter(_feedback),
          offsetMoreOrLessEquals(destination),
        );
        expect(h.repository.writes, isEmpty);
        expect(h.scroll.offset, 0);
        await gesture.up();
        await tester.pump();
        await tester.pump();
        final anchor = tester.getCenter(_button);
        expect(
          tester.getCenter(_feedback),
          offsetMoreOrLessEquals(destination),
        );
        await tester.pump(const Duration(milliseconds: 140));
        final during = tester.getCenter(_feedback);
        expect(
          (during - anchor).distance,
          lessThan((destination - anchor).distance),
        );
        expect((during - anchor).distance, greaterThan(0));
        await tester.pumpAndSettle();
        expect(_feedback, findsNothing);
        expect(h.repository.writes, [source == _right ? _left : _right]);
        expect(tester.getCenter(_button).dy, original.dy);
        expect(tester.getCenter(_button).dx + original.dx, 800);
        expect(h.scroll.offset, 0);

        await tester.tap(_button);
        await tester.pumpAndSettle();
        expect(h.scroll.offset, h.scroll.position.maxScrollExtent);
        await tester.tap(_button);
        await tester.pumpAndSettle();
        expect(h.scroll.offset, 0);
      },
    );
  }

  testWidgets('a short drag never moves the button or scrolls the page', (
    tester,
  ) async {
    final h = await _pump(tester);
    final original = tester.getCenter(_button);
    await tester.drag(_button, const Offset(-180, -60));
    await tester.pumpAndSettle();
    expect(tester.getCenter(_button), original);
    expect(_feedback, findsNothing);
    expect(h.repository.writes, isEmpty);
    expect(h.scroll.offset, 0);
  });

  testWidgets('cancel returns to the source without saving or scrolling', (
    tester,
  ) async {
    final h = await _pump(tester);
    final original = tester.getCenter(_button);
    final gesture = await _longPress(tester);
    await gesture.moveTo(const Offset(130, 160));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_feedback, findsNothing);
    expect(tester.getCenter(_button), original);
    expect(h.repository.writes, isEmpty);
    expect(h.scroll.offset, 0);
  });

  for (final source in ThreadQuickScrollDockSide.values) {
    testWidgets('release on the midline retains $source', (tester) async {
      final h = await _pump(tester, side: source);
      final gesture = await _longPress(tester);
      await gesture.moveTo(const Offset(400, 220));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(h.repository.writes, isEmpty);
      expect(tester.getCenter(_button).dx, source == _right ? 760 : 40);
    });
  }

  testWidgets('drag stays inside the safe viewport and below the app bar', (
    tester,
  ) async {
    await _pump(tester, padding: const EdgeInsets.fromLTRB(34, 24, 10, 20));
    final gesture = await _longPress(tester);
    await gesture.moveTo(const Offset(-300, -400));
    await tester.pump(const Duration(milliseconds: 150));
    var center = tester.getCenter(_feedback);
    expect(center.dx - 48 * 1.08 / 2, greaterThanOrEqualTo(34 - 0.01));
    expect(center.dy - 48 * 1.08 / 2, greaterThanOrEqualTo(80 - 0.01));
    await gesture.moveTo(const Offset(1800, 1400));
    await tester.pump();
    center = tester.getCenter(_feedback);
    expect(center.dx + 48 * 1.08 / 2, lessThanOrEqualTo(790.01));
    expect(center.dy + 48 * 1.08 / 2, lessThanOrEqualTo(580.01));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'asymmetric insets give symmetric anchors and retain bottom spacing',
    (tester) async {
      final h = await _pump(
        tester,
        padding: const EdgeInsets.fromLTRB(34, 24, 10, 20),
      );
      final right = tester.getRect(_button);
      expect(800 - right.right, 50);
      expect(600 - right.bottom, 48);
      await h.controller(tester).setSide(_left);
      await tester.pumpAndSettle();
      final left = tester.getRect(_button);
      expect(left.left, closeTo(50, 0.01));
      expect(left.top, right.top);
      expect(left.center.dx + right.center.dx, 800);
    },
  );

  testWidgets('keyboard and snackbar still raise the docking anchor', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.media.value = h.media.value.copyWith(
      viewInsets: const EdgeInsets.only(bottom: 240),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(_button).bottom, 600 - 240 - 28);
    h.media.value = h.media.value.copyWith(viewInsets: EdgeInsets.zero);
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(
      tester.element(_button),
    ).showSnackBar(const SnackBar(content: Text('fixture')));
    await tester.pumpAndSettle();
    final snackTop = tester.getTopLeft(find.byType(SnackBar)).dy;
    expect(tester.getRect(_button).bottom, lessThanOrEqualTo(snackTop - 28));
    final gesture = await _longPress(tester);
    await gesture.moveTo(const Offset(100, 200));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(_button).bottom, lessThanOrEqualTo(snackTop - 28));
  });

  testWidgets('viewport change cancels an active drag and redocks safely', (
    tester,
  ) async {
    final h = await _pump(tester);
    final gesture = await _longPress(tester);
    await gesture.moveTo(const Offset(100, 170));
    await tester.pump();
    tester.view.physicalSize = const Size(600, 800);
    h.media.value = h.media.value.copyWith(size: const Size(600, 800));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_feedback, findsNothing);
    expect(tester.getCenter(_button).dx, 560);
    expect(h.repository.writes, isEmpty);
  });

  testWidgets(
    'a snackbar appearing during the snap moves its live destination',
    (tester) async {
      await _pump(tester);
      final gesture = await _longPress(tester);
      await gesture.moveTo(const Offset(100, 200));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();
      ScaffoldMessenger.of(
        tester.element(_button),
      ).showSnackBar(const SnackBar(content: Text('fixture')));
      // Advance actual frames so the overlay can observe the moving layout.
      for (var frame = 0; frame < 26; frame++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(
        (tester.getCenter(_feedback) - tester.getCenter(_button)).distance,
        lessThan(2),
      );
      await tester.pumpAndSettle();
      expect(_feedback, findsNothing);
    },
  );

  testWidgets('reduced motion snaps immediately', (tester) async {
    final h = await _pump(tester, disableAnimations: true);
    final gesture = await _longPress(tester);
    await gesture.moveTo(const Offset(100, 200));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(_feedback, findsNothing);
    expect(tester.getCenter(_button).dx, 40);
    expect(h.repository.writes, [_left]);
    final settled = tester.getRect(_button);
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getRect(_button), settled);
  });

  testWidgets('delayed loading never flashes at the default side', (
    tester,
  ) async {
    final loaded = Completer<ThreadQuickScrollDockSide>();
    await _pump(tester, load: loaded.future);
    expect(_button, findsNothing);
    loaded.complete(_left);
    await tester.pumpAndSettle();
    expect(tester.getCenter(_button).dx, 40);
  });

  testWidgets('a different thread uses the same device choice', (tester) async {
    final h = await _pump(tester);
    final gesture = await _longPress(tester);
    await gesture.moveTo(const Offset(100, 200));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    h.page.value = 'another-thread';
    await tester.pumpAndSettle();
    expect(tester.getCenter(_button).dx, 40);
    expect(h.repository.writes, [_left]);
  });

  testWidgets('failed save restores the stored side with localized feedback', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.repository.failWrite = true;
    final gesture = await _longPress(tester);
    await gesture.moveTo(const Offset(100, 200));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getCenter(_button).dx, 760);
    final l10n = AppLocalizations.of(tester.element(_button));
    expect(find.text(l10n.threadQuickScrollPositionSaveFailed), findsOneWidget);
    expect(_feedback, findsNothing);
  });

  testWidgets('accessibility action switches sides without dragging', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await _pump(tester);
    final l10n = AppLocalizations.of(tester.element(_button));
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.hint == l10n.threadQuickScrollDragHint,
    );
    final node = tester.getSemantics(finder);
    final actions = node.getSemanticsData().customSemanticsActionIds!;
    final id = actions.singleWhere(
      (id) =>
          CustomSemanticsAction.getAction(id)!.label ==
          l10n.threadQuickScrollMoveLeft,
    );
    node.owner!.performAction(node.id, SemanticsAction.customAction, id);
    await tester.pumpAndSettle();
    expect(tester.getCenter(_button).dx, 40);
    expect(h.repository.writes, [_left]);
    expect(h.scroll.offset, 0);
    final hint = find.semantics.byPredicate(
      (node) => node.hint.contains(l10n.threadQuickScrollDragHint),
    );
    expect(hint, findsOne);
    h.hasContent.value = false;
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    semantics.dispose();
  });

  testWidgets('losing content or leaving the page removes drag feedback', (
    tester,
  ) async {
    final h = await _pump(tester);
    var gesture = await _longPress(tester);
    h.hasContent.value = false;
    await tester.pumpAndSettle();
    expect(_feedback, findsNothing);
    expect(_button, findsNothing);
    await gesture.up();
    h.hasContent.value = true;
    await tester.pumpAndSettle();
    gesture = await _longPress(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_feedback, findsNothing);
    expect(h.repository.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<TestGesture> _longPress(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(_button));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 150));
  return gesture;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  ThreadQuickScrollDockSide side = _right,
  EdgeInsets padding = EdgeInsets.zero,
  bool disableAnimations = false,
  Future<ThreadQuickScrollDockSide>? load,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final h = _Harness(side, padding, disableAnimations, load);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    h.dispose();
  });
  await tester.pumpWidget(h.app());
  await tester.pump();
  h.coordinator.updateMetrics(h.scroll.position);
  await tester.pumpAndSettle();
  return h;
}

class _Harness {
  _Harness(
    ThreadQuickScrollDockSide side,
    EdgeInsets padding,
    bool disableAnimations,
    Future<ThreadQuickScrollDockSide>? load,
  ) : repository = _Repository(side, load),
      media = ValueNotifier(
        MediaQueryData(
          size: const Size(800, 600),
          padding: padding,
          viewPadding: padding,
          disableAnimations: disableAnimations,
        ),
      ) {
    coordinator = ThreadDetailQuickScrollCoordinator(scrollController: scroll);
    scroll.addListener(() => coordinator.updateMetrics(scroll.position));
  }

  final _Repository repository;
  final ValueNotifier<MediaQueryData> media;
  final page = ValueNotifier('first-thread');
  final hasContent = ValueNotifier(true);
  final scroll = ScrollController();
  late final ThreadDetailQuickScrollCoordinator coordinator;

  ThreadQuickScrollPreferencesController controller(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(_button),
      ).read(threadQuickScrollPreferencesControllerProvider.notifier);

  Widget app() => ProviderScope(
    overrides: [
      threadQuickScrollPreferencesRepositoryProvider.overrideWithValue(
        repository,
      ),
    ],
    child: LocalizedTestApp(
      home: ListenableBuilder(
        listenable: Listenable.merge([media, page, hasContent]),
        builder: (context, _) => MediaQuery(
          data: media.value,
          child: Consumer(
            builder: (context, ref, _) {
              final side =
                  ref
                      .watch(threadQuickScrollPreferencesControllerProvider)
                      .value ??
                  _right;
              return Scaffold(
                appBar: AppBar(title: const Text('fixture')),
                body: SingleChildScrollView(
                  controller: scroll,
                  child: const SizedBox(height: 2400),
                ),
                floatingActionButtonLocation: ThreadQuickScrollDockLocation(
                  side,
                ),
                floatingActionButtonAnimator:
                    FloatingActionButtonAnimator.noAnimation,
                floatingActionButton: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ThreadDetailQuickScrollDock(
                    key: ValueKey(page.value),
                    coordinator: coordinator,
                    hasContent: hasContent.value,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  void dispose() {
    coordinator.dispose();
    scroll.dispose();
    page.dispose();
    media.dispose();
    hasContent.dispose();
  }
}

class _Repository implements ThreadQuickScrollPreferencesRepository {
  _Repository(this.side, this.load);
  ThreadQuickScrollDockSide side;
  final Future<ThreadQuickScrollDockSide>? load;
  final writes = <ThreadQuickScrollDockSide>[];
  bool failWrite = false;

  @override
  Future<ThreadQuickScrollDockSide> loadSide() async => load ?? side;

  @override
  Future<void> saveSide(ThreadQuickScrollDockSide value) async {
    writes.add(value);
    if (failWrite) throw StateError('write failed');
    side = value;
  }
}
