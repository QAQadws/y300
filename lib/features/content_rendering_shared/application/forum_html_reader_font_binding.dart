import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/fonts/fonts.dart';

import '../domain/models/forum_html_reader_preferences.dart';
import 'forum_html_reader_preferences_controller.dart';

/// The preference snapshot and actual loaded font always describe one layout.
final class ForumHtmlReaderFontBinding {
  const ForumHtmlReaderFontBinding({
    required this.preferences,
    required this.resolution,
    required this.isReady,
  });

  final ForumHtmlReaderPreferences preferences;
  final FontResolution resolution;
  final bool isReady;

  ResolvedFont get resolvedFont => resolution.font;
  String get cacheKey => resolvedFont.cacheKey;
}

final forumHtmlReaderFontBindingProvider = Provider<ForumHtmlReaderFontBinding>(
  (ref) {
    final state = ref.watch(forumHtmlReaderPreferencesControllerProvider);
    final controller = ref.read(
      forumHtmlReaderPreferencesControllerProvider.notifier,
    );
    final preferences = state.value ?? ForumHtmlReaderPreferences.defaults();
    final resolution = state.hasError && !state.hasValue
        ? const FontResolution(
            requestedId: FontIdentity.system,
            font: ResolvedFont.system,
          )
        : controller.fontResolution;
    return ForumHtmlReaderFontBinding(
      preferences: preferences,
      resolution: resolution,
      isReady:
          (state.hasValue && preferences.fontFamily == resolution.font.id) ||
          (state.hasError && !state.hasValue),
    );
  },
);
