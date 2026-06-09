import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';

enum _Action {
  first,
  second,
}

void main() {
  testWidgets('ReaderActionSheet renders actions in order and returns value', (
    tester,
  ) async {
    _Action? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selected = await showModalBottomSheet<_Action>(
                  context: context,
                  builder: (_) => const ReaderActionSheet<_Action>(
                    title: '更多',
                    items: [
                      ReaderActionSheetItem<_Action>(
                        id: 'first',
                        value: _Action.first,
                        icon: Icons.looks_one,
                        label: '第一项',
                      ),
                      ReaderActionSheetItem<_Action>(
                        id: 'second',
                        value: _Action.second,
                        icon: Icons.looks_two,
                        label: '第二项',
                      ),
                    ],
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shared-reader-action-sheet')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('第一项')).dy,
      lessThan(tester.getTopLeft(find.text('第二项')).dy),
    );

    await tester.tap(find.byKey(const Key('shared-reader-action-second')));
    await tester.pumpAndSettle();

    expect(selected, _Action.second);
  });

  testWidgets('ReaderActionSheet disables actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReaderActionSheet<_Action>(
            title: '更多',
            items: [
              ReaderActionSheetItem<_Action>(
                id: 'first',
                value: _Action.first,
                icon: Icons.looks_one,
                label: '第一项',
                enabled: false,
              ),
            ],
          ),
        ),
      ),
    );

    final tile = tester.widget<ListTile>(
      find.byKey(const Key('shared-reader-action-first')),
    );
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);
  });
}
