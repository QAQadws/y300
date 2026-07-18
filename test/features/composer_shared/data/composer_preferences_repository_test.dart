import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/composer_shared/data/preferences/shared_preferences_composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/data/providers/composer_preferences_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to Quill and enabled signature for new drafts', () async {
    final repository = SharedPreferencesComposerPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
    );

    expect(await repository.load(), ComposerPreferences.defaults());
    expect(
      (await repository.load()).defaultSurface,
      ComposerSurfacePreference.quill,
    );
    expect((await repository.load()).newDraftUseSignature, isTrue);
  });

  test('snapshot round-trips supported fixed-size preferences', () async {
    final repository = SharedPreferencesComposerPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
    );
    const expected = ComposerPreferences(
      defaultSurface: ComposerSurfacePreference.source,
      newDraftUseSignature: false,
    );

    await repository.save(expected);

    expect(await repository.load(), expected);
  });

  test('unknown snapshot fields fall back independently', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferenceKeys.composerDefaultsSnapshotV1.name:
          jsonEncode(<String, Object>{
            'schemaVersion': 1,
            'defaultSurface': 'future-surface',
            'newDraftUseSignature': false,
          }),
    });
    final repository = SharedPreferencesComposerPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
    );

    final loaded = await repository.load();

    expect(loaded.defaultSurface, ComposerSurfacePreference.quill);
    expect(loaded.newDraftUseSignature, isFalse);
  });

  test('controller persists surface and signature defaults', () async {
    final repository = SharedPreferencesComposerPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
    );
    final container = ProviderContainer(
      overrides: [
        composerPreferencesRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(composerPreferencesControllerProvider.future);
    final controller = container.read(
      composerPreferencesControllerProvider.notifier,
    );

    await controller.setDefaultSurface(ComposerSurfacePreference.source);
    await controller.setNewDraftUseSignature(false);

    expect(
      container.read(composerPreferencesControllerProvider).value,
      const ComposerPreferences(
        defaultSurface: ComposerSurfacePreference.source,
        newDraftUseSignature: false,
      ),
    );
    expect(
      await repository.load(),
      container.read(composerPreferencesControllerProvider).value,
    );
  });
}
