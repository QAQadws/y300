import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_history_coordinator.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class ForumWebViewHistoryVisitMapper {
  const ForumWebViewHistoryVisitMapper({
    ForumReferenceResolver urlParser = const ForumReferenceResolver(),
  }) : _urlParser = urlParser;

  final ForumReferenceResolver _urlParser;

  HistoryVisitDraft map(ForumWebViewHistoryCandidate candidate) {
    final page = _extractPage(candidate.finalUri);
    final forumName = _nonEmpty(candidate.forumName);
    final firstPostImageUrl = _nonEmpty(candidate.document.firstPostImageUrl);
    return HistoryVisitDraft(
      target: HistoryTargetKey(
        type: HistoryTargetType.thread,
        id: candidate.tid,
      ),
      surface: HistoryVisitSurface.threadWebView,
      title: _nonEmpty(candidate.document.title),
      contextLabel:
          forumName ?? (page != null && page > 1 ? '第 $page 页' : null),
      thumbnail: firstPostImageUrl == null
          ? null
          : HistoryThumbnailSnapshot(remoteUrl: firstPostImageUrl),
      canonicalUri: _normalizedCanonicalUri(candidate),
      page: page,
      forumName: forumName,
    );
  }

  Uri? _normalizedCanonicalUri(ForumWebViewHistoryCandidate candidate) {
    for (final uri in <Uri?>[
      candidate.document.canonicalUri,
      candidate.finalUri,
    ]) {
      if (uri == null) {
        continue;
      }
      final normalized = _urlParser.normalizeHref(uri.toString());
      final parsed = normalized == null ? null : Uri.tryParse(normalized);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  int? _extractPage(Uri uri) {
    final rawPage = _rawQueryValue(uri.query, 'page');
    final queryPage = int.tryParse(rawPage?.trim() ?? '');
    if (queryPage != null && queryPage > 0) {
      return queryPage;
    }
    final pathPage = int.tryParse(
      RegExp(
            r'thread-\d+-(\d+)-\d+\.html',
            caseSensitive: false,
          ).firstMatch(uri.path)?.group(1) ??
          '',
    );
    return pathPage != null && pathPage > 0 ? pathPage : null;
  }

  String? _rawQueryValue(String rawQuery, String key) {
    final normalizedKey = key.toLowerCase();
    for (final segment in rawQuery.split(RegExp(r'[&;]'))) {
      final separator = segment.indexOf('=');
      if (separator <= 0 ||
          segment.substring(0, separator).trim().toLowerCase() !=
              normalizedKey) {
        continue;
      }
      return segment.substring(separator + 1);
    }
    return null;
  }

  String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
