import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/presentation/novel_text_resolver.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  final simplified = AppLocalizationsZh();
  final traditional = AppLocalizationsZhTw();

  test('preserves raw work and chapter titles in both locales', () {
    const rawWorkTitle = 'Raw 小說标题 01';
    const rawChapterTitle = 'Raw 章節标题 EP.7';

    for (final locale in <AppLocalizationsZh>[simplified, traditional]) {
      expect(
        NovelTextResolver.workTitle(locale, rawWorkTitle, 'novel:100'),
        rawWorkTitle,
      );
      expect(
        NovelTextResolver.chapterTitle(locale, rawChapterTitle, '571564'),
        rawChapterTitle,
      );
    }
  });

  test('localizes empty title fallbacks at presentation time', () {
    expect(
      NovelTextResolver.workTitle(simplified, '', 'novel:100'),
      simplified.novelUntitledWork('novel:100'),
    );
    expect(
      NovelTextResolver.workTitle(traditional, '', 'novel:100'),
      traditional.novelUntitledWork('novel:100'),
    );
    expect(
      NovelTextResolver.chapterTitle(simplified, '', '571564'),
      simplified.novelChapterFallbackTitle('571564'),
    );
    expect(
      NovelTextResolver.chapterTitle(traditional, '', '571564'),
      traditional.novelChapterFallbackTitle('571564'),
    );
    expect(
      NovelTextResolver.workTitle(traditional, '未命名小说', 'novel:100'),
      traditional.novelUntitledWork('novel:100'),
    );
    expect(
      NovelTextResolver.chapterTitle(traditional, '未命名章节', '571564'),
      traditional.novelChapterFallbackTitle('571564'),
    );
  });

  test('maps legacy source errors to a localized unknown failure', () {
    final code = NovelChapterSyncFailureCodeCodec.fromStorage(
      'network failure',
    );

    expect(code, NovelChapterSyncFailureCode.unknown);
    expect(
      NovelTextResolver.syncFailure(simplified, code, null),
      simplified.novelChapterLoadUnknown,
    );
    expect(
      NovelTextResolver.syncFailure(traditional, code, null),
      traditional.novelChapterLoadUnknown,
    );
  });
}
