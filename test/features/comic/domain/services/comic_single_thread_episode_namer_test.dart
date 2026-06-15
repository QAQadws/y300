import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_single_thread_episode_namer.dart';

void main() {
  group('DefaultComicSingleThreadEpisodeNamer', () {
    const namer = DefaultComicSingleThreadEpisodeNamer();

    test('优先使用解析后的章节标签', () {
      final result = namer.resolve(
        metadata: const ComicSubjectMetadata(
          normalizedTitle: '测试漫画',
          episodeLabel: '第3话',
        ),
        fallbackComicTitle: '【某汉化组】测试漫画 第3话',
      );

      expect(result, '第3话');
    });

    test('章节标签为空时回落到规范化书名', () {
      final result = namer.resolve(
        metadata: const ComicSubjectMetadata(
          normalizedTitle: '单帖漫画',
          // episodeLabel 缺失：标题分析器没识别出章节标记，
          // 表示整本作品就是这一帖，话名等于书名最直观。
        ),
        fallbackComicTitle: '【组A】单帖漫画',
      );

      expect(result, '单帖漫画');
    });

    test('两段元数据都为空白时回落到原始标题', () {
      final result = namer.resolve(
        metadata: const ComicSubjectMetadata(
          normalizedTitle: '   ',
          episodeLabel: '',
        ),
        fallbackComicTitle: '原始标题',
      );

      expect(result, '原始标题');
    });

    test('metadata 为 null 时也能用原始标题兜底', () {
      final result = namer.resolve(
        fallbackComicTitle: '只剩 raw subject',
      );

      expect(result, '只剩 raw subject');
    });

    test('全部都空才退到历史占位 "首楼"', () {
      final result = namer.resolve(
        metadata: const ComicSubjectMetadata(normalizedTitle: ''),
        fallbackComicTitle: '   ',
      );

      // 这是最后一道安全网：尽量不让 NULL/空字符串泄漏到 UI。
      expect(result, '首楼');
    });

    test('章节标签前后空白会被裁剪', () {
      final result = namer.resolve(
        metadata: const ComicSubjectMetadata(
          normalizedTitle: '测试漫画',
          episodeLabel: '  第1话  ',
        ),
        fallbackComicTitle: '测试漫画 第1话',
      );

      expect(result, '第1话');
    });
  });
}
