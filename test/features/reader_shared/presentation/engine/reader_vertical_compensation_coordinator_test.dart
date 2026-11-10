import 'package:continuous_image_geometry/continuous_image_geometry.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_vertical_compensation_coordinator.dart';

void main() {
  testWidgets('extent corrections coalesce and read current pixels at flush', (
    tester,
  ) async {
    final host = await _host(tester);
    host.flow.applyPlan(_plan(100));
    host.flow.applyPlan(_plan(200));
    host.scroll.jumpTo(1100);
    host.scroll.jumps.clear();
    expect(host.frames.pending, hasLength(1));
    await host.frames.run();
    expect(host.scroll.offset, 1400);
    expect(host.scroll.jumps, [1400]);
  });

  testWidgets('active scrolling defers all corrections until idle', (
    tester,
  ) async {
    final host = await _host(tester);
    host.scroll.position.isScrollingNotifier.value = true;
    host.flow.applyPlan(_plan(80));
    host.flow.applyPlan(
      ContinuousImageScrollCompensationPlan.deferred(
        delta: 120,
        targetOffset: 1120,
      ),
    );
    expect(host.frames.pending, isEmpty);
    host.scroll.position.isScrollingNotifier.value = false;
    await host.frames.run();
    expect(host.scroll.jumps, [1200]);
  });

  testWidgets('scroll starting before frame retains the queued correction', (
    tester,
  ) async {
    final host = await _host(tester);
    host.flow.applyPlan(_plan(100));
    host.scroll.position.isScrollingNotifier.value = true;
    await host.frames.run();
    expect(host.scroll.jumps, isEmpty);
    host.scroll.position.isScrollingNotifier.value = false;
    await host.frames.run();
    expect(host.scroll.offset, 1100);
  });

  testWidgets(
    'non-idle direction blocks a stopped activity until scroll sync',
    (tester) async {
      final host = await _host(tester);
      final position = host.scroll.position as ScrollPositionWithSingleContext;
      position.updateUserScrollDirection(ScrollDirection.forward);
      host.flow.applyPlan(_plan(100));
      expect(host.frames.pending, isEmpty);
      position.updateUserScrollDirection(ScrollDirection.idle);
      host.flow.flushIfIdle();
      await host.frames.run();
      expect(host.scroll.offset, 1100);
    },
  );

  testWidgets('spacing compares a stable anchor and queues its shift once', (
    tester,
  ) async {
    final host = await _host(tester);
    var anchor = 1000.0;
    host.spacing(0, () => anchor);
    host.spacing(24, () => anchor);
    anchor = 1048;
    await host.frames.run();
    await host.frames.run();
    expect(host.scroll.jumps, [1048]);
  });

  testWidgets('rapid spacing previews keep only the latest measurement', (
    tester,
  ) async {
    final host = await _host(tester);
    var anchor = 1000.0;
    host.spacing(0, () => anchor);
    host.spacing(24, () => anchor);
    host.spacing(48, () => anchor);
    anchor = 1096;
    await host.frames.run();
    await host.frames.run();
    expect(host.scroll.jumps, [1096]);
  });

  for (final extentFirst in [false, true]) {
    testWidgets(
      'one layout counts extent and spacing shift once, extentFirst=$extentFirst',
      (tester) async {
        final host = await _host(tester);
        var anchor = 1000.0;
        host.spacing(0, () => anchor);
        host.spacing(24, () => anchor);
        anchor = 1120;
        if (extentFirst) host.flow.applyPlan(_plan(100));
        final measured = host.frames.run();
        if (!extentFirst) host.flow.applyPlan(_plan(100));
        await measured;
        await host.frames.run();
        expect(host.scroll.jumps, [1120]);
      },
    );
  }

  testWidgets(
    'extent pending before capture remains an independent correction',
    (tester) async {
      final host = await _host(tester);
      host.flow.applyPlan(_plan(100));
      var anchor = 1100.0;
      host.spacing(0, () => anchor);
      host.spacing(24, () => anchor);
      anchor = 1120;
      await host.frames.run();
      await host.frames.run();
      expect(host.scroll.jumps, [1120]);
    },
  );

  testWidgets(
    'invalid final anchor releases an otherwise valid extent correction',
    (tester) async {
      final host = await _host(tester);
      double? anchor = 1000;
      host.spacing(0, () => anchor);
      host.spacing(24, () => anchor);
      host.flow.applyPlan(_plan(100));
      anchor = null;
      await host.frames.run();
      await host.frames.run();
      expect(host.scroll.jumps, [1100]);
    },
  );

  testWidgets('drain clamps once and consumes the clamped remainder', (
    tester,
  ) async {
    final host = await _host(tester);
    final maximum = host.scroll.position.maxScrollExtent;
    host.flow.applyPlan(_plan(maximum));
    await host.frames.run();
    expect(host.scroll.offset, maximum);
    host.scroll.jumpTo(1000);
    host.scroll.jumps.clear();
    host.flow.flushIfIdle();
    await host.frames.run();
    expect(host.scroll.jumps, isEmpty);
  });

  testWidgets(
    'opposite deltas cancel and invalid plans do not move the viewport',
    (tester) async {
      final host = await _host(tester);
      host.flow.applyPlan(_plan(100));
      host.flow.applyPlan(_plan(-100));
      host.flow.applyPlan(ContinuousImageScrollCompensationPlan.none());
      host.flow.applyPlan(_plan(double.nan));
      host.flow.applyPlan(_plan(double.infinity));
      host.flow.applyPlan(_plan(0.4));
      await host.frames.run();
      expect(host.scroll.jumps, isEmpty);
    },
  );

  for (final retire in ['cancel', 'deactivate', 'close']) {
    testWidgets('$retire retires both spacing and queued extent callbacks', (
      tester,
    ) async {
      final host = await _host(tester);
      var anchor = 1000.0;
      host.spacing(0, () => anchor);
      host.spacing(24, () => anchor);
      host.flow.applyPlan(_plan(100));
      switch (retire) {
        case 'cancel':
          host.flow.cancelPending();
        case 'deactivate':
          host.flow.deactivate();
        case 'close':
          host.flow.close();
      }
      anchor = 1100;
      await host.frames.run();
      await host.frames.run();
      expect(host.scroll.jumps, isEmpty);
    });
  }

  testWidgets(
    'cancelling between measurement and microtask retires its commit',
    (tester) async {
      final host = await _host(tester);
      var anchor = 1000.0;
      host.spacing(0, () => anchor);
      host.spacing(24, () => anchor);
      anchor = 1100;
      final measured = host.frames.run();
      host.flow.cancelPending();
      await measured;
      await host.frames.run();
      expect(host.scroll.jumps, isEmpty);
    },
  );

  testWidgets(
    'same binding rebuild retains queued work and newest owner rejects old frames',
    (tester) async {
      final host = await _host(tester);
      host.flow.applyPlan(_plan(100));
      host.bind();
      await host.frames.run();
      expect(host.scroll.offset, 1100);
      host.scroll.jumps.clear();
      host.flow.applyPlan(_plan(100));
      host.session = Object();
      host.bind();
      host.flow.applyPlan(_plan(40));
      await host.frames.run();
      expect(host.scroll.jumps, [1140]);
    },
  );

  testWidgets('inactive owner rejects work and cannot update spacing state', (
    tester,
  ) async {
    final host = await _host(tester);
    host.current = false;
    host.flow.applyPlan(_plan(100));
    host.spacing(24, () => 1000);
    expect(host.frames.pending, isEmpty);
    host.current = true;
    host.spacing(48, () => 1000);
    expect(host.frames.pending, isEmpty);
  });

  testWidgets(
    'replacing ScrollPosition retires corrections attached to the old viewport',
    (tester) async {
      final host = await _host(tester);
      host.flow.applyPlan(_plan(100));
      await tester.pumpWidget(_viewport(host.scroll, key: const ValueKey(2)));
      host.flow.syncPosition();
      host.scroll.jumps.clear();
      await host.frames.run();
      expect(host.scroll.jumps, isEmpty);
    },
  );

  testWidgets(
    'close is permanent and old idle notifications cannot schedule work',
    (tester) async {
      final host = await _host(tester);
      host.scroll.position.isScrollingNotifier.value = true;
      host.flow.applyPlan(_plan(100));
      host.flow.close();
      host.scroll.position.isScrollingNotifier.value = false;
      host.bind();
      host.flow.applyPlan(_plan(100));
      await host.frames.run();
      expect(host.scroll.jumps, isEmpty);
      expect(host.frames.pending, isEmpty);
    },
  );
}

ContinuousImageScrollCompensationPlan _plan(double delta) =>
    ContinuousImageScrollCompensationPlan.immediate(
      delta: delta,
      targetOffset: 1000 + delta,
    );

Future<_Host> _host(WidgetTester tester) async {
  final host = _Host();
  addTearDown(() {
    host.flow.close();
    host.scroll.dispose();
  });
  await tester.pumpWidget(_viewport(host.scroll));
  await tester.pumpAndSettle();
  host.scroll.jumpTo(1000);
  host.scroll.jumps.clear();
  host.bind();
  return host;
}

Widget _viewport(ScrollController controller, {Key? key}) => Directionality(
  textDirection: TextDirection.ltr,
  child: ListView.builder(
    key: key,
    controller: controller,
    itemExtent: 100,
    itemCount: 40,
    itemBuilder: (_, _) => const SizedBox(height: 100),
  ),
);

class _Host {
  final scroll = _Scroll();
  final frames = _Frames();
  late final flow = ReaderVerticalCompensationCoordinator(
    scheduleAfterFrame: frames.schedule,
  );
  Object session = Object();
  bool current = true;
  void bind() =>
      flow.bind(session: session, controller: scroll, isCurrent: () => current);
  void spacing(double value, double? Function() anchor) =>
      flow.updatePageSpacing(pageSpacing: value, readAnchorOffset: anchor);
}

class _Scroll extends ScrollController {
  _Scroll() : super(keepScrollOffset: false);
  final jumps = <double>[];
  @override
  void jumpTo(double value) {
    jumps.add(value);
    super.jumpTo(value);
  }
}

class _Frames {
  final pending = <VoidCallback>[];
  void schedule(VoidCallback callback) => pending.add(callback);
  Future<void> run() async {
    final callbacks = List<VoidCallback>.of(pending);
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
    await Future<void>.value();
  }
}
