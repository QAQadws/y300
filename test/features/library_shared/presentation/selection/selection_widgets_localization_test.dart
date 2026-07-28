import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_action_bar.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_app_bar.dart';
import 'package:y300/l10n/app_localizations_zh.dart';
import '../../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('SelectionActionBar resolves tooltip from action id', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          bottomNavigationBar: SelectionActionBar(
            actions: const <SelectionAction>[
              SelectionAction(
                id: SelectionActionIds.unfavorite,
                icon: Icons.favorite_border,
                destructive: true,
              ),
            ],
            l10n: AppLocalizationsZh(),
            onActionTap: (_) async {},
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('selection-action-unfavorite')),
    );
    expect(
      button.tooltip,
      AppLocalizationsZh().librarySelectionActionUnfavorite,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('SelectionAppBar localizes title and tooltips', (tester) async {
    final l10n = AppLocalizationsZhTw();
    await tester.pumpWidget(
      LocalizedTestApp(
        locale: const Locale('zh', 'TW'),
        home: Scaffold(
          appBar: SelectionAppBar(
            selectedCount: 2,
            l10n: l10n,
            onClose: () {},
            onSelectAll: () {},
            onInvertSelection: () {},
          ),
        ),
      ),
    );

    expect(find.text(l10n.librarySelectionSelectedCount(2)), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('selection-app-bar-close')))
          .tooltip,
      l10n.librarySelectionExit,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('selection-app-bar-select-all')),
          )
          .tooltip,
      l10n.librarySelectionSelectAll,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('selection-app-bar-invert')))
          .tooltip,
      l10n.librarySelectionInvert,
    );
  });
}
