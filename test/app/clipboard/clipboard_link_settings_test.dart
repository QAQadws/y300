import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/clipboard/clipboard_link_settings_controller.dart';
import 'package:y300/app/clipboard/clipboard_link_settings_repository.dart';
import 'package:y300/core/preferences/preference_key_names.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'absent preference defaults enabled without creating a persisted value',
    () async {
      final store = SharedPreferencesStore();
      final repository = SharedPrefsClipboardLinkSettingsRepository(
        preferencesStore: store,
      );
      expect(await repository.loadEnabled(), isTrue);
      expect(
        await store.contains(PreferenceKeys.appClipboardLinkDetectionEnabledV1),
        isFalse,
      );
    },
  );

  test(
    'only the typed detection preference persists and is restored',
    () async {
      final repository = SharedPrefsClipboardLinkSettingsRepository();
      await repository.saveEnabled(false);
      expect(
        await SharedPrefsClipboardLinkSettingsRepository().loadEnabled(),
        isFalse,
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), {
        PreferenceKeyNames.appClipboardLinkDetectionEnabledV1,
      });
      await repository.saveEnabled(true);
      expect(
        await SharedPrefsClipboardLinkSettingsRepository().loadEnabled(),
        isTrue,
      );
    },
  );

  test('unknown stored value type follows the defined default', () async {
    SharedPreferences.setMockInitialValues({
      PreferenceKeyNames.appClipboardLinkDetectionEnabledV1: 'unknown',
    });
    expect(
      await SharedPrefsClipboardLinkSettingsRepository().loadEnabled(),
      isTrue,
    );
  });

  test(
    'loading remains unknown until the stored setting is available',
    () async {
      final load = Completer<bool>();
      final repository = _SettingsRepository(load: () => load.future);
      final container = _container(repository);
      final initial = container.read(
        clipboardLinkSettingsControllerProvider.future,
      );
      expect(
        container.read(clipboardLinkSettingsControllerProvider).isLoading,
        isTrue,
      );
      await expectLater(
        container
            .read(clipboardLinkSettingsControllerProvider.notifier)
            .setEnabled(false),
        throwsStateError,
      );
      expect(repository.writes, isEmpty);
      load.complete(false);
      final state = await initial;
      expect(state.enabled, isFalse);
      expect(state.isSaving, isFalse);
    },
  );

  test('load failure fails closed instead of claiming enabled data', () async {
    final failure = StateError('unavailable');
    final repository = _SettingsRepository(
      load: () => Future<bool>.error(failure),
    );
    final container = _container(repository);
    await expectLater(
      container.read(clipboardLinkSettingsControllerProvider.future),
      throwsA(same(failure)),
    );
    final state = container.read(clipboardLinkSettingsControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.asData, isNull);
    expect(repository.writes, isEmpty);
  });

  test(
    'optimistic disabling starts immediately, blocks competing writes and confirms success',
    () async {
      final save = Completer<void>();
      final repository = _SettingsRepository(save: (_) => save.future);
      final container = _container(repository);
      await container.read(clipboardLinkSettingsControllerProvider.future);
      final controller = container.read(
        clipboardLinkSettingsControllerProvider.notifier,
      );
      final pending = controller.setEnabled(false);
      var state = container
          .read(clipboardLinkSettingsControllerProvider)
          .requireValue;
      expect(state.enabled, isFalse);
      expect(state.isSaving, isTrue);
      await expectLater(controller.setEnabled(true), throwsStateError);
      expect(repository.writes, [false]);
      save.complete();
      await pending;
      state = container
          .read(clipboardLinkSettingsControllerProvider)
          .requireValue;
      expect(state.enabled, isFalse);
      expect(state.isSaving, isFalse);
      await controller.setEnabled(false);
      expect(repository.writes, [false]);
    },
  );

  test(
    'write failure restores confirmed state and permits explicit retry',
    () async {
      var fail = true;
      final failure = StateError('write failed');
      final repository = _SettingsRepository(
        save: (_) async {
          if (fail) throw failure;
        },
      );
      final container = _container(repository);
      await container.read(clipboardLinkSettingsControllerProvider.future);
      final controller = container.read(
        clipboardLinkSettingsControllerProvider.notifier,
      );
      await expectLater(controller.setEnabled(false), throwsA(same(failure)));
      var state = container
          .read(clipboardLinkSettingsControllerProvider)
          .requireValue;
      expect(state.enabled, isTrue);
      expect(state.isSaving, isFalse);
      fail = false;
      await controller.setEnabled(false);
      state = container
          .read(clipboardLinkSettingsControllerProvider)
          .requireValue;
      expect(state.enabled, isFalse);
      expect(state.isSaving, isFalse);
      expect(repository.writes, [false, false]);
    },
  );

  test(
    'late save completion cannot publish into a replaced repository generation',
    () async {
      final save = Completer<void>();
      final oldRepository = _SettingsRepository(save: (_) => save.future);
      final container = _container(oldRepository);
      await container.read(clipboardLinkSettingsControllerProvider.future);
      final pending = container
          .read(clipboardLinkSettingsControllerProvider.notifier)
          .setEnabled(false);
      container.updateOverrides([
        clipboardLinkSettingsRepositoryProvider.overrideWithValue(
          _SettingsRepository(),
        ),
      ]);
      await container.read(clipboardLinkSettingsControllerProvider.future);
      expect(
        container
            .read(clipboardLinkSettingsControllerProvider)
            .requireValue
            .enabled,
        isTrue,
      );
      save.complete();
      await pending;
      expect(
        container
            .read(clipboardLinkSettingsControllerProvider)
            .requireValue
            .enabled,
        isTrue,
      );
    },
  );

  test(
    'disposing settings while save awaits does not publish a late state',
    () async {
      final save = Completer<void>();
      final repository = _SettingsRepository(save: (_) => save.future);
      final container = ProviderContainer(
        overrides: [
          clipboardLinkSettingsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      await container.read(clipboardLinkSettingsControllerProvider.future);
      final pending = container
          .read(clipboardLinkSettingsControllerProvider.notifier)
          .setEnabled(false);
      container.dispose();
      save.complete();
      await pending;
      expect(repository.writes, [false]);
    },
  );
}

ProviderContainer _container(ClipboardLinkSettingsRepository repository) {
  final container = ProviderContainer(
    overrides: [
      clipboardLinkSettingsRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _SettingsRepository implements ClipboardLinkSettingsRepository {
  _SettingsRepository({
    Future<bool> Function()? load,
    Future<void> Function(bool)? save,
  }) : _load = load ?? (() async => true),
       _save = save ?? ((_) async {});

  final Future<bool> Function() _load;
  final Future<void> Function(bool) _save;
  final writes = <bool>[];

  @override
  Future<bool> loadEnabled() => _load();

  @override
  Future<void> saveEnabled(bool enabled) {
    writes.add(enabled);
    return _save(enabled);
  }
}
