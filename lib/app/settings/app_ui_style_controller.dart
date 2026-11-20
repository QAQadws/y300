import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_providers.dart';

enum AppUiStyle {
  classic,
  glassPremium,
  glassStandard;

  static const defaultStyle = classic;
}

final appUiStyleControllerProvider =
    AsyncNotifierProvider<AppUiStyleController, AppUiStyle>(
      AppUiStyleController.new,
    );

final class AppUiStyleController extends AsyncNotifier<AppUiStyle> {
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<AppUiStyle> build() async {
    final store = ref.watch(preferencesStoreProvider);
    try {
      final value = await store.read(PreferenceKeys.appUiStyle);
      return AppUiStyle.values.firstWhere(
        (style) => style.name == value,
        orElse: () => AppUiStyle.defaultStyle,
      );
    } on Object {
      return AppUiStyle.defaultStyle;
    }
  }

  Future<void> setStyle(AppUiStyle style) {
    final write = _pendingWrite.then((_) async {
      if (!ref.mounted) return;
      final current = state.value ?? await future;
      if (!ref.mounted || current == style) return;

      await ref
          .read(preferencesStoreProvider)
          .write(PreferenceKeys.appUiStyle, style.name);
      if (ref.mounted) state = AsyncData(style);
    });
    // A failed write must not prevent the next selection from being saved.
    _pendingWrite = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return write;
  }
}
