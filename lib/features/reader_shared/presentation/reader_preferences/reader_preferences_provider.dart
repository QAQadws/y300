import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/reader_shared/data/reader_preferences/reader_preferences_snapshot_codec.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';

/// 持久化抽象，让存储实现与状态编排解耦。
abstract class ReaderPreferencesRepository {
  Future<ReaderPreferences> load();

  Future<void> save(ReaderPreferences preferences);
}

class SharedPrefsReaderPreferencesRepository
    implements ReaderPreferencesRepository {
  SharedPrefsReaderPreferencesRepository({
    PreferencesStore? preferencesStore,
    ReaderPreferencesSnapshotCodec codec =
        const ReaderPreferencesSnapshotCodec(),
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore(),
       _codec = codec;

  final PreferencesStore _preferencesStore;
  final ReaderPreferencesSnapshotCodec _codec;

  @override
  Future<ReaderPreferences> load() async {
    if (await _preferencesStore.contains(
      PreferenceKeys.imageReaderSnapshotV1,
    )) {
      return _codec.decode(
        await _preferencesStore.read(PreferenceKeys.imageReaderSnapshotV1),
      );
    }
    return _codec.normalize(
      readerMode: await _preferencesStore.read(
        PreferenceKeys.legacyImageReaderMode,
      ),
      pageFit: await _preferencesStore.read(
        PreferenceKeys.legacyImageReaderPageFit,
      ),
      background: await _preferencesStore.read(
        PreferenceKeys.legacyImageReaderBackground,
      ),
      pageSpacing: await _preferencesStore.read(
        PreferenceKeys.legacyImageReaderPageSpacing,
      ),
      showPageIndicator: await _preferencesStore.read(
        PreferenceKeys.legacyImageReaderShowPageIndicator,
      ),
    );
  }

  @override
  Future<void> save(ReaderPreferences preferences) async {
    await _preferencesStore.write(
      PreferenceKeys.imageReaderSnapshotV1,
      _codec.encode(preferences),
    );
  }
}

final readerPreferencesRepositoryProvider =
    Provider<ReaderPreferencesRepository>(
      (ref) => SharedPrefsReaderPreferencesRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
      ),
    );

final readerPreferencesControllerProvider =
    AsyncNotifierProvider<ReaderPreferencesController, ReaderPreferences>(
      ReaderPreferencesController.new,
    );

class ReaderPreferencesController extends AsyncNotifier<ReaderPreferences> {
  ReaderPreferencesRepository get _repository =>
      ref.read(readerPreferencesRepositoryProvider);

  @override
  Future<ReaderPreferences> build() async {
    return _repository.load();
  }

  Future<void> setReaderMode(ReaderModePreference mode) async {
    final current = state.value ?? ReaderPreferences.defaults();
    await _persist(current.copyWith(readerMode: mode));
  }

  Future<void> setPageFit(ReaderPageFitPreference value) async {
    final current = state.value ?? ReaderPreferences.defaults();
    await _persist(current.copyWith(pageFit: value));
  }

  Future<void> setBackground(ReaderBackgroundPreference value) async {
    final current = state.value ?? ReaderPreferences.defaults();
    await _persist(current.copyWith(background: value));
  }

  Future<void> setPageSpacing(double value) async {
    final current = state.value ?? ReaderPreferences.defaults();
    await _persist(
      current.copyWith(pageSpacing: value.clamp(0.0, 48.0).toDouble()),
    );
  }

  Future<void> setShowPageIndicator(bool value) async {
    final current = state.value ?? ReaderPreferences.defaults();
    await _persist(current.copyWith(showPageIndicator: value));
  }

  Future<void> _persist(ReaderPreferences next) async {
    state = AsyncData(next);
    await _repository.save(next);
  }
}
