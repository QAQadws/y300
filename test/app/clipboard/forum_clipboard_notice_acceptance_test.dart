import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/clipboard/forum_clipboard_link_notice.dart';
import 'package:y300/app/clipboard/forum_clipboard_link_policy.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_shell_destination_presentation.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../test_support/localized_test_app.dart';

const _noticeKey = Key('forum-clipboard-link-notice');
const _openKey = Key('forum-clipboard-link-open');
const _navigationKey = Key('acceptance-navigation-bar');
const _bodyKey = Key('acceptance-body');
const _bodyActionKey = Key('acceptance-body-action');
const _bottomInset = 34.0;

void main() {
  // Use the actual ScaffoldMessenger and production navigation shape without
  // starting a runtime or calling any clipboard/platform adapter.
  for (final locale in AppLocalizations.supportedLocales) {
    for (final kind in ForumClipboardLinkKind.values) {
      for (final brightness in Brightness.values) {
        for (final width in [280.0, 360.0]) {
          for (final scale in [1.0, 2.0]) {
            testWidgets(
              '${locale.toLanguageTag()} ${kind.name} ${brightness.name} '
              '${width.toInt()}px ${scale}x snackbar is accessible and nonmodal',
              (tester) async {
                await tester.binding.setSurfaceSize(Size(width, 900));
                addTearDown(() => tester.binding.setSurfaceSize(null));
                final semantics = tester.ensureSemantics();
                try {
                  final fixture = _NoticeFixture(
                    locale: locale,
                    kind: kind,
                    brightness: brightness,
                    textScale: scale,
                  );
                  await tester.pumpWidget(fixture.build());
                  await tester.pumpAndSettle();
                  final bodyBefore = tester.getRect(find.byKey(_bodyKey));
                  final navigationBefore = tester.getRect(
                    find.byKey(_navigationKey),
                  );
                  final controller = fixture.show(tester);
                  await tester.pumpAndSettle();

                  final context = tester.element(find.byKey(_noticeKey));
                  final l10n = AppLocalizations.of(context);
                  final label = _kindLabel(l10n, kind);
                  expect(Localizations.localeOf(context), locale);
                  expect(find.text(label), findsOneWidget);
                  expect(find.text(l10n.clipboardLinkOpen), findsOneWidget);
                  expect(fixture.visibleCalls, 1);
                  expect(
                    find.bySemanticsLabel(RegExp(r'https?://')),
                    findsNothing,
                  );
                  expect(
                    find.textContaining('https://bbs.yamibo.com'),
                    findsNothing,
                  );
                  expect(
                    find.descendant(
                      of: find.byType(SnackBar),
                      matching: find.byType(ModalBarrier),
                    ),
                    findsNothing,
                  );

                  final snackBar = tester.widget<SnackBar>(
                    find.byType(SnackBar),
                  );
                  expect(snackBar.behavior, SnackBarBehavior.floating);
                  expect(snackBar.duration, const Duration(seconds: 6));
                  expect(snackBar.persist, isFalse);
                  expect(snackBar.showCloseIcon, isFalse);
                  expect(
                    find.descendant(
                      of: find.byType(SnackBar),
                      matching: find.byType(IconButton),
                    ),
                    findsNothing,
                  );
                  final announcement = tester.getSemantics(
                    find.descendant(
                      of: find.byType(SnackBar),
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is Semantics &&
                            widget.properties.liveRegion == true,
                      ),
                    ),
                  );
                  expect(announcement.flagsCollection.isLiveRegion, isTrue);
                  expect(find.bySemanticsLabel(label), findsOneWidget);
                  _expectAccessibleAction(
                    tester,
                    find.byKey(_openKey),
                    l10n.clipboardLinkOpen,
                  );

                  final notice = tester.getRect(find.byType(SnackBar));
                  final navigation = tester.getRect(find.byKey(_navigationKey));
                  expect(notice.left, greaterThanOrEqualTo(0));
                  expect(notice.right, lessThanOrEqualTo(width));
                  expect(notice.bottom, lessThanOrEqualTo(navigation.top));
                  expect(tester.getRect(find.byKey(_bodyKey)), bodyBefore);
                  expect(navigation, navigationBefore);
                  expect(navigation.bottom, 900);
                  final more = find.byKey(
                    _destinationKey(MainShellDestination.more),
                  );
                  expect(
                    tester.getRect(more).bottom,
                    lessThanOrEqualTo(900 - _bottomInset),
                  );
                  expect(tester.takeException(), isNull);

                  await tester.tap(find.byKey(_bodyActionKey));
                  await tester.tap(more);
                  await tester.pumpAndSettle();
                  expect(fixture.bodyActions, 1);
                  expect(fixture.selected, fixture.destinations.length - 1);
                  expect(find.byKey(_noticeKey), findsOneWidget);
                  expect(fixture.opens, 0);

                  await tester.tap(find.byKey(_openKey));
                  await tester.pumpAndSettle();
                  expect(fixture.opens, 1);
                  expect(await controller.closed, SnackBarClosedReason.action);
                  expect(find.byKey(_noticeKey), findsNothing);

                  final dismissed = fixture.show(tester);
                  await tester.pumpAndSettle();
                  await tester.drag(
                    find.byKey(_noticeKey),
                    const Offset(0, 240),
                  );
                  await tester.pumpAndSettle();
                  expect(await dismissed.closed, SnackBarClosedReason.swipe);
                  expect(fixture.opens, 1);
                  expect(find.byKey(_noticeKey), findsNothing);
                  expect(tester.getRect(find.byKey(_bodyKey)), bodyBefore);
                  expect(
                    tester.getRect(find.byKey(_navigationKey)),
                    navigationBefore,
                  );
                  expect(tester.takeException(), isNull);
                } finally {
                  semantics.dispose();
                }
              },
            );
          }
        }
      }
    }
  }

  for (final accessibleNavigation in [false, true]) {
    testWidgets(
      'snackbar expires after six seconds with accessibleNavigation=$accessibleNavigation',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(
              accessibleNavigation: accessibleNavigation,
            );
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final fixture = _NoticeFixture(
          locale: const Locale('zh'),
          kind: ForumClipboardLinkKind.thread,
          brightness: Brightness.light,
          textScale: 1,
          accessibleNavigation: accessibleNavigation,
        );
        await tester.pumpWidget(fixture.build());
        await tester.pumpAndSettle();
        final controller = fixture.show(tester);
        await tester.pumpAndSettle();
        expect(
          MediaQuery.accessibleNavigationOf(fixture.messenger.currentContext!),
          accessibleNavigation,
        );
        expect(fixture.visibleCalls, 1);
        await tester.pump(const Duration(milliseconds: 5900));
        expect(find.byKey(_noticeKey), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        expect(await controller.closed, SnackBarClosedReason.timeout);
        expect(find.byKey(_noticeKey), findsNothing);
        expect(fixture.opens, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final firstUsesOpen in [false, true]) {
    testWidgets('consecutive snackbars reset visibility and action state after '
        '${firstUsesOpen ? 'open' : 'downward swipe'} without an empty frame', (
      tester,
    ) async {
      final fixture = _NoticeFixture(
        locale: const Locale('zh'),
        kind: ForumClipboardLinkKind.thread,
        brightness: Brightness.light,
        textScale: 1,
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final first = fixture.show(tester);
      await tester.pumpAndSettle();
      final firstKey = tester.widget<SnackBar>(find.byType(SnackBar)).key;
      expect(fixture.visibleCalls, 1);
      if (firstUsesOpen) {
        await tester.tap(find.byKey(_openKey));
      } else {
        await tester.drag(find.byKey(_noticeKey), const Offset(0, 240));
      }
      // Queue the next presentation during the first one's exit. There is no
      // intervening pump that could unmount/recreate reusable SDK state.
      final second = fixture.show(tester);
      await tester.pumpAndSettle();
      expect(
        await first.closed,
        firstUsesOpen
            ? SnackBarClosedReason.action
            : SnackBarClosedReason.swipe,
      );
      expect(fixture.visibleCalls, 2);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).key,
        isNot(same(firstKey)),
      );
      expect(
        tester
            .widget<TextButton>(
              find.descendant(
                of: find.byKey(_openKey),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(fixture.opens, firstUsesOpen ? 1 : 0);
      await tester.tap(find.byKey(_openKey));
      await tester.pumpAndSettle();
      expect(await second.closed, SnackBarClosedReason.action);
      expect(fixture.opens, firstUsesOpen ? 2 : 1);
      expect(find.byKey(_noticeKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('caller wrapper retains the localized default content', (
    tester,
  ) async {
    final fixture = _NoticeFixture(
      locale: const Locale('zh', 'TW'),
      kind: ForumClipboardLinkKind.forum,
      brightness: Brightness.dark,
      textScale: 1,
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byKey(_bodyKey)));
    Widget? wrappedContent;
    var wrapperCalls = 0;
    final controller = fixture.show(
      tester,
      contentWrapper: (content) {
        wrapperCalls++;
        wrappedContent = content;
        return KeyedSubtree(key: const Key('caller-wrapper'), child: content);
      },
    );
    await tester.pumpAndSettle();
    expect(wrapperCalls, 1);
    expect(wrappedContent, isA<Text>());
    expect((wrappedContent! as Text).data, l10n.clipboardLinkFoundForum);
    expect(find.byKey(const Key('caller-wrapper')), findsOneWidget);
    expect(find.text(l10n.clipboardLinkFoundForum), findsOneWidget);
    await tester.tap(find.byKey(_openKey));
    await tester.pumpAndSettle();
    expect(await controller.closed, SnackBarClosedReason.action);
    expect(fixture.opens, 1);
    expect(tester.takeException(), isNull);
  });
}

void _expectAccessibleAction(WidgetTester tester, Finder action, String label) {
  final node = tester.getSemantics(action);
  expect([node.label, node.tooltip], contains(label));
  expect(node.flagsCollection.isButton, isTrue);
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  final size = tester.getSize(action);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
}

String _kindLabel(AppLocalizations l10n, ForumClipboardLinkKind kind) =>
    switch (kind) {
      ForumClipboardLinkKind.thread => l10n.clipboardLinkFoundThread,
      ForumClipboardLinkKind.threadPost => l10n.clipboardLinkFoundPost,
      ForumClipboardLinkKind.forum => l10n.clipboardLinkFoundForum,
      ForumClipboardLinkKind.blog => l10n.clipboardLinkFoundBlog,
    };

Key _destinationKey(MainShellDestination destination) =>
    ValueKey('acceptance-navigation-${destination.name}');

final class _NoticeFixture {
  _NoticeFixture({
    required this.locale,
    required this.kind,
    required this.brightness,
    required this.textScale,
    this.accessibleNavigation = false,
  });

  final Locale locale;
  final ForumClipboardLinkKind kind;
  final Brightness brightness;
  final double textScale;
  final bool accessibleNavigation;
  final destinations = MainNavigationSettings.defaults().visibleDestinations;
  final messenger = GlobalKey<ScaffoldMessengerState>();
  int opens = 0;
  int visibleCalls = 0;
  int bodyActions = 0;
  int selected = 0;

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    WidgetTester tester, {
    Widget Function(Widget content)? contentWrapper,
  }) => messenger.currentState!.showSnackBar(
    buildForumClipboardLinkSnackBar(
      context: tester.element(find.byKey(_bodyKey)),
      kind: kind,
      onOpen: () => opens++,
      onVisible: () => visibleCalls++,
      contentWrapper: contentWrapper,
    ),
  );

  Widget build() => LocalizedTestApp(
    scaffoldMessengerKey: messenger,
    locale: locale,
    theme: (brightness == Brightness.light ? AppTheme.light() : AppTheme.dark())
        .copyWith(platform: TargetPlatform.android),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        accessibleNavigation: accessibleNavigation,
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(bottom: _bottomInset),
        viewPadding: const EdgeInsets.only(bottom: _bottomInset),
      ),
      child: child!,
    ),
    home: StatefulBuilder(
      builder: (context, setState) {
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          body: Center(
            key: _bodyKey,
            child: TextButton(
              key: _bodyActionKey,
              onPressed: () => bodyActions++,
              child: Text(l10n.commonConfirm),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            key: _navigationKey,
            selectedIndex: selected,
            onDestinationSelected: (index) => setState(() => selected = index),
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  key: _destinationKey(destination),
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.localizedLabel(l10n),
                ),
            ],
          ),
        );
      },
    ),
  );
}
