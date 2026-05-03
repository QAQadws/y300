import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

/// Phase 1 章节发现：先做稳定最小实现。
///
/// 规则：
/// 1. 仅解析楼主楼层。
/// 2. 每个楼主楼层作为一个章节。
/// 3. 章节标题优先使用“第x章/话/节”匹配，否则回退“第N节（PID）”。
class NovelEpisodeDiscoveryService {
  const NovelEpisodeDiscoveryService();

  NovelRefreshPlan buildPlan({
    required String novelId,
    required List<ThreadDetailData> pages,
  }) {
    if (pages.isEmpty) {
      throw StateError('线程页面为空，无法生成章节计划');
    }

    final firstPage = pages.first;
    final opAuthorId = firstPage.posts.isEmpty ? '' : firstPage.posts.first.authorId;
    var order = 0;
    final episodes = <NovelEpisodeDraft>[];

    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final page = pages[pageIndex];
      for (final post in page.posts) {
        if (opAuthorId.isNotEmpty && post.authorId != opAuthorId) {
          continue;
        }
        final plainText = _toPlainText(post.message);
        if (plainText.isEmpty) {
          continue;
        }
        final paragraphs = _splitParagraphs(plainText);
        final title = _resolveEpisodeTitle(post: post, fallbackOrder: order + 1, plainText: plainText);
        final pageNumber = page.currentPage > 0 ? page.currentPage : (pageIndex + 1);
        episodes.add(
          NovelEpisodeDraft(
            episodeId: '$novelId:${post.pid}',
            novelId: novelId,
            sourceTid: page.tid,
            sourcePid: post.pid,
            sourcePage: pageNumber,
            episodeTitle: title,
            orderIndex: order,
            datelineText: post.dateline,
            rawHtml: post.message,
            plainText: plainText,
            paragraphs: paragraphs,
          ),
        );
        order++;
      }
    }

    return NovelRefreshPlan(
      tid: firstPage.tid,
      subject: firstPage.subject,
      author: firstPage.author,
      episodes: episodes,
    );
  }

  String _toPlainText(String rawHtml) {
    final fragment = html_parser.parseFragment(rawHtml);
    final text = (fragment.text ?? '')
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\r\n|\r'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    return text;
  }

  List<String> _splitParagraphs(String plainText) {
    return plainText
        .split(RegExp(r'\n{1,}'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String _resolveEpisodeTitle({
    required ThreadPost post,
    required int fallbackOrder,
    required String plainText,
  }) {
    final direct = RegExp(r'(第\s*[0-9一二三四五六七八九十百千零〇两\.]+\s*[章节话回卷])')
        .firstMatch(plainText)
        ?.group(1)
        ?.replaceAll(RegExp(r'\s+'), '');
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    if (post.number == 1) {
      return '序章';
    }

    return '第$fallbackOrder节（PID:${post.pid}）';
  }
}
