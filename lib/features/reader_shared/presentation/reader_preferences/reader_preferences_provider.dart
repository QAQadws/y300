import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';

/// 持久化抽象，让存储实现与状态编排解耦。
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

final readerPreferencesRepositoryProvider =
    Provider<ReaderPreferencesRepository>(
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
