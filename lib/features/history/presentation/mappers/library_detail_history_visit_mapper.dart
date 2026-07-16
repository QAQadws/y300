import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

class LibraryDetailHistoryVisitMapper {
  const LibraryDetailHistoryVisitMapper();

  HistoryVisitDraft map({
    required LibraryModuleKey module,
    required LibraryDetailHeader header,
    required List<LibraryChapterItem> chapters,
  }) {
    final (targetType, surface, fallbackContext) = switch (module) {
      LibraryModuleKey.comic => (
        HistoryTargetType.comic,
        HistoryVisitSurface.comicDetail,
        '漫画详情',
      ),
      LibraryModuleKey.novel => (
        HistoryTargetType.novel,
        HistoryVisitSurface.novelDetail,
        '小说详情',
      ),
      LibraryModuleKey.favorite => throw ArgumentError.value(
        module,
        'module',
        'Favorite details are not work history targets',
      ),
    };
    final customLocalPath = _nonEmpty(header.customCoverLocalPath);
    final customRemoteUrl = _nonEmpty(header.customCoverImageUrl);
    // The shared Header applies focal alignment only when its displayed local
    // image is the custom cover. Mirror that rule in the history snapshot.
    final usesCustomCover = customLocalPath != null;
    final localPath = customLocalPath ?? _nonEmpty(header.coverLocalPath);
    final remoteUrl = customRemoteUrl ?? _nonEmpty(header.coverImageUrl);
    final currentChapter = _currentProgressChapter(chapters);

    return HistoryVisitDraft(
      target: HistoryTargetKey(type: targetType, id: header.workId),
      surface: surface,
      title: header.title,
      contextLabel: currentChapter?.title ?? fallbackContext,
      thumbnail: localPath == null && remoteUrl == null
          ? null
          : HistoryThumbnailSnapshot(
              localPath: localPath,
              remoteUrl: remoteUrl,
              focusX: usesCustomCover
                  ? _alignmentAxisToNormalized(header.customCoverFocusX)
                  : null,
              focusY: usesCustomCover
                  ? _alignmentAxisToNormalized(header.customCoverFocusY)
                  : null,
            ),
      sourceTid: header.sourceTid,
    );
  }

  LibraryChapterItem? _currentProgressChapter(
    List<LibraryChapterItem> chapters,
  ) {
    for (final chapter in chapters) {
      if (chapter.progressInfo?.isCurrent == true) {
        return chapter;
      }
    }
    return null;
  }

  double? _alignmentAxisToNormalized(double? value) {
    if (value == null || !value.isFinite) {
      return null;
    }
    final axis = value.clamp(-1.0, 1.0).toDouble();
    return (axis + 1) / 2;
  }

  String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
