import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';

/// Storage abstraction keeps persistence decoupled from state orchestration.
abstract class ReaderPreferencesRepository {
  Future<ReaderPreferences> load();

  Future<void> save(ReaderPreferences preferences);
}

class SharedPrefsReaderPreferencesRepository
    implements ReaderPreferencesRepository {
  static const String _readerModeKey = 'reader_pref_mode';
  static const String _showPageIndicatorKey = 'reader_pref_show_page_indicator';
  static const String _fullscreenOnOpenKey = 'reader_pref_fullscreen_on_open';
  static const String _cacheDirectoryPathKey = 'reader_pref_cache_directory';

  @override
  Future<ReaderPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeRaw = prefs.getString(_readerModeKey);
    final mode = _parseMode(modeRaw);

    return ReaderPreferences(
      readerMode: mode,
      showPageIndicator: prefs.getBool(_showPageIndicatorKey) ?? true,
      fullscreenOnOpen: prefs.getBool(_fullscreenOnOpenKey) ?? false,
      cacheDirectoryPath: prefs.getString(_cacheDirectoryPathKey),
    );
  }

  @override
  Future<void> save(ReaderPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readerModeKey, preferences.readerMode.name);
    await prefs.setBool(_showPageIndicatorKey, preferences.showPageIndicator);
    await prefs.setBool(_fullscreenOnOpenKey, preferences.fullscreenOnOpen);
    final cacheDirectoryPath = preferences.cacheDirectoryPath;
    if (cacheDirectoryPath == null || cacheDirectoryPath.isEmpty) {
      await prefs.remove(_cacheDirectoryPathKey);
      return;
    }
    await prefs.setString(_cacheDirectoryPathKey, cacheDirectoryPath);
  }

  static ReaderModePreference _parseMode(String? raw) {
    for (final mode in ReaderModePreference.values) {
      if (mode.name == raw) {
        return mode;
      }
    }
    return ReaderModePreference.vertical;
  }
}

final readerPreferencesRepositoryProvider = Provider<ReaderPreferencesRepository>(
  (ref) => SharedPrefsReaderPreferencesRepository(),
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

  Future<void> setShowPageIndicator(bool value) async {
    final current = state.value ?? ReaderPreferences.defaults();
    await _persist(current.copyWith(showPageIndicator: value));
  }

  Future<void> setFullscreenOnOpen(bool value) async {
    final current = state.value ?? ReaderPreferences.defaults();
    await _persist(current.copyWith(fullscreenOnOpen: value));
  }

  Future<void> setCacheDirectoryPath(String? path) async {
    final current = state.value ?? ReaderPreferences.defaults();
    final normalized = path?.trim();
    if (normalized == null || normalized.isEmpty) {
      await _persist(current.copyWith(clearCacheDirectoryPath: true));
      return;
    }
    await _persist(current.copyWith(cacheDirectoryPath: normalized));
  }

  Future<void> _persist(ReaderPreferences next) async {
    state = AsyncData(next);
    await _repository.save(next);
  }
}
