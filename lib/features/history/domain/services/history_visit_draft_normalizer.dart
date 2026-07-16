import 'package:characters/characters.dart';
import 'package:y300/features/history/domain/models/history_models.dart';

class HistoryVisitDraftNormalizer {
  const HistoryVisitDraftNormalizer({this.maxTitleCharacters = 200});

  final int maxTitleCharacters;

  HistoryVisitDraft normalize(HistoryVisitDraft draft) {
    final target = _normalizeTarget(draft.target);
    _validateSurface(target.type, draft.surface);
    final page = draft.page != null && draft.page! > 0 ? draft.page : null;
    final forumName = _normalizeOptionalText(draft.forumName);
    final sourceTid = _normalizePositiveInteger(draft.sourceTid);
    final title = _normalizeTitle(draft.title, target);
    final contextLabel = _normalizeContextLabel(
      draft.contextLabel,
      target: target,
      forumName: forumName,
      page: page,
    );

    return HistoryVisitDraft(
      target: target,
      surface: draft.surface,
      title: title,
      contextLabel: contextLabel,
      thumbnail: _normalizeThumbnail(draft.thumbnail),
      sourceTid: sourceTid,
      canonicalUri: _normalizeCanonicalUri(
        draft.canonicalUri,
        target,
        sourceTid: sourceTid,
      ),
      page: page,
      forumName: forumName,
    );
  }

  String normalizeSearchText(String value) => _collapseWhitespace(value);

  HistoryTargetKey _normalizeTarget(HistoryTargetKey target) {
    final rawId = target.id.trim();
    if (rawId.isEmpty) {
      throw const FormatException('History target id must not be empty');
    }
    if (target.type == HistoryTargetType.thread) {
      final tid = _normalizePositiveInteger(rawId);
      if (tid == null) {
        throw FormatException('Invalid history thread id: $rawId');
      }
      return HistoryTargetKey(type: target.type, id: tid);
    }
    return HistoryTargetKey(type: target.type, id: rawId);
  }

  void _validateSurface(
    HistoryTargetType targetType,
    HistoryVisitSurface surface,
  ) {
    final matches = switch (targetType) {
      HistoryTargetType.thread =>
        surface == HistoryVisitSurface.threadNative ||
            surface == HistoryVisitSurface.threadWebView,
      HistoryTargetType.comic => surface == HistoryVisitSurface.comicDetail,
      HistoryTargetType.novel => surface == HistoryVisitSurface.novelDetail,
    };
    if (!matches) {
      throw FormatException(
        'History surface ${surface.name} does not match ${targetType.name}',
      );
    }
  }

  String _normalizeTitle(String? raw, HistoryTargetKey target) {
    final normalized = _normalizeOptionalText(raw);
    final fallback = switch (target.type) {
      HistoryTargetType.thread => '帖子 ${target.id}',
      HistoryTargetType.comic => '未命名漫画',
      HistoryTargetType.novel => '未命名小说',
    };
    final resolved = normalized ?? fallback;
    if (maxTitleCharacters <= 0) {
      return resolved;
    }
    return resolved.characters.take(maxTitleCharacters).toString();
  }

  String _normalizeContextLabel(
    String? raw, {
    required HistoryTargetKey target,
    required String? forumName,
    required int? page,
  }) {
    final normalized = _normalizeOptionalText(raw);
    if (normalized != null) {
      return normalized;
    }
    return switch (target.type) {
      HistoryTargetType.thread =>
        forumName ?? (page != null && page > 1 ? '第 $page 页' : '帖子详情'),
      HistoryTargetType.comic => '漫画详情',
      HistoryTargetType.novel => '小说详情',
    };
  }

  HistoryThumbnailSnapshot? _normalizeThumbnail(
    HistoryThumbnailSnapshot? thumbnail,
  ) {
    if (thumbnail == null) {
      return null;
    }
    final localPath = _normalizeOptionalText(thumbnail.localPath);
    final remoteUrl = _normalizeRemoteUrl(thumbnail.remoteUrl);
    if (localPath == null && remoteUrl == null) {
      return null;
    }
    return HistoryThumbnailSnapshot(
      localPath: localPath,
      remoteUrl: remoteUrl,
      focusX: _normalizeFocus(thumbnail.focusX),
      focusY: _normalizeFocus(thumbnail.focusY),
    );
  }

  Uri? _normalizeCanonicalUri(
    Uri? uri,
    HistoryTargetKey target, {
    required String? sourceTid,
  }) {
    if (uri == null) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
      return null;
    }
    final routeTid = target.type == HistoryTargetType.thread
        ? target.id
        : sourceTid;
    if (routeTid != null) {
      return Uri(
        scheme: scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/forum.php',
        query: 'mod=viewthread&tid=$routeTid',
      );
    }
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      query: uri.hasQuery ? _sanitizeRawQuery(uri.query) : null,
    );
  }

  String? _sanitizeRawQuery(String rawQuery) {
    const sensitiveKeys = <String>{
      'access_token',
      'auth',
      'cookie',
      'formhash',
      'hash',
      'highlight',
      'passwd',
      'password',
      'sid',
      'token',
    };
    final retained = <String>[];
    for (final segment in rawQuery.split(RegExp(r'[&;]'))) {
      if (segment.isEmpty) {
        continue;
      }
      final separator = segment.indexOf('=');
      final key = (separator < 0 ? segment : segment.substring(0, separator))
          .trim()
          .toLowerCase();
      if (key.isEmpty || sensitiveKeys.contains(key)) {
        continue;
      }
      retained.add(segment);
    }
    return retained.isEmpty ? null : retained.join('&');
  }

  String? _normalizeRemoteUrl(String? value) {
    final normalized = _normalizeOptionalText(value);
    if (normalized == null) {
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  double? _normalizeFocus(double? value) {
    if (value == null || !value.isFinite) {
      return null;
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  String? _normalizePositiveInteger(String? value) {
    final normalized = value?.trim();
    if (normalized == null || !RegExp(r'^\d+$').hasMatch(normalized)) {
      return null;
    }
    final number = BigInt.tryParse(normalized);
    if (number == null || number <= BigInt.zero) {
      return null;
    }
    return number.toString();
  }

  String? _normalizeOptionalText(String? value) {
    final normalized = value == null ? '' : _collapseWhitespace(value);
    return normalized.isEmpty ? null : normalized;
  }

  String _collapseWhitespace(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}
