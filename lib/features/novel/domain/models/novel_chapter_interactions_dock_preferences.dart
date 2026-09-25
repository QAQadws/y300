import 'package:y300/features/library_shared/domain/models/reader_corner_dock_side.dart';

final class NovelChapterInteractionsDockPreferences {
  const NovelChapterInteractionsDockPreferences({
    this.enabled = true,
    this.side = ReaderCornerDockSide.right,
  });

  final bool enabled;
  final ReaderCornerDockSide side;

  NovelChapterInteractionsDockPreferences copyWith({
    bool? enabled,
    ReaderCornerDockSide? side,
  }) => NovelChapterInteractionsDockPreferences(
    enabled: enabled ?? this.enabled,
    side: side ?? this.side,
  );
}
