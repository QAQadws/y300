import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_visit_draft_normalizer.dart';

void main() {
  const normalizer = HistoryVisitDraftNormalizer();

  test('normalizes thread identity, text, route and thumbnail snapshot', () {
    final normalized = normalizer.normalize(
      HistoryVisitDraft(
        target: const HistoryTargetKey(
          type: HistoryTargetType.thread,
          id: ' 000527325 ',
        ),
        surface: HistoryVisitSurface.threadNative,
        title: '  测试\n  主题  ',
        contextLabel: '  中文   百合区 ',
        thumbnail: const HistoryThumbnailSnapshot(
          localPath: '  C:/covers/a.jpg  ',
          remoteUrl: 'https://example.com/avatar.jpg',
          focusX: -2,
          focusY: 3,
        ),
        sourceTid: '000527325',
        canonicalUri: Uri.parse(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=527325&page=4&highlight=%D2%B2%CE%DE&formhash=secret#pid1',
        ),
        page: 4,
        forumName: ' 中文百合漫画区 ',
      ),
    );

    expect(normalized.target.id, '527325');
    expect(normalized.title, '测试 主题');
    expect(normalized.contextLabel, '中文 百合区');
    expect(normalized.sourceTid, '527325');
    expect(normalized.page, 4);
    expect(normalized.forumName, '中文百合漫画区');
    expect(
      normalized.canonicalUri.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=527325',
    );
    expect(normalized.thumbnail?.localPath, 'C:/covers/a.jpg');
    expect(normalized.thumbnail?.focusX, 0);
    expect(normalized.thumbnail?.focusY, 1);
  });

  test('uses type fallbacks and truncates title by grapheme cluster', () {
    final family = '👨‍👩‍👧‍👦';
    final normalized = normalizer.normalize(
      HistoryVisitDraft(
        target: const HistoryTargetKey(
          type: HistoryTargetType.comic,
          id: ' comic:1 ',
        ),
        surface: HistoryVisitSurface.comicDetail,
        title: List<String>.filled(201, family).join(),
        page: 0,
      ),
    );
    final untitled = normalizer.normalize(
      const HistoryVisitDraft(
        target: HistoryTargetKey(type: HistoryTargetType.novel, id: 'novel:1'),
        surface: HistoryVisitSurface.novelDetail,
      ),
    );

    expect(normalized.title?.characters.length, 200);
    expect(normalized.title?.endsWith(family), isTrue);
    expect(normalized.contextLabel, '漫画详情');
    expect(normalized.page, isNull);
    expect(untitled.title, '未命名小说');
    expect(untitled.contextLabel, '小说详情');
  });

  test('rejects empty ids, invalid tids and mismatched surfaces', () {
    expect(
      () => normalizer.normalize(
        const HistoryVisitDraft(
          target: HistoryTargetKey(type: HistoryTargetType.comic, id: ' '),
          surface: HistoryVisitSurface.comicDetail,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => normalizer.normalize(
        const HistoryVisitDraft(
          target: HistoryTargetKey(type: HistoryTargetType.thread, id: '0'),
          surface: HistoryVisitSurface.threadNative,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => normalizer.normalize(
        const HistoryVisitDraft(
          target: HistoryTargetKey(type: HistoryTargetType.novel, id: 'n1'),
          surface: HistoryVisitSurface.comicDetail,
        ),
      ),
      throwsFormatException,
    );
  });

  test('drops unsupported URLs and empty thumbnail snapshots', () {
    final normalized = normalizer.normalize(
      HistoryVisitDraft(
        target: const HistoryTargetKey(
          type: HistoryTargetType.novel,
          id: 'novel:1',
        ),
        surface: HistoryVisitSurface.novelDetail,
        thumbnail: const HistoryThumbnailSnapshot(
          localPath: ' ',
          remoteUrl: 'file:///private/cover.jpg',
        ),
        canonicalUri: Uri.parse('javascript:alert(1)'),
      ),
    );

    expect(normalized.thumbnail, isNull);
    expect(normalized.canonicalUri, isNull);
  });

  test('removes sensitive raw query fields without decoding legacy bytes', () {
    final normalized = normalizer.normalize(
      HistoryVisitDraft(
        target: const HistoryTargetKey(
          type: HistoryTargetType.novel,
          id: 'novel:1',
        ),
        surface: HistoryVisitSurface.novelDetail,
        canonicalUri: Uri.parse(
          'https://example.com/work?id=1&token=secret&highlight=%D2%B2%CE%DE#chapter',
        ),
      ),
    );

    expect(normalized.canonicalUri.toString(), 'https://example.com/work?id=1');
  });
}
