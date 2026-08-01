import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/thread/domain/models/post_edit_models.dart';
import 'package:y300/features/thread/domain/models/post_edit_submit_models.dart';

final class PostEditSubmitResponseParser {
  const PostEditSubmitResponseParser();

  PostEditSubmitResponse parse({
    required Uri responseUri,
    required String body,
    required PostEditTarget target,
  }) {
    if (_isLoginPage(body, responseUri)) {
      return const PostEditSubmitResponse(
        kind: PostEditSubmitResponseKind.authenticationFailure,
      );
    }
    if (_isTargetRedirect(responseUri, target)) {
      return PostEditSubmitResponse(
        kind: PostEditSubmitResponseKind.confirmedSuccess,
        redirectUri: responseUri,
      );
    }
    if (_isWrongTargetRedirect(responseUri, target)) {
      return const PostEditSubmitResponse(
        kind: PostEditSubmitResponseKind.ambiguous,
      );
    }

    final redirect = _targetRedirectInBody(body, target);
    if (redirect != null) {
      return PostEditSubmitResponse(
        kind: PostEditSubmitResponseKind.confirmedSuccess,
        redirectUri: redirect,
      );
    }
    if (_containsFormHashFailure(body)) {
      return const PostEditSubmitResponse(
        kind: PostEditSubmitResponseKind.formExpired,
      );
    }
    if (_containsPermissionFailure(body)) {
      return const PostEditSubmitResponse(
        kind: PostEditSubmitResponseKind.permissionFailure,
      );
    }

    final normalized = body.toLowerCase();
    final hasStableSuccessKey = _successKeys.any(normalized.contains);
    final containsTarget =
        normalized.contains(target.tid) && normalized.contains(target.pid);
    if (hasStableSuccessKey && containsTarget) {
      return const PostEditSubmitResponse(
        kind: PostEditSubmitResponseKind.confirmedSuccess,
      );
    }
    if (_looksLikeBusinessError(body)) {
      return const PostEditSubmitResponse(
        kind: PostEditSubmitResponseKind.businessFailure,
      );
    }
    return const PostEditSubmitResponse(
      kind: PostEditSubmitResponseKind.ambiguous,
    );
  }

  static const _successKeys = <String>{
    'post_edit_succeed',
    'edit_newthread_mod_succeed',
    'edit_reply_mod_succeed',
    'auditstatuson_succeed',
    'audit_edit_succeed',
  };

  bool _isLoginPage(String body, Uri uri) {
    final document = html_parser.parse(body);
    final title = document.querySelector('title')?.text.toLowerCase() ?? '';
    final text = document.body?.text.toLowerCase() ?? '';
    return uri.queryParameters['mod'] == 'logging' ||
        document.querySelector('form#loginform, .loginbox') != null ||
        title.contains('login') ||
        title.contains('登录') ||
        text.contains('请先登录');
  }

  bool _isTargetRedirect(Uri uri, PostEditTarget target) {
    if (!_isSameSiteForumUri(uri, target) ||
        uri.path.toLowerCase() != '/forum.php') {
      return false;
    }
    final query = uri.queryParameters;
    final fragment = uri.fragment.trim();
    final viewThread =
        query['mod'] == 'viewthread' &&
        query['tid'] == target.tid &&
        (fragment == 'pid${target.pid}' || query['pid'] == target.pid);
    final findPost =
        query['mod'] == 'redirect' &&
        query['goto'] == 'findpost' &&
        query['ptid'] == target.tid &&
        query['pid'] == target.pid;
    return viewThread || findPost;
  }

  bool _isWrongTargetRedirect(Uri uri, PostEditTarget target) {
    if (!_isSameSiteForumUri(uri, target) ||
        uri.path.toLowerCase() != '/forum.php') {
      return false;
    }
    final query = uri.queryParameters;
    final mod = query['mod']?.toLowerCase();
    if (mod == 'viewthread') {
      return query['tid'] != target.tid ||
          (query['pid'] != null && query['pid'] != target.pid);
    }
    if (mod == 'redirect' && query['goto'] == 'findpost') {
      return query['ptid'] != target.tid || query['pid'] != target.pid;
    }
    return false;
  }

  bool _isSameSiteForumUri(Uri uri, PostEditTarget target) {
    return uri.scheme.toLowerCase() == target.editUri.scheme.toLowerCase() &&
        uri.host.toLowerCase() == target.editUri.host.toLowerCase() &&
        uri.port == target.editUri.port;
  }

  Uri? _targetRedirectInBody(String body, PostEditTarget target) {
    final document = html_parser.parse(body);
    for (final anchor in document.querySelectorAll('a[href]')) {
      final uri = _resolveBodyUri(
        (anchor.attributes['href'] ?? '').replaceAll('&amp;', '&'),
        target,
      );
      if (uri != null && _isTargetRedirect(uri, target)) {
        return uri;
      }
    }
    final matches = RegExp(
      r'''forum\.php\?[^"'<>\s]+''',
      caseSensitive: false,
    ).allMatches(body);
    for (final match in matches) {
      final uri = _resolveBodyUri(
        match.group(0)!.replaceAll('&amp;', '&'),
        target,
      );
      if (uri != null && _isTargetRedirect(uri, target)) {
        return uri;
      }
    }
    return null;
  }

  Uri? _resolveBodyUri(String raw, PostEditTarget target) {
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null) {
      return null;
    }
    if (parsed.hasScheme || parsed.host.isNotEmpty) {
      return parsed;
    }
    return target.editUri.resolveUri(parsed);
  }

  bool _containsFormHashFailure(String body) {
    final normalized = body.toLowerCase();
    return normalized.contains('formhash_invalid') ||
        normalized.contains('formhash_expired') ||
        (normalized.contains('formhash') &&
            (normalized.contains('invalid') ||
                normalized.contains('expired') ||
                normalized.contains('过期')));
  }

  bool _containsPermissionFailure(String body) {
    final normalized = body.toLowerCase();
    return normalized.contains('nopermission') ||
        normalized.contains('no_permission') ||
        normalized.contains('postperm') ||
        normalized.contains('无权') ||
        normalized.contains('没有权限') ||
        normalized.contains('permission denied');
  }

  bool _looksLikeBusinessError(String body) {
    final document = html_parser.parse(body);
    return document.querySelector(
          'error, .error, #messagetext, .alert_error, [data-error]',
        ) !=
        null;
  }
}
