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
  static const String _pageFitKey = 'reader_pref_page_fit';
  static const String _backgroundKey = 'reader_pref_background';
  static const String _pageSpacingKey = 'reader_pref_page_spacing';
  static const String _showPageIndicatorKey = 'reader_pref_show_page_indicator';
  static const String _cropBordersKey = 'reader_pref_crop_borders';
  static const String _fullscreenOnOpenKey = 'reader_pref_fullscreen_on_open';
  static const String _cacheDirectoryPathKey = 'reader_pref_cache_directory';

  @override
  Future<ReaderPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeRaw = prefs.getString(_readerModeKey);
    final mode = _parseMode(modeRaw);

    return ReaderPreferences(
      readerMode: mode,
      pageFit: _parsePageFit(prefs.getString(_pageFitKey)),
      background: _parseBackground(prefs.getString(_backgroundKey)),
      pageSpacing: _normalizePageSpacing(prefs.getDouble(_pageSpacingKey)),
      showPageIndicator: prefs.getBool(_showPageIndicatorKey) ?? true,
      cropBorders: prefs.getBool(_cropBordersKey) ?? false,
      fullscreenOnOpen: prefs.getBool(_fullscreenOnOpenKey) ?? false,
      cacheDirectoryPath: prefs.getString(_cacheDirectoryPathKey),
    );
  }

  @override
  Future<void> save(ReaderPreferences preferences) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readerModeKey, preferences.readerMode.name);
    await prefs.setString(_pageFitKey, preferences.pageFit.name);
    await prefs.setString(_backgroundKey, preferences.background.name);
    await prefs.setDouble(
      _pageSpacingKey,
      _normalizePageSpacing(preferences.pageSpacing),
    );
    await prefs.setBool(_showPageIndicatorKey, preferences.showPageIndicator);
    await prefs.setBool(_cropBordersKey, preferences.cropBorders);
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

  static ReaderPageFitPreference _parsePageFit(String? raw) {
    for (final value in ReaderPageFitPreference.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return ReaderPageFitPreference.fitWidth;
  }

  static ReaderBackgroundPreference _parseBackground(String? raw) {
    for (final value in ReaderBackgroundPreference.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return ReaderBackgroundPreference.followTheme;
  }

  static double _normalizePageSpacing(double? value) {
    final raw = value ?? ReaderPreferences.defaults().pageSpacing;
    return raw.clamp(0.0, 48.0).toDouble();
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
    await _persist(current.copyWith(pageSpacing: value.clamp(0.0, 48.0).toDouble()));
  }

  Future<void> setShowPageIndicator(bool value) async {
    final current = state.value ?? ReaderPreferences.defaults();
    await _persist(current.copyWith(showPageIndicator: value));
  }

  Future<void> setCropBorders(bool value) async {
    final current = state.value ?? ReaderPreferences.defaults();
    await _persist(current.copyWith(cropBorders: value));
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
