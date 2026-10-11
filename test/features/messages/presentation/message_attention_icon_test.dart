import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/messages/presentation/widgets/message_attention_icon.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('attention merges into the entry action in $locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        LocalizedTestApp(
          locale: locale,
          home: Scaffold(
            body: ListTile(
              key: const Key('attention-entry'),
              leading: const MessageAttentionIcon(
                icon: Icons.mail_outline,
                showAttention: true,
              ),
              title: Builder(
                builder: (context) =>
                    Text(AppLocalizations.of(context).moreMyMessages),
              ),
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(MessageAttentionIcon));
      final l10n = AppLocalizations.of(context);
      final action = tester.getSemantics(
        find.byKey(const Key('attention-entry')),
      );
      expect(action.getSemanticsData().label, l10n.moreMyMessages);
      expect(action.getSemanticsData().hint, l10n.messageAttentionAvailable);
      expect(action.childrenCountInTraversalOrder, 0);
      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.backgroundColor, Theme.of(context).colorScheme.error);
      expect(badge.label, isNull);
      expect(badge.isLabelVisible, isTrue);
      expect(
        tester.getSize(find.byType(MessageAttentionIcon)),
        const Size(24, 24),
      );
    });
  }

  testWidgets('normal and selected navigation icons expose a single hint', (
    tester,
  ) async {
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            bottomNavigationBar: ValueListenableBuilder<int>(
              valueListenable: selected,
              builder: (context, selectedIndex, _) => NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) => selected.value = index,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.more_horiz),
                    label: AppLocalizations.of(context).appNavigationMore,
                  ),
                  NavigationDestination(
                    key: const Key('attention-destination'),
                    icon: const MessageAttentionIcon(
                      icon: Icons.mail_outline,
                      showAttention: true,
                    ),
                    selectedIcon: const MessageAttentionIcon(
                      icon: Icons.mail,
                      showAttention: true,
                    ),
                    label: AppLocalizations.of(context).appNavigationMessages,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(const Key('attention-destination'))),
    );
    void expectHint() {
      final action = tester.getSemantics(
        find.byKey(const Key('attention-destination')),
      );
      expect(
        action.getSemanticsData().label,
        contains(l10n.appNavigationMessages),
      );
      expect(action.getSemanticsData().hint, l10n.messageAttentionAvailable);
    }

    expectHint();
    selected.value = 1;
    await tester.pumpAndSettle();
    expectHint();
    expect(find.byIcon(Icons.mail), findsOneWidget);
    expect(find.byIcon(Icons.mail_outline), findsNothing);
  });

  testWidgets('no attention has no hint and leaves the icon size unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: Center(
            child: MessageAttentionIcon(
              icon: Icons.more_horiz,
              showAttention: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    expect(
      tester
          .getSemantics(find.byType(MessageAttentionIcon))
          .getSemanticsData()
          .hint,
      isEmpty,
    );
    expect(
      tester.getSize(find.byType(MessageAttentionIcon)),
      const Size(24, 24),
    );
  });
}
