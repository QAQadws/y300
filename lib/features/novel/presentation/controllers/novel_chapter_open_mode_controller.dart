import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';

final novelChapterOpenModeControllerProvider =
    AsyncNotifierProvider<NovelChapterOpenModeController, NovelChapterOpenMode>(
      NovelChapterOpenModeController.new,
    );

class NovelChapterOpenModeController
    extends AsyncNotifier<NovelChapterOpenMode> {
  @override
  FutureOr<NovelChapterOpenMode> build() {
    return ref
        .read(novelInteractionPreferencesRepositoryProvider)
        .loadChapterOpenMode();
  }

  Future<void> updateMode(NovelChapterOpenMode nextMode) async {
    final previousMode = state.value ?? NovelChapterOpenMode.reader;
    if (previousMode == nextMode) {
      return;
    }
    state = AsyncData(nextMode);
    try {
      await ref
          .read(novelInteractionPreferencesRepositoryProvider)
          .saveChapterOpenMode(nextMode);
    } catch (error, stackTrace) {
      state = AsyncData(previousMode);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
