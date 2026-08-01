import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

class NovelCatalogEntry {
  const NovelCatalogEntry({
    required this.pid,
    required this.title,
    required this.position,
  });

  final String pid;
  final String title;
  final int position;
}

/// Extracts same-thread chapter catalogs from the first OP floors.
///
/// Yamibo novel threads normally keep all chapters inside one tid and jump by
/// pid (`mod=redirect&goto=findpost&ptid=<tid>&pid=<pid>`). This extractor owns
/// that novel-specific rule so the shared DOM extractor can stay domain-neutral.
class NovelSameThreadCatalogExtractor {
  const NovelSameThreadCatalogExtractor({
    this.maxScanFloor = 10,
    this.minCatalogEntries = 2,
    ForumPostDomExtractor? domExtractor,
  }) : _domExtractor = domExtractor ?? const ForumPostDomExtractor();

  final int maxScanFloor;
  final int minCatalogEntries;
  final ForumPostDomExtractor _domExtractor;

  List<NovelCatalogEntry> extract({
    required String threadTid,
    required String opAuthorId,
    required List<ThreadPost> posts,
  }) {
    final sorted = [...posts]..sort((a, b) => a.number.compareTo(b.number));
    final entries = <NovelCatalogEntry>[];
    final seenPids = <String>{};

    for (final post in sorted) {
      if (post.number > maxScanFloor) {
        break;
      }
      if (opAuthorId.isNotEmpty && post.authorId != opAuthorId) {
        continue;
      }
      final anchors = _domExtractor.extractAnchors(post.message);
      for (final anchor in anchors) {
        final entry = _tryParseCatalogEntry(
          threadTid: threadTid,
          rawTitle: anchor.text,
          normalizedUrl: anchor.normalizedUrl,
          position: entries.length,
        );
        if (entry == null || !seenPids.add(entry.pid)) {
          continue;
        }
        entries.add(entry);
      }
    }

    if (entries.length < minCatalogEntries) {
      return const <NovelCatalogEntry>[];
    }
    return entries;
  }

  NovelCatalogEntry? _tryParseCatalogEntry({
    required String threadTid,
    required String rawTitle,
    required String normalizedUrl,
    required int position,
  }) {
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.path.toLowerCase().endsWith('forum.php')) {
      return null;
    }
    final params = uri.queryParameters;
    final mod = params['mod']?.toLowerCase();
    final goto = params['goto']?.toLowerCase();
    if (mod != 'redirect' || goto != 'findpost') {
      return null;
    }

    final targetTid = (params['ptid'] ?? params['tid'])?.trim();
    final pid = params['pid']?.trim();
    if (targetTid != threadTid || pid == null || pid.isEmpty) {
      return null;
    }

    final title = _normalizeTitle(rawTitle);
    if (title == null) {
      return null;
    }
    return NovelCatalogEntry(pid: pid, title: title, position: position);
  }

  String? _normalizeTitle(String rawTitle) {
    // Keep full-width spaces inside titles. Yamibo novel catalog titles may use
    // them deliberately for labels such as "序　章"; collapsing all \s would
    // change the user-visible chapter name.
    final title = rawTitle.replaceAll(RegExp(r'[ \t\r\n]+'), ' ').trim();
    if (title.isEmpty) {
      return null;
    }
    final lower = title.toLowerCase();
    if (title == '目录' || lower == 'contents' || lower == 'catalog') {
      return null;
    }
    return title;
  }
}
