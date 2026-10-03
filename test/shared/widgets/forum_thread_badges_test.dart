import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/forum_thread_badge_theme.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_thread_badges.dart';

import '../../test_support/localized_test_app.dart';

void main() {
  for (final family in AppThemeFamily.values) {
    for (final brightness in Brightness.values) {
      test('$family $brightness status markers stay distinct and readable', () {
        final theme = AppTheme.build(family: family, brightness: brightness);
        final closed = ForumThreadBadgeColors.resolve(
          theme,
          ForumThreadBadgeKind.closed,
        );
        final digest = ForumThreadBadgeColors.resolve(
          theme,
          ForumThreadBadgeKind.digest,
        );
        final poll = ForumThreadBadgeColors.resolve(
          theme,
          ForumThreadBadgeKind.poll,
        );
        final sticky = ForumThreadBadgeColors.resolve(
          theme,
          ForumThreadBadgeKind.sticky,
        );
        expect(closed.background, isNot(poll.background));
        expect(digest.background, isNot(poll.background));
        expect(closed.background, isNot(digest.background));
        expect(closed.background, theme.colorScheme.error);
        expect(closed.foreground, theme.colorScheme.onError);
        expect(digest.background, theme.colorScheme.secondaryContainer);
        expect(digest.foreground, theme.colorScheme.onSecondaryContainer);
        expect(sticky.background, theme.colorScheme.tertiaryContainer);
        expect(sticky.foreground, theme.colorScheme.onTertiaryContainer);
        expect(poll.background, theme.appBarTheme.backgroundColor);
        expect(poll.foreground, theme.appBarTheme.foregroundColor);
        for (final kind in ForumThreadBadgeKind.values) {
          final colors = ForumThreadBadgeColors.resolve(theme, kind);
          final first = colors.background.computeLuminance();
          final second = colors.foreground.computeLuminance();
          final contrast = first > second
              ? (first + 0.05) / (second + 0.05)
              : (second + 0.05) / (first + 0.05);
          expect(contrast, greaterThanOrEqualTo(4.5), reason: kind.name);
        }
      });
    }
  }

  for (final brightness in Brightness.values) {
    test('digest markers follow each theme family at $brightness', () {
      final digestBackgrounds = <Color>{};
      for (final family in AppThemeFamily.values) {
        final theme = AppTheme.build(family: family, brightness: brightness);
        digestBackgrounds.add(
          ForumThreadBadgeColors.resolve(
            theme,
            ForumThreadBadgeKind.digest,
          ).background,
        );
      }
      expect(digestBackgrounds, hasLength(AppThemeFamily.values.length));
    });
  }

  testWidgets('scheme role changes update the rendered status markers', (
    tester,
  ) async {
    final baseTheme = AppTheme.light();
    final updatedScheme = baseTheme.colorScheme.copyWith(
      error: Colors.indigo,
      onError: Colors.white,
      secondaryContainer: Colors.teal,
      onSecondaryContainer: Colors.black,
      tertiaryContainer: Colors.orange,
      onTertiaryContainer: Colors.brown,
    );
    for (final scheme in [baseTheme.colorScheme, updatedScheme]) {
      final badgeTheme = ForumThreadBadgeTheme.fromColorScheme(
        scheme,
        standardBackground: baseTheme.appBarTheme.backgroundColor,
        standardForeground: baseTheme.appBarTheme.foregroundColor,
      );
      await _pumpBadgeTheme(
        tester,
        baseTheme.copyWith(
          colorScheme: scheme,
          extensions: [
            ...baseTheme.extensions.values.where(
              (extension) => extension is! ForumThreadBadgeTheme,
            ),
            badgeTheme,
          ],
        ),
      );
      _expectThemeColorsWithoutBorders(
        tester,
        ForumThreadBadgeTheme(
          closed: ForumThreadBadgeColors(
            background: scheme.error,
            foreground: scheme.onError,
          ),
          digest: ForumThreadBadgeColors(
            background: scheme.secondaryContainer,
            foreground: scheme.onSecondaryContainer,
          ),
          sticky: ForumThreadBadgeColors(
            background: scheme.tertiaryContainer,
            foreground: scheme.onTertiaryContainer,
          ),
          standard: ForumThreadBadgeColors(
            background: baseTheme.appBarTheme.backgroundColor!,
            foreground: baseTheme.appBarTheme.foregroundColor!,
          ),
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('all markers update from the theme extension without borders', (
    tester,
  ) async {
    const custom = ForumThreadBadgeTheme(
      closed: ForumThreadBadgeColors(
        background: Color(0xFF164A30),
        foreground: Color(0xFFDCFFEA),
      ),
      digest: ForumThreadBadgeColors(
        background: Color(0xFF332267),
        foreground: Color(0xFFF0EAFF),
      ),
      sticky: ForumThreadBadgeColors(
        background: Color(0xFF17476D),
        foreground: Color(0xFFE5F3FF),
      ),
      standard: ForumThreadBadgeColors(
        background: Color(0xFF285454),
        foreground: Color(0xFFE4FFFF),
      ),
    );
    final baseTheme = AppTheme.light();
    Future<void> pumpTheme(ForumThreadBadgeTheme badgeTheme) async {
      await _pumpBadgeTheme(
        tester,
        baseTheme.copyWith(
          extensions: [
            ...baseTheme.extensions.values.where(
              (extension) => extension is! ForumThreadBadgeTheme,
            ),
            badgeTheme,
          ],
        ),
      );
    }

    await pumpTheme(custom);
    _expectThemeColorsWithoutBorders(tester, custom);
    final updated = custom.copyWith(
      closed: const ForumThreadBadgeColors(
        background: Color(0xFF302A74),
        foreground: Color(0xFFF1EDFF),
      ),
      digest: const ForumThreadBadgeColors(
        background: Color(0xFF175959),
        foreground: Color(0xFFE0FFFF),
      ),
    );
    await pumpTheme(updated);
    _expectThemeColorsWithoutBorders(tester, updated);
    expect(tester.takeException(), isNull);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('localizes and wraps combined markers in $locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        LocalizedTestApp(
          theme: AppTheme.light(),
          locale: locale,
          home: const Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 110,
                  child: ForumThreadBadgeGroup(
                    badges: [
                      ForumThreadBadge(
                        kind: ForumThreadBadgeKind.closed,
                        sourceLabel: '关闭的主题',
                      ),
                      ForumThreadBadge(
                        kind: ForumThreadBadgeKind.poll,
                        sourceLabel: '',
                      ),
                      ForumThreadBadge(
                        kind: ForumThreadBadgeKind.digest,
                        sourceLabel: '精华',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final group = find.byType(ForumThreadBadgeGroup);
      final l10n = AppLocalizations.of(tester.element(group));
      expect(find.text('关闭的主题'), findsNothing);
      final groupRect = tester.getRect(group);
      final closed = find.text(l10n.forumThreadBadgeClosed);
      final poll = find.text(l10n.forumThreadBadgePoll);
      final digest = find.text(l10n.forumThreadBadgeDigest);
      for (final marker in [closed, poll, digest]) {
        expect(marker, findsOneWidget);
        final rect = tester.getRect(marker);
        expect(rect.left, greaterThanOrEqualTo(groupRect.left));
        expect(rect.right, lessThanOrEqualTo(groupRect.right));
      }
      expect(
        tester.getRect(digest).top,
        greaterThan(tester.getRect(closed).top),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('keeps unrecognized server marker wording', (tester) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: ForumThreadBadgeGroup(
            badges: [
              ForumThreadBadge(
                kind: ForumThreadBadgeKind.unknown,
                sourceLabel: 'Custom server marker',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Custom server marker'), findsOneWidget);
  });
}

Future<void> _pumpBadgeTheme(WidgetTester tester, ThemeData theme) {
  return tester.pumpWidget(
    LocalizedTestApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: ForumThreadBadgeGroup(
          badges: [
            for (final kind in ForumThreadBadgeKind.values)
              ForumThreadBadge(kind: kind, sourceLabel: 'Source marker'),
          ],
        ),
      ),
    ),
  );
}

void _expectThemeColorsWithoutBorders(
  WidgetTester tester,
  ForumThreadBadgeTheme badgeTheme,
) {
  final group = find.byType(ForumThreadBadgeGroup);
  final containers = tester
      .widgetList<Container>(
        find.descendant(of: group, matching: find.byType(Container)),
      )
      .toList();
  final texts = tester
      .widgetList<Text>(find.descendant(of: group, matching: find.byType(Text)))
      .toList();
  expect(containers, hasLength(ForumThreadBadgeKind.values.length));
  expect(texts, hasLength(ForumThreadBadgeKind.values.length));
  for (var index = 0; index < ForumThreadBadgeKind.values.length; index++) {
    final expected = switch (ForumThreadBadgeKind.values[index]) {
      ForumThreadBadgeKind.closed => badgeTheme.closed,
      ForumThreadBadgeKind.digest => badgeTheme.digest,
      ForumThreadBadgeKind.sticky => badgeTheme.sticky,
      _ => badgeTheme.standard,
    };
    final decoration = containers[index].decoration! as BoxDecoration;
    expect(decoration.color, expected.background);
    expect(decoration.border, isNull);
    expect(texts[index].style!.color, expected.foreground);
  }
}
