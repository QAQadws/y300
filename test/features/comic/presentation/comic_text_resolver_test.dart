import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/presentation/comic_text_resolver.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  final simplified = AppLocalizationsZh();
  final traditional = AppLocalizationsZhTw();

  test('preserves raw work and chapter titles in both locales', () {
    const rawWorkTitle = 'Raw 漫畫标题 01';
    const rawChapterTitle = 'Raw 章節标题 EP.7';

    for (final locale in <AppLocalizationsZh>[simplified, traditional]) {
      expect(
        ComicTextResolver.workTitle(locale, rawWorkTitle, 'comic:100'),
        rawWorkTitle,
      );
      expect(
        ComicTextResolver.chapterTitle(locale, rawChapterTitle, '571564'),
        rawChapterTitle,
      );
    }
  });

  test('localizes empty title fallbacks at presentation time', () {
    expect(
      ComicTextResolver.workTitle(simplified, '', 'comic:100'),
      simplified.comicUntitledWork('comic:100'),
    );
    expect(
      ComicTextResolver.workTitle(traditional, '', 'comic:100'),
      traditional.comicUntitledWork('comic:100'),
    );
    expect(
      ComicTextResolver.chapterTitle(simplified, '', '571564'),
      simplified.comicChapterFallbackTitle('571564'),
    );
    expect(
      ComicTextResolver.chapterTitle(traditional, '', '571564'),
      traditional.comicChapterFallbackTitle('571564'),
    );
    expect(
      ComicTextResolver.workTitle(traditional, '未命名漫画', 'comic:100'),
      traditional.comicUntitledWork('comic:100'),
    );
    expect(
      ComicTextResolver.chapterTitle(traditional, '章节 571564', '571564'),
      traditional.comicChapterFallbackTitle('571564'),
    );
    expect(
      ComicTextResolver.chapterTitle(traditional, '571564', '571564'),
      traditional.comicChapterFallbackTitle('571564'),
    );
  });

  test('maps legacy download errors to a localized unknown failure', () {
    final code = ComicDownloadFailureCodeCodec.fromStorage('网络失败');

    expect(code, ComicDownloadFailureCode.unknown);
    expect(
      ComicTextResolver.downloadFailure(simplified, code),
      simplified.comicDownloadUnknownFailure,
    );
    expect(
      ComicTextResolver.downloadFailure(traditional, code),
      traditional.comicDownloadUnknownFailure,
    );
  });

  test('derives source TID from the stable download episode id', () {
    final entry = ComicDownloadQueueEntry(
      id: 1,
      comicId: 'comic:55:100',
      episodeId: 'comic:55:100:571564',
      comicTitle: '',
      episodeTitle: '571564',
      status: ComicDownloadQueueStatus.pending,
      completedImages: 0,
      totalImages: null,
      lastError: null,
      createdAt: DateTime(2026, 7, 28),
      updatedAt: DateTime(2026, 7, 28),
    );

    expect(entry.sourceTid, '571564');
  });
}
