import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/composer_shared/data/preferences/shared_preferences_composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/data/repositories/sticker_picker_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';

final composerPreferencesRepositoryProvider =
    Provider<ComposerPreferencesRepository>((ref) {
      return SharedPreferencesComposerPreferencesRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

final composerPreferencesControllerProvider =
    AsyncNotifierProvider<ComposerPreferencesController, ComposerPreferences>(
      ComposerPreferencesController.new,
    );

class ComposerPreferencesController extends AsyncNotifier<ComposerPreferences> {
  Future<void> _pendingSave = Future<void>.value();

  ComposerPreferencesRepository get _repository =>
      ref.read(composerPreferencesRepositoryProvider);

  @override
  Future<ComposerPreferences> build() => _repository.load();

  Future<void> setDefaultSurface(ComposerSurfacePreference surface) {
    final current = state.value ?? ComposerPreferences.defaults();
    if (current.defaultSurface == surface) {
      return Future<void>.value();
    }
    return _persist(current.copyWith(defaultSurface: surface));
  }

  Future<void> setNewDraftUseSignature(bool value) {
    final current = state.value ?? ComposerPreferences.defaults();
    if (current.newDraftUseSignature == value) {
      return Future<void>.value();
    }
    return _persist(current.copyWith(newDraftUseSignature: value));
  }

  Future<void> _persist(ComposerPreferences next) async {
    final previous = state.value ?? ComposerPreferences.defaults();
    state = AsyncData(next);
    final operation = _pendingSave.then((_) => _repository.save(next));
    _pendingSave = operation.catchError((_) {});
    try {
      await operation;
    } catch (error, stackTrace) {
      if (state.value == next) {
        state = AsyncData(previous);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final stickerPickerPreferencesRepositoryProvider =
    Provider<StickerPickerPreferencesRepository>((ref) {
      return SharedPreferencesStickerPickerPreferencesRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

final stickerPickerLastGroupIdControllerProvider =
    AsyncNotifierProvider<StickerPickerLastGroupIdController, String?>(
      StickerPickerLastGroupIdController.new,
    );

class StickerPickerLastGroupIdController extends AsyncNotifier<String?> {
  StickerPickerPreferencesRepository get _repository =>
      ref.read(stickerPickerPreferencesRepositoryProvider);

  @override
  Future<String?> build() => _repository.loadLastGroupId();

  Future<void> selectGroup(String groupId) async {
    final normalized = groupId.trim();
    if (normalized.isEmpty || state.value == normalized) {
      return;
    }
    final previous = state.value;
    state = AsyncData(normalized);
    try {
      await _repository.saveLastGroupId(normalized);
    } catch (error, stackTrace) {
      state = AsyncData(previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
