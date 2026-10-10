import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/clipboard/clipboard_link_settings_repository.dart';
import 'package:y300/core/preferences/preferences_providers.dart';

@immutable
final class ClipboardLinkSettingsState {
  const ClipboardLinkSettingsState({
    required this.enabled,
    this.isSaving = false,
  });

  final bool enabled;
  final bool isSaving;
}

final clipboardLinkSettingsRepositoryProvider =
    Provider<ClipboardLinkSettingsRepository>((ref) {
      return SharedPrefsClipboardLinkSettingsRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

final clipboardLinkSettingsControllerProvider =
    AsyncNotifierProvider<
      ClipboardLinkSettingsController,
      ClipboardLinkSettingsState
    >(ClipboardLinkSettingsController.new);

final class ClipboardLinkSettingsController
    extends AsyncNotifier<ClipboardLinkSettingsState> {
  var _generation = 0;

  @override
  Future<ClipboardLinkSettingsState> build() async {
    _generation++;
    final repository = ref.watch(clipboardLinkSettingsRepositoryProvider);
    return ClipboardLinkSettingsState(enabled: await repository.loadEnabled());
  }

  Future<void> setEnabled(bool enabled) async {
    final previous = state.asData?.value;
    if (previous == null) {
      throw StateError('Clipboard link settings are not ready');
    }
    if (previous.isSaving) {
      throw StateError('Clipboard link settings mutation is in progress');
    }
    if (previous.enabled == enabled) return;
    final generation = _generation;
    final repository = ref.read(clipboardLinkSettingsRepositoryProvider);
    // Disabling takes effect before persistence so pending clipboard work is
    // retired immediately. A failed write restores the confirmed preference.
    state = AsyncData(
      ClipboardLinkSettingsState(enabled: enabled, isSaving: true),
    );
    try {
      await repository.saveEnabled(enabled);
      if (ref.mounted && generation == _generation) {
        state = AsyncData(ClipboardLinkSettingsState(enabled: enabled));
      }
    } catch (error, stackTrace) {
      if (ref.mounted && generation == _generation) {
        state = AsyncData(previous);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
