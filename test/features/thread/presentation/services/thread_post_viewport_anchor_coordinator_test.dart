import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/services/thread_post_viewport_anchor_coordinator.dart';

void main() {
  testWidgets('restores the first visible pid and its local offset', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_AnchorHarnessState>();
    await tester.pumpWidget(MaterialApp(home: _AnchorHarness(key: harnessKey)));
    await tester.pump();
    harnessKey.currentState!.controller.jumpTo(120);
    await tester.pump();

    final before = _relativeTop(tester, '2');
    harnessKey.currentState!.applyProjection();
    await tester.pump();
    await tester.pump();

    expect(_relativeTop(tester, '2'), closeTo(before, 0.5));
    expect(harnessKey.currentState!.controller.offset, closeTo(240, 0.5));
  });

  testWidgets('keeps the leading edge pinned during projection changes', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_AnchorHarnessState>();
    await tester.pumpWidget(MaterialApp(home: _AnchorHarness(key: harnessKey)));
    await tester.pump();

    harnessKey.currentState!.applyProjection();
    await tester.pump();
    await tester.pump();

    expect(harnessKey.currentState!.controller.offset, 0);
  });

  testWidgets('falls back to the previous clamped offset when pid disappears', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_AnchorHarnessState>();
    await tester.pumpWidget(MaterialApp(home: _AnchorHarness(key: harnessKey)));
    await tester.pump();
    harnessKey.currentState!.controller.jumpTo(120);
    await tester.pump();

    harnessKey.currentState!.applyProjection(removeSecondPost: true);
    await tester.pump();
    await tester.pump();

    expect(harnessKey.currentState!.controller.offset, closeTo(120, 0.5));
  });
}

double _relativeTop(WidgetTester tester, String pid) {
  final viewportTop = tester
      .getTopLeft(find.byKey(const Key('anchor-viewport')))
      .dy;
  final postTop = tester.getTopLeft(find.byKey(Key('anchor-item-$pid'))).dy;
  return postTop - viewportTop;
}

class _AnchorHarness extends StatefulWidget {
  const _AnchorHarness({super.key});

  @override
  State<_AnchorHarness> createState() => _AnchorHarnessState();
}

class _AnchorHarnessState extends State<_AnchorHarness> {
  final controller = ScrollController();
  final viewportKey = GlobalKey();
  late final ThreadPostViewportAnchorCoordinator coordinator;
  var firstHeight = 100.0;
  var pids = <String>['1', '2', '3', '4'];

  @override
  void initState() {
    super.initState();
    coordinator = ThreadPostViewportAnchorCoordinator(
      scrollController: controller,
      viewportKey: viewportKey,
    );
  }

  void applyProjection({bool removeSecondPost = false}) {
    final snapshot = coordinator.capture(pids);
    setState(() {
      firstHeight = 220;
      if (removeSecondPost) {
        pids = <String>['1', '3', '4'];
      }
    });
    coordinator.prune(pids);
    coordinator.restoreAfterFrame(snapshot);
  }

  @override
  void dispose() {
    coordinator.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: viewportKey,
          width: 300,
          height: 200,
          child: SizedBox.expand(
            key: const Key('anchor-viewport'),
            child: ListView(
              controller: controller,
              children: <Widget>[
                for (final pid in pids)
                  KeyedSubtree(
                    key: coordinator.keyForPid(pid),
                    child: SizedBox(
                      key: Key('anchor-item-$pid'),
                      height: pid == '1' ? firstHeight : 100,
                      child: Text(pid),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
