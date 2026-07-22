import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_navigation_settings_controller.dart';
import 'package:y300/app/navigation/main_navigation_settings_repository.dart';
import 'package:y300/app/navigation/main_navigation_settings_snapshot_codec.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MainNavigationSettingsSnapshotCodec', () {
    test('round-trips a normalized snapshot', () {
      final settings = MainNavigationSettings(
        managedOrder: const <MainShellDestination>[
          MainShellDestination.comic,
          MainShellDestination.forum,
          MainShellDestination.history,
          MainShellDestination.favorites,
          MainShellDestination.novel,
        ],
        hiddenDestinations: const <MainShellDestination>{
          MainShellDestination.favorites,
          MainShellDestination.history,
        },
      );

      final decoded = MainNavigationSettingsSnapshotCodec.decode(
        MainNavigationSettingsSnapshotCodec.encode(settings),
      );

      expect(decoded, settings);
      expect(decoded.visibleDestinations.last, MainShellDestination.more);
    });

    test('repairs unknown, duplicate, missing, and all-hidden values', () {
      final decoded = MainNavigationSettingsSnapshotCodec.decode('''
        {
          "schemaVersion": 1,
          "order": ["history", "future", "history", "comic"],
          "hidden": ["history", "comic", "forum", "favorites", "novel", "more"]
        }
      ''');

      expect(decoded.managedOrder, const <MainShellDestination>[
        MainShellDestination.history,
        MainShellDestination.comic,
        MainShellDestination.forum,
        MainShellDestination.favorites,
        MainShellDestination.novel,
      ]);
      expect(decoded.visibleManagedDestinations, const <MainShellDestination>[
        MainShellDestination.history,
      ]);
    });

    test('falls back to defaults for malformed or future snapshots', () {
      expect(
        MainNavigationSettingsSnapshotCodec.decode('{broken'),
        MainNavigationSettings.defaults(),
      );
      expect(
        MainNavigationSettingsSnapshotCodec.decode(
          '{"schemaVersion":2,"order":[]}',
        ),
        MainNavigationSettings.defaults(),
      );
    });
  });

  test('shared preferences repository persists one snapshot', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = SharedPrefsMainNavigationSettingsRepository();
    final settings = MainNavigationSettings(
      managedOrder: const <MainShellDestination>[
        MainShellDestination.novel,
        MainShellDestination.comic,
        MainShellDestination.forum,
        MainShellDestination.favorites,
        MainShellDestination.history,
      ],
      hiddenDestinations: const <MainShellDestination>{
        MainShellDestination.history,
      },
    );

    await repository.save(settings);

    expect(await repository.load(), settings);
  });

  group('MainNavigationSettingsController', () {
    test('falls back to defaults when repository loading fails', () async {
      final container = ProviderContainer(
        overrides: [
          mainNavigationSettingsRepositoryProvider.overrideWithValue(
            _FakeMainNavigationSettingsRepository(failOnLoad: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(
        mainNavigationSettingsControllerProvider.future,
      );

      expect(state.settings, MainNavigationSettings.defaults());
      expect(state.isSaving, isFalse);
    });

    test('updates visibility and reorder then restores defaults', () async {
      final repository = _FakeMainNavigationSettingsRepository();
      final container = ProviderContainer(
        overrides: [
          mainNavigationSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(mainNavigationSettingsControllerProvider.future);
      final controller = container.read(
        mainNavigationSettingsControllerProvider.notifier,
      );

      await controller.setVisibility(MainShellDestination.history, false);
      await controller.reorder(0, 2);

      var settings = container
          .read(mainNavigationSettingsControllerProvider)
          .requireValue
          .settings;
      expect(settings.hiddenDestinations, <MainShellDestination>{
        MainShellDestination.history,
      });
      expect(settings.managedOrder.take(3), const <MainShellDestination>[
        MainShellDestination.favorites,
        MainShellDestination.comic,
        MainShellDestination.forum,
      ]);

      await controller.resetToDefaults();
      settings = container
          .read(mainNavigationSettingsControllerProvider)
          .requireValue
          .settings;
      expect(settings, MainNavigationSettings.defaults());
      expect(repository.savedSettings, hasLength(3));
    });

    test('rejects hiding the final visible managed destination', () async {
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
      final container = ProviderContainer(
        overrides: [
          mainNavigationSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(mainNavigationSettingsControllerProvider.future);

      await expectLater(
        container
            .read(mainNavigationSettingsControllerProvider.notifier)
            .setVisibility(MainShellDestination.forum, false),
        throwsA(isA<MainNavigationMinimumVisibleException>()),
      );
      expect(repository.savedSettings, isEmpty);
    });

    test('exposes optimistic state and locks concurrent mutations', () async {
      final saveCompleter = Completer<void>();
      final repository = _FakeMainNavigationSettingsRepository(
        saveCompleter: saveCompleter,
      );
      final container = ProviderContainer(
        overrides: [
          mainNavigationSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(mainNavigationSettingsControllerProvider.future);
      final controller = container.read(
        mainNavigationSettingsControllerProvider.notifier,
      );

      final saving = controller.setVisibility(
        MainShellDestination.history,
        false,
      );
      await Future<void>.delayed(Duration.zero);

      final optimistic = container
          .read(mainNavigationSettingsControllerProvider)
          .requireValue;
      expect(optimistic.isSaving, isTrue);
      expect(
        optimistic.settings.hiddenDestinations,
        contains(MainShellDestination.history),
      );
      await expectLater(
        controller.setVisibility(MainShellDestination.novel, false),
        throwsA(isA<MainNavigationMutationInProgressException>()),
      );

      saveCompleter.complete();
      await saving;
      expect(
        container
            .read(mainNavigationSettingsControllerProvider)
            .requireValue
            .isSaving,
        isFalse,
      );
    });

    test('rolls back optimistic state when persistence fails', () async {
      final repository = _FakeMainNavigationSettingsRepository(
        failOnSave: true,
      );
      final container = ProviderContainer(
        overrides: [
          mainNavigationSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(mainNavigationSettingsControllerProvider.future);

      await expectLater(
        container
            .read(mainNavigationSettingsControllerProvider.notifier)
            .setVisibility(MainShellDestination.history, false),
        throwsStateError,
      );

      expect(
        container
            .read(mainNavigationSettingsControllerProvider)
            .requireValue
            .settings,
        MainNavigationSettings.defaults(),
      );
    });
  });
}

final class _FakeMainNavigationSettingsRepository
    implements MainNavigationSettingsRepository {
  _FakeMainNavigationSettingsRepository({
    MainNavigationSettings? settings,
    this.failOnLoad = false,
    this.failOnSave = false,
    this.saveCompleter,
  }) : _settings = settings ?? MainNavigationSettings.defaults();

  MainNavigationSettings _settings;
  final bool failOnLoad;
  final bool failOnSave;
  final Completer<void>? saveCompleter;
  final List<MainNavigationSettings> savedSettings = <MainNavigationSettings>[];

  @override
  Future<MainNavigationSettings> load() async {
    if (failOnLoad) {
      throw StateError('load failed');
    }
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
