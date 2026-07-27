import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';

void main() {
  testWidgets('ReaderBottomOverlayPanel renders actions in order', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPanel(
        actions: [
          _action(id: 'catalog', icon: Icons.list, label: '目录'),
          _action(id: 'display', icon: Icons.tune, label: '显示'),
          _action(id: 'cache', icon: Icons.download, label: '缓存'),
        ],
      ),
    );

    final catalogCenter = tester.getCenter(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
    );
    final displayCenter = tester.getCenter(
      find.byKey(const Key('shared-reader-bottom-action-display')),
    );
    final cacheCenter = tester.getCenter(
      find.byKey(const Key('shared-reader-bottom-action-cache')),
    );

    expect(catalogCenter.dx, lessThan(displayCenter.dx));
    expect(displayCenter.dx, lessThan(cacheCenter.dx));
  });

  testWidgets('ReaderBottomOverlayPanel disabled action cannot be tapped', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _buildPanel(
        actions: [
          _action(
            id: 'cache',
            icon: Icons.download,
            label: '缓存',
            enabled: false,
            onPressed: () => taps += 1,
          ),
        ],
      ),
    );

    await tester.tap(
      find.byKey(const Key('shared-reader-bottom-action-cache')),
    );
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('ReaderBottomOverlayPanel can hide progress control', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPanel(
        includeProgress: false,
        actions: [_action(id: 'catalog', icon: Icons.list, label: '目录')],
      ),
    );

    expect(
      find.byKey(const Key('shared-reader-progress-slider')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('shared-reader-bottom-action-catalog')),
      findsOneWidget,
    );
  });
}

Widget _buildPanel({
  required List<ReaderToolbarAction> actions,
  bool includeProgress = true,
}) {
  return LocalizedTestApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: ReaderBottomOverlayPanel(
          config: ReaderBottomBarConfig(
            actions: actions,
            progress: includeProgress
                ? ReaderProgressConfig(
                    current: 1,
                    total: 10,
                    onChanged: (_) {},
                    onChangeEnd: (_) {},
                  )
                : null,
          ),
        ),
      ),
    ),
  );
}

ReaderToolbarAction _action({
  required String id,
  required IconData icon,
  required String label,
  bool enabled = true,
  VoidCallback? onPressed,
}) {
  return ReaderToolbarAction(
    id: id,
    icon: icon,
    label: label,
    enabled: enabled,
    onPressed: onPressed ?? () {},
  );
}
