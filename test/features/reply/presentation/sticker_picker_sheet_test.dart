import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/widgets/sticker_picker_sheet.dart';

void main() {
  testWidgets('StickerPickerSheet shows loading state', (tester) async {
    final completer = Completer<List<StickerGroup>>();
    await tester.pumpWidget(
      _buildSheet(
        loadGroups: () => completer.future,
      ),
    );

    expect(find.byKey(const Key('reply-sticker-picker-loading')), findsOneWidget);
  });

  testWidgets('StickerPickerSheet shows error state', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        loadGroups: () async {
          throw StateError('boom');
        },
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reply-sticker-picker-error')), findsOneWidget);
  });

  testWidgets('StickerPickerSheet shows empty state', (tester) async {
    await tester.pumpWidget(
      _buildSheet(
        loadGroups: () async => const [],
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reply-sticker-picker-empty')), findsOneWidget);
  });

  testWidgets('StickerPickerSheet shows groups and returns selected sticker', (
    tester,
  ) async {
    StickerItem? selected;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stickerGroupsProvider.overrideWith((_) async => _groups),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: StickerPickerSheet(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reply-sticker-group-tab-group-0')), findsOneWidget);
    expect(find.byKey(const Key('reply-sticker-item-{:9_656:}')), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stickerGroupsProvider.overrideWith((_) async => _groups),
        ],
        child: MaterialApp(
          home: _PickerLauncher(
            onSelected: (sticker) {
              selected = sticker;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-sticker-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reply-sticker-item-{:9_656:}')));
    await tester.pumpAndSettle();

    expect(selected?.code, '{:9_656:}');
  });
}

const _groups = [
  StickerGroup(
    id: 'group-0',
    title: 'group-0',
    stickers: [
      StickerItem(
        code: '{:9_656:}',
        assetPath: 'assets/stickers/bugcat/Capoo16.gif',
        rawCodePattern: '{:9_656:}',
      ),
    ],
  ),
];

Widget _buildSheet({
  required Future<List<StickerGroup>> Function() loadGroups,
}) {
  return ProviderScope(
    overrides: [
      stickerGroupsProvider.overrideWith((_) => loadGroups()),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: StickerPickerSheet(),
      ),
    ),
  );
}

class _PickerLauncher extends StatelessWidget {
  const _PickerLauncher({
    required this.onSelected,
  });

  final ValueChanged<StickerItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FilledButton(
        key: const Key('open-sticker-picker'),
        onPressed: () async {
          final sticker = await showModalBottomSheet<StickerItem>(
            context: context,
            builder: (_) => const StickerPickerSheet(),
          );
          if (sticker != null) {
            onSelected(sticker);
          }
        },
        child: const Text('open'),
      ),
    );
  }
}
