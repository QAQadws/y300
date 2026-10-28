import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/messages/presentation/widgets/conversation_latest_button.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      testWidgets('$family $brightness keeps a clear arrow on a quiet surface', (
        tester,
      ) async {
        var taps = 0;
        await tester.pumpWidget(
          LocalizedTestApp(
            theme: AppTheme.build(family: family, brightness: brightness),
            home: Scaffold(
              body: Center(
                child: ConversationLatestButton(onPressed: () => taps++),
              ),
            ),
          ),
        );
        final button = tester.widget<IconButton>(find.byType(IconButton));
        final context = tester.element(find.byType(ConversationLatestButton));
        final palette = Theme.of(context).y300NativeContent;
        final surface = button.style!.backgroundColor!.resolve({})!;
        final arrow = button.style!.foregroundColor!.resolve({})!;
        expect(surface.a, greaterThan(0));
        expect(surface.a, lessThan(0.5));
        expect(arrow.a, 1);
        for (final underlying in [palette.background, palette.card]) {
          final visibleSurface = Color.alphaBlend(surface, underlying);
          final light = math.max(
            arrow.computeLuminance(),
            visibleSurface.computeLuminance(),
          );
          final dark = math.min(
            arrow.computeLuminance(),
            visibleSurface.computeLuminance(),
          );
          expect((light + 0.05) / (dark + 0.05), greaterThanOrEqualTo(3));
        }
        final target = tester.getSize(find.byType(ConversationLatestButton));
        expect(target.width, inInclusiveRange(44, 48));
        expect(target.height, inInclusiveRange(44, 48));
        await tester.tap(find.byType(IconButton));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('icon-only action keeps its accessible tooltip in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        LocalizedTestApp(
          locale: locale,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ConversationLatestButton(onPressed: () {}),
            ),
          ),
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ConversationLatestButton)),
      );
      expect(find.text(l10n.messageLatest), findsNothing);
      expect(find.byTooltip(l10n.messageLatest), findsOneWidget);
      final semantics = tester.getSemantics(find.byType(IconButton));
      expect(semantics.getSemanticsData().tooltip, l10n.messageLatest);
      expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(semantics.childrenCountInTraversalOrder, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
