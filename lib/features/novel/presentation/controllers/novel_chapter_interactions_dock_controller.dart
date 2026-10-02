import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/library_shared/domain/models/reader_corner_dock_side.dart';
import 'package:y300/features/novel/data/preferences/novel_chapter_interactions_dock_preferences_provider.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';

final novelChapterInteractionsDockControllerProvider =
    AsyncNotifierProvider<
      NovelChapterInteractionsDockController,
      NovelChapterInteractionsDockPreferences
    >(NovelChapterInteractionsDockController.new);

final class NovelChapterInteractionsDockController
    extends AsyncNotifier<NovelChapterInteractionsDockPreferences> {
  Future<void> _writes = Future<void>.value();
  NovelChapterInteractionsDockPreferences _saved =
      const NovelChapterInteractionsDockPreferences();
  int _revision = 0;

  @override
  Future<NovelChapterInteractionsDockPreferences> build() async {
    final repository = ref.watch(
      novelChapterInteractionsDockPreferencesRepositoryProvider,
    );
    try {
      return _saved = await repository.load();
    } on Object {
      return _saved = const NovelChapterInteractionsDockPreferences();
    }
  }

  Future<bool> setEnabled(bool enabled) =>
      _update((current) => current.copyWith(enabled: enabled));

  Future<bool> setSide(ReaderCornerDockSide side) =>
      _update((current) => current.copyWith(side: side));

  Future<bool> _update(
    NovelChapterInteractionsDockPreferences Function(
      NovelChapterInteractionsDockPreferences,
    )
    transform,
  ) {
    final current = state.value;
    if (current == null) return Future<bool>.value(false);
    final next = transform(current);
    if (next.enabled == current.enabled && next.side == current.side) {
      return Future<bool>.value(true);
    }
    final repository = ref.read(
      novelChapterInteractionsDockPreferencesRepositoryProvider,
    );
    final revision = ++_revision;
    state = AsyncData(next);
    final result = _writes.then((_) async {
      try {
        await repository.save(next);
        _saved = next;
        return true;
      } on Object {
        if (ref.mounted && revision == _revision) {
          state = AsyncData(_saved);
          return false;
        }
        return true;
      }
    });
    _writes = result.then<void>((_) {});
    return result;
  }
}
