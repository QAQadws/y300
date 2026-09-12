import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/presentation/services/read_access_feedback.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_read_access_tile.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  const access = ThreadReadAccess(
    canModify: true,
    currentValue: 0,
    options: [
      ThreadReadAccessOption(value: 0),
      ThreadReadAccessOption(value: 20, groupNames: ['组 A', '組 B']),
      ThreadReadAccessOption(value: 255),
    ],
  );

  testWidgets(
    'localized choices retain server labels and return numeric thresholds',
    (tester) async {
      for (final locale in [const Locale('zh'), const Locale('zh', 'TW')]) {
        int? selected;
        await tester.pumpWidget(
          LocalizedTestApp(
            locale: locale,
            home: Scaffold(
              body: ComposerReadAccessTile(
                access: access,
                selectedValue: 0,
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ComposerReadAccessTile)),
        );
        expect(find.text(l10n.composerReadAccessUnlimited), findsOneWidget);
        await tester.tap(find.byType(ComposerReadAccessTile));
        await tester.pumpAndSettle();
        expect(find.text('组 A / 組 B'), findsOneWidget);
        expect(find.text(l10n.composerReadAccessHighest), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('read-access-option-20')));
        await tester.pumpAndSettle();
        expect(selected, 20);
        expect(
          readAccessFeedback(
            l10n,
            const ThreadReadAccessEvidence(
              kind: ThreadReadAccessEvidenceKind.serverAdjusted,
              requested: 20,
              actual: 0,
            ),
          ),
          l10n.composerReadAccessAdjusted(20, 0),
        );
        expect(
          readAccessFeedback(
            l10n,
            const ThreadReadAccessEvidence(
              kind: ThreadReadAccessEvidenceKind.unverified,
              requested: 0,
            ),
          ),
          l10n.composerReadAccessUnverified(0),
        );
      }
    },
  );

  testWidgets('obsolete edit threshold remains an explicit keep choice', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: ComposerReadAccessTile(
            access: access.withCurrentValue(37),
            selectedValue: 37,
            preservingExisting: true,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ComposerReadAccessTile)),
    );
    expect(find.text(l10n.composerReadAccessKeep(37)), findsOneWidget);
    await tester.tap(find.byType(ComposerReadAccessTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('read-access-option-37')));
    await tester.pumpAndSettle();
    expect(selected, 37);
  });

  testWidgets('unavailable and loading controls cannot open the selector', (
    tester,
  ) async {
    for (final enabled in [true, false]) {
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Scaffold(
            body: ComposerReadAccessTile(
              access: enabled ? ThreadReadAccess.unavailable : access,
              selectedValue: 0,
              enabled: enabled,
              onChanged: (_) => fail('disabled control changed'),
            ),
          ),
        ),
      );
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    }
  });
}
