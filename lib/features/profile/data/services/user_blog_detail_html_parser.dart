import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';

final class UserBlogDetailHtmlParser {
  const UserBlogDetailHtmlParser();

  UserBlogDetailData parse({
    required String html,
    required UserBlogDetailQuery query,
    required String siteOrigin,
  }) {
    final document = html_parser.parse(html);
    final root = document.querySelector('.viewthread');
    final post = root?.querySelector('.plc');
    final message = post?.querySelector('.message');
    if (root == null || post == null || message == null) {
      throw const FormatException('User blog detail root is missing.');
    }
    final title = _cleanText(root.querySelector('.view_tit')?.text ?? '');
    final bodyHtml = message.innerHtml.trim();
    if (title.isEmpty || bodyHtml.isEmpty) {
      throw const FormatException('User blog detail content is missing.');
    }

    final authorAnchor = post.querySelector('.authi .mtit a[href*="uid="]');
    final ownerUserId = _userIdFromUrl(
      authorAnchor?.attributes['href'],
      siteOrigin: siteOrigin,
    );
    if (ownerUserId == null || ownerUserId != query.ownerUserId.trim()) {
      throw const FormatException('User blog owner identity mismatch.');
    }
    final observedBlogIds = <String>{
      for (final anchor in post.querySelectorAll('.threadlist_foot a[href]'))
        if (_blogIdFromUrl(anchor.attributes['href'], siteOrigin: siteOrigin)
            case final String value)
          value,
      if (root.querySelector('input[name="id"]')?.attributes['value']?.trim()
          case final String value when value.isNotEmpty)
        value,
    };
    if (observedBlogIds.length != 1 ||
        observedBlogIds.single != query.blogId.trim()) {
      throw const FormatException('User blog detail identity mismatch.');
    }

    final statLine = post.querySelector('.authi .mtime');
    final viewCount = _parseDisplayedCount(statLine, 'dm-eye');
    final commentCount = _parseDisplayedCount(statLine, 'dm-chat-s');
    final resolver = SiteUrlResolver(siteOrigin: siteOrigin);
    final comments = <UserBlogComment>[];
    final commentIds = <String>{};
    for (final row in root.querySelectorAll('li.doing_list_li')) {
      final comment = _parseComment(row, resolver, siteOrigin);
      if (!commentIds.add(comment.commentId)) {
        throw const FormatException('Duplicate user blog comment identity.');
      }
      comments.add(comment);
    }
    if (commentCount != null && commentCount < comments.length) {
      throw const FormatException('User blog comment count is inconsistent.');
    }
    if (commentCount != null &&
        commentCount > 0 &&
        root.querySelector('.doing_list_box') == null) {
      throw const FormatException('User blog comments root is missing.');
    }

    final commentForm = root.querySelector('form[id^="quickcommentform"]');
    if (commentForm != null) {
      final formBlogId = commentForm
          .querySelector('input[name="id"]')
          ?.attributes['value']
          ?.trim();
      final idType = commentForm
          .querySelector('input[name="idtype"]')
          ?.attributes['value']
          ?.trim();
      if (formBlogId != query.blogId.trim() || idType != 'blogid') {
        throw const FormatException('User blog comment form is invalid.');
      }
    }

    return UserBlogDetailData(
      blogId: observedBlogIds.single,
      ownerUserId: ownerUserId,
      title: title,
      bodyHtml: bodyHtml,
      authorName: _optionalText(authorAnchor?.text),
      avatarUrl: _resolve(
        resolver,
        post.querySelector('.avatar img')?.attributes['src'],
      ),
      publishedAtText: _parsePublishedAt(statLine),
      viewCount: viewCount,
      commentCount: commentCount,
      comments: List<UserBlogComment>.unmodifiable(comments),
      commentsOpen: commentForm == null ? null : true,
    );
  }

  UserBlogComment _parseComment(
    html_dom.Element row,
    SiteUrlResolver resolver,
    String siteOrigin,
  ) {
    final match = RegExp(r'^comment_(\d+)_li$').firstMatch(row.id.trim());
    final authorAnchor = row.querySelector('.muser h3 a');
    final authorName = _cleanText(authorAnchor?.text ?? '');
    final bodyHtml = row.querySelector('.do_comment')?.innerHtml.trim() ?? '';
    if (match == null || authorName.isEmpty || bodyHtml.isEmpty) {
      throw const FormatException('User blog comment is invalid.');
    }
    return UserBlogComment(
      commentId: match.group(1)!,
      authorName: authorName,
      bodyHtml: bodyHtml,
      authorUserId: _userIdFromUrl(
        authorAnchor?.attributes['href'],
        siteOrigin: siteOrigin,
      ),
      avatarUrl: _resolve(
        resolver,
        row.querySelector('.avatar img')?.attributes['src'],
      ),
      publishedAtText: _optionalText(row.querySelector('.mtime span')?.text),
    );
  }

  int? _parseDisplayedCount(html_dom.Element? statLine, String iconClass) {
    final icon = statLine?.querySelector('i.$iconClass');
    if (icon == null) {
      return null;
    }
    final value = _cleanText(icon.nextElementSibling?.text ?? '');
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw const FormatException('User blog statistic is invalid.');
    }
    return int.parse(value);
  }

  String? _parsePublishedAt(html_dom.Element? statLine) {
    if (statLine == null) {
      return null;
    }
    final metricNode = statLine.querySelector('span.y');
    return _optionalText(
      statLine.nodes
          .where((node) => node != metricNode)
          .map((node) => node.text)
          .join(' '),
    );
  }

  String? _blogIdFromUrl(String? raw, {required String siteOrigin}) {
    final uri = _sameOriginUri(raw, siteOrigin: siteOrigin);
    if (uri == null) {
      return null;
    }
    final type = uri.queryParameters['type'];
    final action = uri.queryParameters['action'];
    final isSpaceAction =
        uri.path.endsWith('home.php') &&
        uri.queryParameters['mod'] == 'spacecp' &&
        type == 'blog';
    final isInviteAction =
        uri.path.endsWith('misc.php') &&
        uri.queryParameters['mod'] == 'invite' &&
        action == 'blog';
    if (!isSpaceAction && !isInviteAction) {
      return null;
    }
    final value = uri.queryParameters['id']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _userIdFromUrl(String? raw, {required String siteOrigin}) {
    final uri = _sameOriginUri(raw, siteOrigin: siteOrigin);
    if (uri == null ||
        !uri.path.endsWith('home.php') ||
        uri.queryParameters['mod'] != 'space') {
      return null;
    }
    final value = uri.queryParameters['uid']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Uri? _sameOriginUri(String? raw, {required String siteOrigin}) {
    final resolved = SiteUrlResolver(
      siteOrigin: siteOrigin,
    ).resolve(raw?.replaceAll('&amp;', '&') ?? '');
    final uri = Uri.tryParse(resolved ?? '');
    final expected = Uri.tryParse(siteOrigin);
    if (uri == null ||
        expected == null ||
        !uri.hasScheme ||
        uri.origin != expected.origin) {
      return null;
    }
    return uri;
  }

  String? _resolve(SiteUrlResolver resolver, String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return resolver.resolve(raw);
  }

  String? _optionalText(String? value) {
    final normalized = _cleanText(value ?? '');
    return normalized.isEmpty ? null : normalized;
  }

  String _cleanText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
