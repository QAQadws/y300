import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_navigation_settings_repository.dart';
import 'package:y300/core/preferences/preferences_providers.dart';

@immutable
final class MainNavigationControllerState {
  const MainNavigationControllerState({
    required this.settings,
    required this.isSaving,
  });

  factory MainNavigationControllerState.defaults() {
    return MainNavigationControllerState(
      settings: MainNavigationSettings.defaults(),
      isSaving: false,
    );
  }

  final MainNavigationSettings settings;
  final bool isSaving;

  MainNavigationControllerState copyWith({
    MainNavigationSettings? settings,
    bool? isSaving,
  }) {
    return MainNavigationControllerState(
      settings: settings ?? this.settings,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

final mainNavigationSettingsRepositoryProvider =
    Provider<MainNavigationSettingsRepository>((ref) {
      return SharedPrefsMainNavigationSettingsRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

final mainNavigationSettingsControllerProvider =
    AsyncNotifierProvider<
      MainNavigationSettingsController,
      MainNavigationControllerState
    >(MainNavigationSettingsController.new);

final class MainNavigationSettingsController
    extends AsyncNotifier<MainNavigationControllerState> {
  MainNavigationSettingsRepository get _repository =>
      ref.read(mainNavigationSettingsRepositoryProvider);

  @override
  Future<MainNavigationControllerState> build() async {
    try {
      return MainNavigationControllerState(
        settings: await _repository.load(),
        isSaving: false,
      );
    } on Object {
      return MainNavigationControllerState.defaults();
    }
  }

  Future<void> setVisibility(
    MainShellDestination destination,
    bool visible,
  ) async {
    if (!destination.isManaged) {
      throw ArgumentError.value(destination, 'destination');
    }
    final current = _requireReadyState();
    if (current.settings.isVisible(destination) == visible) {
      return;
    }
    if (!visible && current.settings.visibleManagedDestinations.length == 1) {
      throw const MainNavigationMinimumVisibleException();
    }
    final hidden = current.settings.hiddenDestinations.toSet();
    if (visible) {
      hidden.remove(destination);
    } else {
      hidden.add(destination);
    }
    await _persist(current.settings.copyWith(hiddenDestinations: hidden));
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = _requireReadyState();
    final order = current.settings.managedOrder.toList();
    if (oldIndex < 0 || oldIndex >= order.length) {
      throw RangeError.index(oldIndex, order, 'oldIndex');
    }
    if (newIndex < 0 || newIndex >= order.length) {
      throw RangeError.index(newIndex, order, 'newIndex');
    }
    if (newIndex == oldIndex) {
      return;
    }
    final destination = order.removeAt(oldIndex);
    order.insert(newIndex, destination);
    await _persist(current.settings.copyWith(managedOrder: order));
  }

  Future<void> resetToDefaults() {
    return _persist(MainNavigationSettings.defaults());
  }

  MainNavigationControllerState _requireReadyState() {
    final current = state.value;
    if (current == null) {
      throw StateError('Navigation settings are not ready');
    }
    if (current.isSaving) {
      throw const MainNavigationMutationInProgressException();
    }
    return current;
  }

  Future<void> _persist(MainNavigationSettings next) async {
    final previous = _requireReadyState();
    if (previous.settings == next) {
      return;
    }
    state = AsyncData(previous.copyWith(settings: next, isSaving: true));
    try {
      await _repository.save(next);
      if (ref.mounted) {
        state = AsyncData(
          MainNavigationControllerState(settings: next, isSaving: false),
        );
      }
    } catch (error, stackTrace) {
      if (ref.mounted) {
        state = AsyncData(previous.copyWith(isSaving: false));
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
