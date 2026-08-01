import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

final postEditTargetParserProvider = Provider<PostEditTargetParser>((ref) {
  return const PostEditTargetParser();
});

class PostEditTargetParser {
  const PostEditTargetParser({this.siteBaseUri});

  // The default is resolved lazily so this domain service remains easy to use
  // in fixture tests without requiring a network client.
  final Uri? siteBaseUri;

  PostEditTargetParseResult parse({
    required String rawUrl,
    required String currentTid,
    required String currentPid,
    String currentFid = '',
    int currentPage = 1,
    bool isFirstPost = false,
  }) {
    final raw = rawUrl.trim();
    if (raw.isEmpty) {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.emptyUrl,
      );
    }

    final uri = Uri.tryParse(raw.replaceAll('&amp;', '&'));
    if (uri == null) {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.invalidUrl,
      );
    }
    final siteUri = _siteUri;
    if (uri.scheme.toLowerCase() != siteUri.scheme.toLowerCase() ||
        uri.host.toLowerCase() != siteUri.host.toLowerCase() ||
        uri.port != siteUri.port) {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.externalSite,
      );
    }
    if (uri.userInfo.isNotEmpty) {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.userInfoNotAllowed,
      );
    }
    if (uri.path.toLowerCase() != '/forum.php') {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.invalidPath,
      );
    }

    Map<String, List<String>> query;
    try {
      query = uri.queryParametersAll;
    } on FormatException {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.invalidUrl,
      );
    }

    final mod = _single(query, 'mod')?.toLowerCase();
    final action = _single(query, 'action')?.toLowerCase();
    if (mod != 'post') {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.invalidModule,
      );
    }
    if (action != 'edit') {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.invalidAction,
      );
    }

    final fid = _single(query, 'fid');
    final tid = _single(query, 'tid');
    final pid = _single(query, 'pid');
    final pageText = _single(query, 'page');
    if (!_positiveInteger(fid) ||
        !_positiveInteger(tid) ||
        !_positiveInteger(pid)) {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.invalidIdentifier,
      );
    }
    if (pageText != null && !_positiveInteger(pageText)) {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.invalidIdentifier,
      );
    }
    if (tid != currentTid.trim() || pid != currentPid.trim()) {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.targetMismatch,
      );
    }
    final expectedFid = currentFid.trim();
    if (expectedFid.isNotEmpty && fid != expectedFid) {
      return const PostEditTargetParseResult.failure(
        PostEditTargetParseFailure.targetMismatch,
      );
    }

    final page = int.tryParse(pageText ?? '') ?? currentPage;
    return PostEditTargetParseResult.success(
      PostEditTarget(
        editUri: uri,
        fid: fid!,
        tid: tid!,
        pid: pid!,
        page: page > 0 ? page : 1,
        isFirstPost: isFirstPost,
      ),
    );
  }

  Uri get _siteUri {
    final configured = siteBaseUri;
    return configured != null && configured.hasScheme
        ? configured
        : Uri.parse(AppConfig.siteBaseUrl);
  }

  String? _single(Map<String, List<String>> query, String name) {
    final values = query[name];
    if (values == null || values.length != 1) {
      return null;
    }
    final value = values.single.trim();
    return value.isEmpty ? null : value;
  }

  bool _positiveInteger(String? value) {
    return value != null && RegExp(r'^[1-9]\d*$').hasMatch(value);
  }
}
