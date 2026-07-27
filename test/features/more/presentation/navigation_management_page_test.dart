import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:y300/app/navigation/main_navigation_settings_repository.dart';
import 'package:y300/features/more/presentation/navigation_management_page.dart';

void main() {
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
    expect(find.byType(Switch), findsNWidgets(5));
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
  MainNavigationSettingsRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mainNavigationSettingsRepositoryProvider.overrideWithValue(repository),
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
