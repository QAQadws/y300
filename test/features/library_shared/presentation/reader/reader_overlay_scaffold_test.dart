import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';

void main() {
  testWidgets('ReaderOverlayScaffold hides menu by default', (tester) async {
    await tester.pumpWidget(_buildScaffold());

    final top = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    final bottom = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-bottom-overlay-hit-test-gate')),
    );

    expect(top.ignoring, isTrue);
    expect(bottom.ignoring, isTrue);
  });

  testWidgets('ReaderOverlayScaffold center tap toggles menu visibility', (
    tester,
  ) async {
    await tester.pumpWidget(_buildScaffold());

    await tester.tapAt(const Offset(400, 300));
    await _pumpTapAndOverlayAnimation(tester);

    var top = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(top.ignoring, isFalse);

    await tester.tapAt(const Offset(400, 300));
    await _pumpTapAndOverlayAnimation(tester);

    top = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(top.ignoring, isTrue);
  });

  testWidgets('ReaderOverlayScaffold respects initially visible menu', (
    tester,
  ) async {
    await tester.pumpWidget(_buildScaffold(menuInitiallyVisible: true));

    final top = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );

    expect(top.ignoring, isFalse);
  });

  testWidgets('ReaderOverlayScaffold overlay action triggers callback', (
    tester,
  ) async {
    var actionTaps = 0;
    await tester.pumpWidget(
      _buildScaffold(
        menuInitiallyVisible: true,
        topActions: [
          ReaderToolbarAction(
            id: 'search',
            icon: Icons.search,
            label: '搜索',
            onPressed: () => actionTaps += 1,
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('shared-reader-top-action-search')));
    await tester.pump();

    expect(actionTaps, 1);
  });

  testWidgets('ReaderOverlayScaffold center callback keeps default toggle', (
    tester,
  ) async {
    var centerTaps = 0;
    await tester.pumpWidget(
      _buildScaffold(
        onCenterTap: () => centerTaps += 1,
      ),
    );

    await tester.tapAt(const Offset(400, 300));
    await _pumpTapAndOverlayAnimation(tester);

    final top = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(centerTaps, 1);
    expect(top.ignoring, isFalse);
  });

  testWidgets('ReaderOverlayScaffold controller can hide visible menu', (
    tester,
  ) async {
    final controller = ReaderOverlayController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_buildScaffold(controller: controller));

    await tester.tapAt(const Offset(400, 300));
    await _pumpTapAndOverlayAnimation(tester);

    var top = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(top.ignoring, isFalse);
    expect(controller.isMenuVisible, isTrue);

    controller.hideMenu();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();

    top = tester.widget<IgnorePointer>(
      find.byKey(const Key('shared-reader-top-overlay-hit-test-gate')),
    );
    expect(top.ignoring, isTrue);
    expect(controller.isMenuVisible, isFalse);
  });
}

Future<void> _pumpTapAndOverlayAnimation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 330));
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump();
}

Widget _buildScaffold({
  bool menuInitiallyVisible = false,
  List<ReaderToolbarAction> topActions = const <ReaderToolbarAction>[],
  VoidCallback? onCenterTap,
  ReaderOverlayController? controller,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ReaderOverlayScaffold(
        controller: controller,
        menuInitiallyVisible: menuInitiallyVisible,
        animationDuration: Duration.zero,
        onCenterTap: onCenterTap,
        topBar: ReaderTopBarConfig(
          title: '作品名',
          subtitle: '章节名',
          actions: topActions,
          onBack: () {},
        ),
        bottomBar: ReaderBottomBarConfig(
          progress: ReaderProgressConfig(
            current: 1,
            total: 10,
            onChanged: (_) {},
            onChangeEnd: (_) {},
          ),
          actions: const <ReaderToolbarAction>[],
        ),
        child: const ColoredBox(color: Colors.white),
      ),
    ),
  );
}
