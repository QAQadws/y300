import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/presentation/mappers/library_detail_history_visit_mapper.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

void main() {
  const mapper = LibraryDetailHistoryVisitMapper();

  test('maps the currently displayed comic header and progress chapter', () {
    final draft = mapper.map(
      module: LibraryModuleKey.comic,
      header: const LibraryDetailHeader(
        workId: ' comic:1 ',
        title: 'Resolved Comic Title',
        coverLocalPath: 'source-cover.jpg',
        customCoverLocalPath: 'custom-cover.jpg',
        coverImageUrl: 'https://img.test/source.jpg',
        customCoverImageUrl: 'https://img.test/custom.jpg',
        customCoverFocusX: -0.5,
        customCoverFocusY: 1,
        sourceTid: '527325',
        inShelf: true,
      ),
      chapters: const [
        LibraryChapterItem(
          episodeId: 'e1',
          workId: 'comic:1',
          title: 'Episode 1',
          orderIndex: 0,
        ),
        LibraryChapterItem(
          episodeId: 'e2',
          workId: 'comic:1',
          title: 'Episode 2',
          orderIndex: 1,
          progressInfo: LibraryChapterProgressInfo(
            kind: LibraryChapterProgressKind.currentPage,
            isCurrent: true,
            currentPage: 3,
          ),
        ),
      ],
    );

    expect(
      draft.target,
      const HistoryTargetKey(type: HistoryTargetType.comic, id: ' comic:1 '),
    );
    expect(draft.surface, HistoryVisitSurface.comicDetail);
    expect(draft.title, 'Resolved Comic Title');
    expect(draft.contextLabel, 'Episode 2');
    expect(draft.sourceTid, '527325');
    expect(draft.thumbnail?.localPath, 'custom-cover.jpg');
    expect(draft.thumbnail?.remoteUrl, 'https://img.test/custom.jpg');
    expect(draft.thumbnail?.focusX, 0.25);
    expect(draft.thumbnail?.focusY, 1);
  });

  test('maps a coverless novel with the detail fallback context', () {
    final draft = mapper.map(
      module: LibraryModuleKey.novel,
      header: const LibraryDetailHeader(
        workId: 'novel:1',
        title: 'Resolved Novel Title',
        sourceTid: '564823',
        inShelf: true,
      ),
      chapters: const [],
    );

    expect(
      draft.target,
      const HistoryTargetKey(type: HistoryTargetType.novel, id: 'novel:1'),
    );
    expect(draft.surface, HistoryVisitSurface.novelDetail);
    expect(draft.contextLabel, '小说详情');
    expect(draft.thumbnail, isNull);
    expect(draft.sourceTid, '564823');
  });

  test('rejects favorite details as unsupported history targets', () {
    expect(
      () => mapper.map(
        module: LibraryModuleKey.favorite,
        header: const LibraryDetailHeader(
          workId: 'favorite:1',
          title: 'Favorite',
          inShelf: true,
        ),
        chapters: const [],
      ),
      throwsArgumentError,
    );
  });
}
