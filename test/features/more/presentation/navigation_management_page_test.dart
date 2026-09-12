import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/main_destination_page.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_shell_destination_presentation.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:y300/app/navigation/main_navigation_settings_repository.dart';
import 'package:y300/features/more/presentation/navigation_management_page.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../profile/test_support/blog_directory_fixture.dart';

void main() {
  testWidgets(
    'opens visible and hidden destinations without changing settings',
    (tester) async {
      final initialSettings = MainNavigationSettings(
        managedOrder: MainShellDestination.defaultManagedOrder.reversed
            .toList(),
        hiddenDestinations: MainShellDestination.defaultManagedOrder
            .where((destination) => destination != MainShellDestination.comic)
            .toSet(),
      );
      final repository = _FakeMainNavigationSettingsRepository(
        settings: initialSettings,
      );
      final opened = <MainShellDestination>[];
      await _pumpPage(tester, repository, opened: opened);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NavigationManagementPage)),
      );

      for (final destination in initialSettings.managedOrder) {
        final entry = find.byKey(
          ValueKey('navigation-management-open-${destination.name}'),
        );
        // Icon, title and the remaining middle area all open the same route.
        for (final hit in ['icon', 'title', 'space']) {
          if (hit == 'space') {
            final rect = tester.getRect(entry);
            await tester.tapAt(Offset(rect.right - 8, rect.center.dy));
          } else {
            await tester.tap(
              find.descendant(
                of: entry,
                matching: hit == 'icon'
                    ? find.byIcon(destination.icon)
                    : find.text(destination.localizedLabel(l10n)),
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(opened.last, destination);
          expect(
            find.byKey(ValueKey('opened-${destination.name}')),
            findsOneWidget,
          );
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(find.byType(NavigationManagementPage), findsOneWidget);
        }
      }
      expect(opened, hasLength(initialSettings.managedOrder.length * 3));
      expect(repository.savedSettings, isEmpty);
      expect(await repository.load(), initialSettings);
    },
  );

  testWidgets('opens hidden blogs through the shared native destination', (
    tester,
  ) async {
    final repository = _FakeMainNavigationSettingsRepository();
    final blogs = BlogDirectoryFixture();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mainNavigationSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
          blogAccountIdProvider.overrideWithValue('101'),
          userBlogDirectoryRepositoryProvider.overrideWithValue(blogs),
          forumImageRefererProvider.overrideWithValue('https://example.test/'),
        ],
        child: const LocalizedTestApp(home: NavigationManagementPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(blogs.queries, isEmpty);
    await tester.tap(find.byKey(const Key('navigation-management-open-blogs')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileBlogPage), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ProfileBlogPage)),
    );
    expect(find.text(l10n.profileBlogFriends), findsOneWidget);
    expect(blogs.queries, hasLength(1));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationManagementPage), findsOneWidget);
    expect(
      tester
          .widget<Switch>(
            find.byKey(const Key('navigation-management-visible-blogs')),
          )
          .value,
      isFalse,
    );
    expect(repository.savedSettings, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches and drag handles do not open a destination', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeMainNavigationSettingsRepository();
    final opened = <MainShellDestination>[];
    await _pumpPage(tester, repository, opened: opened);
    await tester.tap(
      find.byKey(const Key('navigation-management-visible-history')),
    );
    await tester.pumpAndSettle();
    final handle = find.byKey(const Key('navigation-management-drag-forum'));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 140));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(repository.savedSettings.length, greaterThanOrEqualTo(2));
    expect(
      repository.savedSettings.last.managedOrder.first,
      isNot(MainShellDestination.forum),
    );
    expect(find.byType(NavigationManagementPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled controls stay separate from navigation while saving', (
    tester,
  ) async {
    final saveCompleter = Completer<void>();
    final repository = _FakeMainNavigationSettingsRepository(
      saveCompleter: saveCompleter,
    );
    final opened = <MainShellDestination>[];
    await _pumpPage(tester, repository, opened: opened);
    await tester.tap(
      find.byKey(const Key('navigation-management-visible-history')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('navigation-management-visible-novel')),
    );
    await tester.tap(find.byKey(const Key('navigation-management-drag-novel')));
    expect(opened, isEmpty);
    await tester.tap(find.byKey(const Key('navigation-management-open-novel')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, [MainShellDestination.novel]);
    saveCompleter.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(repository.savedSettings, hasLength(1));
    expect(find.byType(NavigationManagementPage), findsOneWidget);
  });

  testWidgets('disables reset until settings finish loading', (tester) async {
    final loadCompleter = Completer<void>();
    final repository = _FakeMainNavigationSettingsRepository(
      loadCompleter: loadCompleter,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mainNavigationSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: const LocalizedTestApp(home: NavigationManagementPage()),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('navigation-management-reset')),
          )
          .onPressed,
      isNull,
    );

    loadCompleter.complete();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('navigation-management-reset')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('shows all managed destinations and never lists More', (
    tester,
  ) async {
    final repository = _FakeMainNavigationSettingsRepository();
    await _pumpPage(tester, repository);

    expect(find.text('论坛'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('漫画'), findsOneWidget);
    expect(find.text('小说'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NavigationManagementPage)),
    );
    expect(find.text(l10n.profileBlogTitle), findsOneWidget);
    expect(
      find.byType(Switch),
      findsNWidgets(MainShellDestination.defaultManagedOrder.length),
    );
  });

  testWidgets('visibility changes persist immediately', (tester) async {
    final repository = _FakeMainNavigationSettingsRepository();
    await _pumpPage(tester, repository);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('navigation-management-visible-history'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.savedSettings, hasLength(1));
    expect(
      repository.savedSettings.single.hiddenDestinations,
      contains(MainShellDestination.history),
    );
  });

  testWidgets('reorder uses the complete managed list including hidden items', (
    tester,
  ) async {
    final repository = _FakeMainNavigationSettingsRepository(
      settings: MainNavigationSettings(
        managedOrder: MainShellDestination.defaultManagedOrder,
        hiddenDestinations: const <MainShellDestination>{
          MainShellDestination.favorites,
        },
      ),
    );
    await _pumpPage(tester, repository);
    final list = tester.widget<ReorderableListView>(
      find.byKey(const Key('navigation-management-list')),
    );

    list.onReorderItem!(0, 2);
    await tester.pumpAndSettle();

    expect(repository.savedSettings.single.managedOrder.take(3), const [
      MainShellDestination.favorites,
      MainShellDestination.comic,
      MainShellDestination.forum,
    ]);
    expect(
      repository.savedSettings.single.hiddenDestinations,
      contains(MainShellDestination.favorites),
    );
  });

  testWidgets('rejects hiding the final visible destination', (tester) async {
    final repository = _FakeMainNavigationSettingsRepository(
      settings: MainNavigationSettings(
        managedOrder: MainShellDestination.defaultManagedOrder,
        hiddenDestinations: const <MainShellDestination>{
          MainShellDestination.favorites,
          MainShellDestination.comic,
          MainShellDestination.novel,
          MainShellDestination.history,
          MainShellDestination.blogs,
        },
      ),
    );
    await _pumpPage(tester, repository);

    await tester.tap(
      find.byKey(const ValueKey<String>('navigation-management-visible-forum')),
    );
    await tester.pumpAndSettle();

    expect(repository.savedSettings, isEmpty);
    expect(find.text('至少保留一个导航项'), findsOneWidget);
  });

  testWidgets('locks controls while saving and restores them afterward', (
    tester,
  ) async {
    final saveCompleter = Completer<void>();
    final repository = _FakeMainNavigationSettingsRepository(
      saveCompleter: saveCompleter,
    );
    await _pumpPage(tester, repository);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('navigation-management-visible-history'),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('navigation-management-saving')),
      findsOneWidget,
    );
    final novelSwitch = tester.widget<Switch>(
      find.byKey(const ValueKey<String>('navigation-management-visible-novel')),
    );
    expect(novelSwitch.onChanged, isNull);

    saveCompleter.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-management-saving')), findsNothing);
  });

  testWidgets('save failure rolls back and shows stable feedback', (
    tester,
  ) async {
    final repository = _FakeMainNavigationSettingsRepository(failOnSave: true);
    await _pumpPage(tester, repository);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('navigation-management-visible-history'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('导航栏设置保存失败'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(
            find.byKey(
              const ValueKey<String>('navigation-management-visible-history'),
            ),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('reset restores visibility and the default order', (
    tester,
  ) async {
    final repository = _FakeMainNavigationSettingsRepository(
      settings: MainNavigationSettings(
        managedOrder: const <MainShellDestination>[
          MainShellDestination.history,
          MainShellDestination.novel,
          MainShellDestination.comic,
          MainShellDestination.favorites,
          MainShellDestination.forum,
        ],
        hiddenDestinations: const <MainShellDestination>{
          MainShellDestination.forum,
        },
      ),
    );
    await _pumpPage(tester, repository);

    await tester.tap(find.byKey(const Key('navigation-management-reset')));
    await tester.pumpAndSettle();

    expect(repository.savedSettings.single, MainNavigationSettings.defaults());
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  MainNavigationSettingsRepository repository, {
  List<MainShellDestination>? opened,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mainNavigationSettingsRepositoryProvider.overrideWithValue(repository),
        mainDestinationRouteFactoryProvider.overrideWithValue((destination) {
          opened?.add(destination);
          return MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              key: ValueKey('opened-${destination.name}'),
              appBar: AppBar(),
            ),
          );
        }),
      ],
      child: const LocalizedTestApp(home: NavigationManagementPage()),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeMainNavigationSettingsRepository
    implements MainNavigationSettingsRepository {
  _FakeMainNavigationSettingsRepository({
    MainNavigationSettings? settings,
    this.failOnSave = false,
    this.saveCompleter,
    this.loadCompleter,
  }) : _settings = settings ?? MainNavigationSettings.defaults();

  MainNavigationSettings _settings;
  final bool failOnSave;
  final Completer<void>? saveCompleter;
  final Completer<void>? loadCompleter;
  final List<MainNavigationSettings> savedSettings = <MainNavigationSettings>[];

  @override
  Future<MainNavigationSettings> load() async {
    await loadCompleter?.future;
    return _settings;
  }

  @override
  Future<void> save(MainNavigationSettings settings) async {
    if (failOnSave) {
      throw StateError('save failed');
    }
    await saveCompleter?.future;
    savedSettings.add(settings);
    _settings = settings;
  }
}
