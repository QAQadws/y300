import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

/// Extracts source catalog links from exactly one first post.
///
/// The catalog is diagnostic metadata only. It never creates chapters and it
/// deliberately does not inspect later posts from a version=4 response.
class NovelFirstPostCatalogExtractor {
  const NovelFirstPostCatalogExtractor({
    ForumPostDomExtractor domExtractor = const ForumPostDomExtractor(),
  }) : _domExtractor = domExtractor;

  final ForumPostDomExtractor _domExtractor;

  List<NovelSourceCatalogEntry> extract({
    required String threadTid,
    required ThreadPost firstPost,
  }) {
    final normalizedTid = threadTid.trim();
    if (normalizedTid.isEmpty) {
      return const <NovelSourceCatalogEntry>[];
    }

    final entries = <NovelSourceCatalogEntry>[];
    final seenPids = <String>{};
    for (final anchor in _domExtractor.extractAnchors(firstPost.message)) {
      final entry = _tryParseEntry(
        threadTid: normalizedTid,
        title: anchor.text,
        normalizedUrl: anchor.normalizedUrl,
        position: entries.length,
      );
      if (entry != null && seenPids.add(entry.pid)) {
        entries.add(entry);
      }
    }
    return List<NovelSourceCatalogEntry>.unmodifiable(entries);
  }

  NovelSourceCatalogEntry? _tryParseEntry({
    required String threadTid,
    required String title,
    required String normalizedUrl,
    required int position,
  }) {
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.path.toLowerCase().endsWith('forum.php')) {
      return null;
    }
    final rawQuery = uri.query;
    if (_rawQueryValue(rawQuery, 'mod')?.toLowerCase() != 'redirect' ||
        _rawQueryValue(rawQuery, 'goto')?.toLowerCase() != 'findpost') {
      return null;
    }

    final targetTid =
        _rawQueryValue(rawQuery, 'ptid') ?? _rawQueryValue(rawQuery, 'tid');
    final pid = _rawQueryValue(rawQuery, 'pid')?.trim();
    if (targetTid?.trim() != threadTid ||
        pid == null ||
        !RegExp(r'^[1-9]\d*$').hasMatch(pid)) {
      return null;
    }

    final normalizedTitle = _normalizeTitle(title);
    if (normalizedTitle == null) {
      return null;
    }
    return NovelSourceCatalogEntry(
      position: position,
      pid: pid,
      title: normalizedTitle,
      url: uri
          .replace(query: 'mod=redirect&goto=findpost&ptid=$threadTid&pid=$pid')
          .removeFragment()
          .toString(),
    );
  }

  String? _rawQueryValue(String rawQuery, String key) {
    final expectedKey = key.toLowerCase();
    for (final part in rawQuery.split(RegExp(r'[&;]'))) {
      final separator = part.indexOf('=');
      if (separator <= 0 ||
          part.substring(0, separator).trim().toLowerCase() != expectedKey) {
        continue;
      }
      return part.substring(separator + 1);
    }
    return null;
  }

  String? _normalizeTitle(String source) {
    final normalized = source
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t\r\n]+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }
    final lower = normalized.toLowerCase();
    if (normalized == '目录' ||
        normalized == '目錄' ||
        lower == 'contents' ||
        lower == 'catalog') {
      return null;
    }
    return normalized;
  }
}
