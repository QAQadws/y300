import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/more/data/more_settings_repository.dart';

class CacheSettingsViewState {
  const CacheSettingsViewState({
    required this.defaultDirectory,
    required this.customDirectory,
    required this.effectiveDirectory,
    required this.isUpdating,
    this.hint,
  });

  final String defaultDirectory;
  final String? customDirectory;
  final String effectiveDirectory;
  final bool isUpdating;
  final String? hint;

  CacheSettingsViewState copyWith({
    String? defaultDirectory,
    String? customDirectory,
    String? effectiveDirectory,
    bool? isUpdating,
    String? hint,
    bool clearCustomDirectory = false,
    bool clearHint = false,
  }) {
    return CacheSettingsViewState(
      defaultDirectory: defaultDirectory ?? this.defaultDirectory,
      customDirectory: clearCustomDirectory ? null : (customDirectory ?? this.customDirectory),
      effectiveDirectory: effectiveDirectory ?? this.effectiveDirectory,
      isUpdating: isUpdating ?? this.isUpdating,
      hint: clearHint ? null : (hint ?? this.hint),
    );
  }
}

final moreSettingsRepositoryProvider = Provider<MoreSettingsRepository>(
  (ref) => MoreSettingsRepositoryImpl(),
);

final cacheSettingsControllerProvider =
    AsyncNotifierProvider.autoDispose<CacheSettingsController, CacheSettingsViewState>(
  CacheSettingsController.new,
);

class CacheSettingsController extends AsyncNotifier<CacheSettingsViewState> {
  late final MoreSettingsRepository _repository;

  @override
  Future<CacheSettingsViewState> build() async {
    _repository = ref.read(moreSettingsRepositoryProvider);
    final defaultDir = await _repository.getDefaultCacheDirectory();
    final customDir = await _repository.getCustomCacheDirectory();
    final effectiveDir = customDir ?? defaultDir;

    return CacheSettingsViewState(
      defaultDirectory: defaultDir,
      customDirectory: customDir,
      effectiveDirectory: effectiveDir,
      isUpdating: false,
    );
  }

  Future<void> chooseCustomDirectory() async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearHint: true));

    final selected = await _repository.pickDirectory();
    if (!ref.mounted) {
      return;
    }
    if (selected == null || selected.trim().isEmpty) {
      state = AsyncData(current.copyWith(isUpdating: false, hint: '未选择目录'));
      return;
    }

    await _repository.setCustomCacheDirectory(selected);
    if (!ref.mounted) {
      return;
    }
    final nextCustom = await _repository.getCustomCacheDirectory();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        customDirectory: nextCustom,
        effectiveDirectory: nextCustom ?? current.defaultDirectory,
        isUpdating: false,
        hint: '缓存目录已更新',
      ),
    );
  }

  Future<void> restoreDefaultDirectory() async {
    final current = state.value;
    if (current == null || current.isUpdating) {
      return;
    }
    state = AsyncData(current.copyWith(isUpdating: true, clearHint: true));
    await _repository.setCustomCacheDirectory(null);
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        clearCustomDirectory: true,
        effectiveDirectory: current.defaultDirectory,
        isUpdating: false,
        hint: '已恢复默认目录',
      ),
    );
  }
}
