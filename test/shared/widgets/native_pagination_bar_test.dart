import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/native_pagination_bar.dart';

import '../../test_support/localized_test_app.dart';

const _previousKey = Key('test-pagination-previous');
const _currentKey = Key('test-pagination-current');
const _nextKey = Key('test-pagination-next');

void main() {
  testWidgets('routes previous, next and selected pages independently', (
    tester,
  ) async {
    final actions = <Object>[];
    await _pumpPagination(
      tester,
      onLoadPrevious: () => actions.add('previous'),
      onLoadNext: () => actions.add('next'),
      onSelectPage: actions.add,
    );

    await tester.tap(find.byKey(_previousKey));
    await tester.tap(find.byKey(_nextKey));
    await tester.tap(find.byKey(_currentKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('test-pagination-page-option-4')));
    await tester.pumpAndSettle();

    expect(actions, ['previous', 'next', 4]);
  });

  testWidgets('page boundaries disable navigation but retain the page picker', (
    tester,
  ) async {
    await _pumpPagination(tester, canLoadPrevious: false, hasMore: false);

    expect(_button(tester, _previousKey).onPressed, isNull);
    expect(_button(tester, _nextKey).onPressed, isNull);
    expect(_button(tester, _currentKey).onPressed, isNotNull);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NativePaginationBar)),
    );
    expect(find.text(l10n.forumDisplayNoMore), findsOneWidget);
  });

  testWidgets('loading blocks navigation while preserving the current page', (
    tester,
  ) async {
    await _pumpPagination(tester, isLoading: true);

    expect(_button(tester, _previousKey).onPressed, isNull);
    expect(_button(tester, _currentKey).onPressed, isNull);
    expect(find.byKey(_nextKey), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NativePaginationBar)),
    );
    expect(find.text(l10n.commonPage(2)), findsOneWidget);
  });

  testWidgets('wraps controls on narrow screens with enlarged text', (
    tester,
  ) async {
    await _pumpPagination(tester, width: 240, textScale: 2);

    expect(tester.takeException(), isNull);
    final barRect = tester.getRect(find.byType(NativePaginationBar));
    for (final key in [_previousKey, _currentKey, _nextKey]) {
      final buttonRect = tester.getRect(find.byKey(key));
      expect(buttonRect.left, greaterThanOrEqualTo(barRect.left));
      expect(buttonRect.right, lessThanOrEqualTo(barRect.right));
    }
    expect(
      tester.getTopLeft(find.byKey(_nextKey)).dy,
      greaterThan(tester.getTopLeft(find.byKey(_previousKey)).dy),
    );
  });
}

TextButton _button(WidgetTester tester, Key key) => tester.widget<TextButton>(
  find.descendant(of: find.byKey(key), matching: find.byType(TextButton)),
);

Future<void> _pumpPagination(
  WidgetTester tester, {
  bool canLoadPrevious = true,
  bool hasMore = true,
  bool isLoading = false,
  VoidCallback? onLoadPrevious,
  VoidCallback? onLoadNext,
  ValueChanged<int>? onSelectPage,
  double width = 400,
  double textScale = 1,
}) => tester.pumpWidget(
  LocalizedTestApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Center(
              child: SizedBox(
                width: width,
                child: NativePaginationBar(
                  currentPage: 2,
                  lastPage: 4,
                  hasMore: hasMore,
                  canLoadPrevious: canLoadPrevious,
                  isLoading: isLoading,
                  onLoadPrevious: onLoadPrevious ?? () {},
                  onLoadNext: onLoadNext ?? () {},
                  onSelectPage: onSelectPage ?? (_) {},
                  previousLabel: l10n.commonPreviousPage,
                  currentLabel: l10n.commonPage(2),
                  nextLabel: hasMore
                      ? l10n.commonNextPage
                      : l10n.forumDisplayNoMore,
                  previousButtonKey: _previousKey,
                  currentPageButtonKey: _currentKey,
                  nextButtonKey: _nextKey,
                  menuKeyPrefix: 'test-pagination',
                ),
              ),
            ),
          );
        },
      ),
    ),
  ),
);
