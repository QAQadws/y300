import 'package:flutter/material.dart';

import '../../../../test_support/localized_test_app.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';

void main() {
  for (final scale in [1.0, 1.5, 3.0]) {
    testWidgets('top overlay fits system text scale $scale', (tester) async {
      var actionTaps = 0;
      final controller = ReaderOverlayController()..showMenu();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _buildScaffold(
          controller: controller,
          textScaler: TextScaler.linear(scale),
          topActions: [
            ReaderToolbarAction(
              id: 'search',
              icon: Icons.search,
              label: 'Search',
              onPressed: () => actionTaps++,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      final bar = tester.getRect(
        find.byKey(const Key('shared-reader-top-overlay-bar')),
      );
      final title = tester.getRect(
        find.byKey(const Key('shared-reader-top-title')),
      );
      final subtitle = tester.getRect(
        find.byKey(const Key('shared-reader-top-subtitle')),
      );
      expect(title.top, greaterThanOrEqualTo(bar.top));
      expect(title.bottom, lessThanOrEqualTo(subtitle.top));
      expect(subtitle.bottom, lessThanOrEqualTo(bar.bottom));
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byKey(const Key('shared-reader-top-title'))),
        ).scale(16),
        16 * scale,
      );
      await tester.tap(
        find.byKey(const Key('shared-reader-top-action-search')),
      );
      expect(actionTaps, 1);
      controller.hideMenu();
      await tester.pumpAndSettle();
      expect(controller.contentObscured.value, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'body obstruction outlives desired visibility through slide out',
    (tester) async {
      final controller = ReaderOverlayController();
      addTearDown(controller.dispose);
      final menuEvents = <bool>[];
      final obstructionEvents = <bool>[];
      controller.addListener(() => menuEvents.add(controller.isMenuVisible));
      controller.contentObscured.addListener(
        () => obstructionEvents.add(controller.contentObscured.value),
      );
      await tester.pumpWidget(
        _buildScaffold(
          controller: controller,
          animationDuration: const Duration(milliseconds: 240),
        ),
      );

      controller.showMenu();
      expect(controller.contentObscured.value, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));

      controller.hideMenu();
      expect(controller.isMenuVisible, isFalse);
      expect(controller.contentObscured.value, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(controller.contentObscured.value, isTrue);
      expect(menuEvents, [true, false]);
      expect(obstructionEvents, [true]);

      await tester.pump(const Duration(milliseconds: 120));
      expect(controller.contentObscured.value, isFalse);
      expect(obstructionEvents, [true, false]);
      expect(menuEvents, [true, false]);
    },
  );

  testWidgets('reversing a closing menu never clears body obstruction', (
    tester,
  ) async {
    final controller = ReaderOverlayController()..showMenu();
    addTearDown(controller.dispose);
    final events = <bool>[];
    controller.contentObscured.addListener(
      () => events.add(controller.contentObscured.value),
    );
    await tester.pumpWidget(
      _buildScaffold(
        controller: controller,
        animationDuration: const Duration(milliseconds: 240),
      ),
    );

    controller.hideMenu();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    controller.showMenu();
    await tester.pumpAndSettle();
    expect(controller.contentObscured.value, isTrue);
    expect(events, [true]);

    controller.hideMenu();
    await tester.pumpAndSettle();
    expect(events, [true, false]);
  });

  testWidgets(
    'detached commands preserve visibility without body obstruction',
    (tester) async {
      final controller = ReaderOverlayController()..showMenu();
      addTearDown(controller.dispose);
      expect(controller.isMenuVisible, isTrue);
      expect(controller.contentObscured.value, isFalse);

      await tester.pumpWidget(_buildScaffold(controller: controller));
      expect(controller.contentObscured.value, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(controller.isMenuVisible, isTrue);
      expect(controller.contentObscured.value, isFalse);

      await tester.pumpWidget(_buildScaffold(controller: controller));
      expect(controller.contentObscured.value, isTrue);
      controller.hideMenu();
      await tester.pump();
      expect(controller.contentObscured.value, isFalse);
    },
  );

  testWidgets(
    'initial visible menu and replacement binding report obstruction',
    (tester) async {
      final first = ReaderOverlayController();
      final second = ReaderOverlayController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final firstMenuEvents = <bool>[];
      first.addListener(() => firstMenuEvents.add(first.isMenuVisible));
      await tester.pumpWidget(
        _buildScaffold(
          controller: first,
          menuInitiallyVisible: true,
          animationDuration: const Duration(milliseconds: 240),
        ),
      );
      expect(first.contentObscured.value, isTrue);
      expect(firstMenuEvents, isEmpty);

      await tester.pumpWidget(
        _buildScaffold(
          controller: second,
          animationDuration: const Duration(milliseconds: 240),
        ),
      );
      expect(first.contentObscured.value, isFalse);
      expect(second.isMenuVisible, isFalse);
      expect(second.contentObscured.value, isTrue);
      first.hideMenu();
      first.showMenu();
      await tester.pumpAndSettle();
      expect(first.isMenuVisible, isTrue);
      expect(first.contentObscured.value, isFalse);
      expect(second.contentObscured.value, isFalse);
    },
  );

  testWidgets('old scaffold disposal cannot detach a newer bound scaffold', (
    tester,
  ) async {
    final controller = ReaderOverlayController()..showMenu();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _buildScaffold(controller: controller, overlayKey: const ValueKey(1)),
    );
    await tester.pumpWidget(
      _buildScaffold(controller: controller, overlayKey: const ValueKey(2)),
    );
    expect(controller.contentObscured.value, isTrue);
    controller.hideMenu();
    await tester.pump();
    expect(controller.isMenuVisible, isFalse);
    expect(controller.contentObscured.value, isFalse);
  });

  testWidgets('synchronous menu reversal publishes current obstruction', (
    tester,
  ) async {
    final controller = ReaderOverlayController();
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.isMenuVisible) controller.hideMenu();
    });
    final events = <bool>[];
    controller.contentObscured.addListener(
      () => events.add(controller.contentObscured.value),
    );
    await tester.pumpWidget(_buildScaffold(controller: controller));
    controller.showMenu();
    await tester.pumpAndSettle();
    expect(controller.isMenuVisible, isFalse);
    expect(controller.contentObscured.value, isFalse);
    expect(events, isEmpty);
  });

  testWidgets('disposed controller ignores late animation and detach signals', (
    tester,
  ) async {
    final controller = ReaderOverlayController()..showMenu();
    final events = <bool>[];
    controller.contentObscured.addListener(
      () => events.add(controller.contentObscured.value),
    );
    await tester.pumpWidget(
      _buildScaffold(
        controller: controller,
        animationDuration: const Duration(milliseconds: 240),
      ),
    );
    controller.hideMenu();
    controller.dispose();
    controller.toggleMenu();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(events, [true]);
    expect(controller.contentObscured.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final disposeFromContentSignal in [true, false]) {
    testWidgets('controller can retire during its own signal dispatch '
        '(content: $disposeFromContentSignal)', (tester) async {
      final controller = ReaderOverlayController();
      await tester.pumpWidget(_buildScaffold(controller: controller));
      if (disposeFromContentSignal) {
        controller.contentObscured.addListener(controller.dispose);
      } else {
        controller.addListener(controller.dispose);
      }
      controller.showMenu();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

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

  testWidgets('overlay controls are excluded from reader tap zones', (
    tester,
  ) async {
    var actionTaps = 0;
    final controller = ReaderOverlayController()..showMenu();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _buildScaffold(
        controller: controller,
        bottomActions: [
          ReaderToolbarAction(
            id: 'display',
            icon: Icons.tune,
            label: '显示',
            onPressed: () => actionTaps += 1,
          ),
        ],
      ),
    );

    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-display')),
    );
    await tester.pump(const Duration(milliseconds: 330));

    expect(actionTaps, 1);
    expect(controller.isMenuVisible, isTrue);
  });

  testWidgets('ReaderOverlayScaffold center callback keeps default toggle', (
    tester,
  ) async {
    var centerTaps = 0;
    await tester.pumpWidget(_buildScaffold(onCenterTap: () => centerTaps += 1));

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

  testWidgets(
    'ReaderOverlayScaffold uses reader chrome background in dark theme',
    (tester) async {
      final theme = AppTheme.dark();
      final palette = const ReaderChromePaletteResolver().resolve(theme);

      await tester.pumpWidget(
        _buildScaffold(theme: theme, menuInitiallyVisible: true),
      );

      final top = tester.widget<Material>(
        find.byKey(const Key('shared-reader-top-overlay-bar')),
      );
      final bottom = tester.widget<Material>(
        find.byKey(const Key('shared-reader-bottom-overlay-panel')),
      );

      expect(top.color, palette.chromeBackground);
      expect(bottom.color, palette.chromeBackground);
    },
  );
}

Future<void> _pumpTapAndOverlayAnimation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 330));
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump();
}

Widget _buildScaffold({
  bool menuInitiallyVisible = false,
  List<ReaderToolbarAction> topActions = const <ReaderToolbarAction>[],
  List<ReaderToolbarAction> bottomActions = const <ReaderToolbarAction>[],
  VoidCallback? onCenterTap,
  ReaderOverlayController? controller,
  ThemeData? theme,
  Duration animationDuration = Duration.zero,
  Key? overlayKey,
  TextScaler? textScaler,
}) {
  return LocalizedTestApp(
    theme: theme,
    builder: textScaler == null
        ? null
        : (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
    home: Scaffold(
      body: ReaderOverlayScaffold(
        key: overlayKey,
        controller: controller,
        menuInitiallyVisible: menuInitiallyVisible,
        animationDuration: animationDuration,
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
          actions: bottomActions,
        ),
        child: const ColoredBox(color: Colors.white),
      ),
    ),
  );
}
