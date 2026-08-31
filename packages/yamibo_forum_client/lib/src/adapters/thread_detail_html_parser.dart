import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import '../contracts/thread_detail_models.dart';
import '../url/forum_uri_resolver.dart';

/// Source-neutral thread detail html parser.
class ThreadDetailHtmlParser {
  /// Creates a parser restricted to same-site references under [siteOrigin].
  ThreadDetailHtmlParser({required Uri siteOrigin})
    : _urlResolver = ForumUriResolver(siteOrigin: siteOrigin);

  static final RegExp _positiveIntegerPattern = RegExp(r'^[1-9]\d*$');

  final ForumUriResolver _urlResolver;

  /// Parses the payload from validated source data.
  ThreadDetailData parse(
    String html, {
    required String fallbackTid,
    required int fallbackPage,
    String fallbackSubject = '',
  }) {
    final document = html_parser.parse(html);
    if (_looksLikeMobileThreadDetail(document)) {
      return _parseMobile(
        document,
        fallbackTid: fallbackTid,
        fallbackPage: fallbackPage,
        fallbackSubject: fallbackSubject,
      );
    }
    return _parseDesktop(
      document,
      fallbackTid: fallbackTid,
      fallbackPage: fallbackPage,
      fallbackSubject: fallbackSubject,
    );
  }

  bool _looksLikeMobileThreadDetail(html_dom.Document document) {
    return document.body?.id == 'forum' &&
        document.querySelector('.viewthread .plc[id^="pid"]') != null;
  }

  ThreadDetailData _parseMobile(
    html_dom.Document document, {
    required String fallbackTid,
    required int fallbackPage,
    required String fallbackSubject,
  }) {
    final threadHeader = _parseMobileThreadHeader(document);
    final posts = _parseMobilePosts(document, expectedTid: fallbackTid);
    final tid = _extractTid(document) ?? fallbackTid;
    final page = _parseCurrentPage(document, fallback: fallbackPage);
    final lastPage = _parseLastPage(document);
    final nextPageUrl = _resolve(
      document.querySelector('.pg a.nxt')?.attributes['href'],
    );
    final previousPageUrl = _resolve(
      document.querySelector('.pg a.prev')?.attributes['href'],
    );

    return ThreadDetailData(
      tid: tid,
      fid: _extractFid(document) ?? '',
      typeid: _extractTypeId(document) ?? '',
      typeName: threadHeader.typeName,
      forumName: threadHeader.forumName,
      forumUrl: threadHeader.forumUrl,
      subject: threadHeader.subject.isNotEmpty
          ? threadHeader.subject
          : fallbackSubject,
      author: posts.isEmpty ? '' : posts.first.author,
      replies: threadHeader.replies,
      views: threadHeader.views,
      currentPage: page,
      perPage: posts.isEmpty ? 20 : posts.length,
      posts: List<ThreadPost>.unmodifiable(posts),
      lastPage: lastPage,
      previousPageUrl: previousPageUrl,
      nextPageUrl: nextPageUrl,
      reverseOrderUrl: _parseReverseOrderUrl(document),
      onlyAuthorUrl: _parseOnlyAuthorUrl(document),
      favoriteUrl: _parseFavoriteUrl(document),
      shareUrl: _parseShareUrl(document),
      homeUrl:
          _resolve(
            document.querySelector('a[href*="index.php"]')?.attributes['href'],
          ) ??
          _resolve('/index.php'),
      desktopUrl:
          document.querySelector('link[rel="canonical"]')?.attributes['href'] ??
          _resolve('/forum.php?mod=viewthread&tid=$tid&page=$page'),
    );
  }

  ThreadDetailData _parseDesktop(
    html_dom.Document document, {
    required String fallbackTid,
    required int fallbackPage,
    required String fallbackSubject,
  }) {
    final threadHeader = _parseDesktopThreadHeader(document);
    final posts = _parseDesktopPosts(document, expectedTid: fallbackTid);
    final tid = _extractTid(document) ?? fallbackTid;
    final page = _parseCurrentPage(document, fallback: fallbackPage);
    final lastPage = _parseLastPage(document);
    final nextPageUrl = _resolve(
      document.querySelector('.pg a.nxt')?.attributes['href'],
    );
    final previousPageUrl = _resolve(
      document.querySelector('.pg a.prev')?.attributes['href'],
    );

    return ThreadDetailData(
      tid: tid,
      fid: _extractFid(document) ?? '',
      typeid: _extractTypeId(document) ?? '',
      typeName: threadHeader.typeName,
      forumName: threadHeader.forumName,
      forumUrl: threadHeader.forumUrl,
      subject: threadHeader.subject.isNotEmpty
          ? threadHeader.subject
          : fallbackSubject,
      author: posts.isEmpty ? '' : posts.first.author,
      replies: threadHeader.replies,
      views: threadHeader.views,
      currentPage: page,
      perPage: posts.isEmpty ? 20 : posts.length,
      posts: List<ThreadPost>.unmodifiable(posts),
      lastPage: lastPage,
      previousPageUrl: previousPageUrl,
      nextPageUrl: nextPageUrl,
      reverseOrderUrl: _parseReverseOrderUrl(document),
      onlyAuthorUrl: _parseOnlyAuthorUrl(document),
      favoriteUrl: _parseFavoriteUrl(document),
      shareUrl: _parseShareUrl(document),
      homeUrl: _resolve('/index.php'),
      desktopUrl: _resolve('/forum.php?mod=viewthread&tid=$tid&page=$page'),
    );
  }

  _ThreadHeader _parseMobileThreadHeader(html_dom.Document document) {
    final viewTitle = document.querySelector('.viewthread .view_tit');
    final typeNode = viewTitle?.querySelector('em');
    final typeName = _stripBrackets(_cleanText(typeNode?.text ?? ''));
    final subject = _cleanText(
      _cloneWithout(viewTitle, const <String>['em']).text,
    );
    final forumAnchor = document.querySelector(
      '.header h2 a[href*="forumdisplay"][href*="fid="]',
    );
    final firstMtime = document.querySelector(
      '.viewthread .plc .display.pione .authi .mtime',
    );
    final metrics =
        firstMtime
            ?.querySelectorAll('.y em')
            .map((node) => _parseFirstInt(_cleanText(node.text)))
            .where((value) => value > 0)
            .toList(growable: false) ??
        const <int>[];
    final repliesText = _cleanText(
      document.querySelector('.txtlist .mtit em')?.text ?? '',
    );
    final replies = metrics.length > 1
        ? metrics[1]
        : (int.tryParse(repliesText) ?? 0);
    return _ThreadHeader(
      subject: subject,
      typeName: typeName.isEmpty ? null : typeName,
      forumName: _cleanText(forumAnchor?.text ?? '').isEmpty
          ? null
          : _cleanText(forumAnchor?.text ?? ''),
      forumUrl: _resolve(forumAnchor?.attributes['href']),
      views: metrics.isEmpty ? 0 : metrics.first,
      replies: replies,
    );
  }

  _ThreadHeader _parseDesktopThreadHeader(html_dom.Document document) {
    final subject = _cleanText(
      document.querySelector('#thread_subject')?.text ?? '',
    );
    final typeAnchor = document.querySelector('.vwthd h1.ts a[href*="typeid"]');
    final typeName = _stripBrackets(_cleanText(typeAnchor?.text ?? ''));
    final forumAnchor =
        _parseBreadcrumbForumAnchor(document) ??
        document.querySelector('a[href*="forumdisplay"][href*="fid="]') ??
        document.querySelector('a[rel="curforum"][fid]');
    final statText = _cleanText(
      document.querySelector('#postlist .hm')?.text ?? '',
    );
    return _ThreadHeader(
      subject: subject,
      typeName: typeName.isEmpty ? null : typeName,
      forumName: _cleanText(forumAnchor?.text ?? '').isEmpty
          ? null
          : _cleanText(forumAnchor?.text ?? ''),
      forumUrl: _resolve(forumAnchor?.attributes['href']),
      views: _parseLabeledInt(statText, '查看'),
      replies: _parseLabeledInt(statText, '回复'),
    );
  }

  html_dom.Element? _parseBreadcrumbForumAnchor(html_dom.Document document) {
    final anchors = document.querySelectorAll(
      '#pt a[href*="forum-"], #pt a[href*="forumdisplay"][href*="fid="]',
    );
    for (final anchor in anchors.reversed) {
      final name = _cleanText(anchor.text);
      if (name.isNotEmpty) {
        return anchor;
      }
    }
    return null;
  }

  List<ThreadPost> _parseMobilePosts(
    html_dom.Document document, {
    required String expectedTid,
  }) {
    final output = <ThreadPost>[];
    for (final container in document.querySelectorAll(
      '.viewthread .plc[id^="pid"]',
    )) {
      final post = _parseMobilePost(
        container,
        output.length,
        document,
        expectedTid: expectedTid,
      );
      if (post != null) {
        output.add(post);
      }
    }
    return output;
  }

  ThreadPost? _parseMobilePost(
    html_dom.Element container,
    int index,
    html_dom.Document document, {
    required String expectedTid,
  }) {
    final pid = _extractPid(container);
    if (pid.isEmpty) {
      return null;
    }
    final authorAnchor = container.querySelector(
      '.authi .mtit .z a[href*="uid="]',
    );
    final number = _parseFirstInt(
      _cleanText(container.querySelector('.authi .mtit .y')?.text ?? ''),
    );
    final messageNode = container.querySelector('.message');
    final footer = _findMobilePostActionFooter(container);
    final isFirst =
        container.querySelector('.display.pione') != null || number == 1;

    return ThreadPost(
      pid: pid,
      author: _cleanText(authorAnchor?.text ?? ''),
      authorId: _extractUid(_resolve(authorAnchor?.attributes['href'])) ?? '',
      message: _cleanMobilePostMessageHtml(
        messageNode,
        postContainer: container,
      ),
      number: number > 0 ? number : index + 1,
      isFirst: isFirst,
      dateline: _parseMobileDateline(container),
      avatarUrl: _resolve(
        container.querySelector('.avatar img')?.attributes['src'],
      ),
      replyUrl: _parseMobileReplyUrl(
        container: container,
        document: document,
        pid: pid,
        isFirst: isFirst,
      ),
      editUrl: _parseEditUrl(
        container,
        expectedTid: expectedTid,
        expectedPid: pid,
      ),
      rateUrl: _resolve(
        footer
            ?.querySelector('a[href*="mod=misc"][href*="action=rate"]')
            ?.attributes['href'],
      ),
      commentUrl: _resolve(
        footer
            ?.querySelector('a[href*="mod=misc"][href*="action=comment"]')
            ?.attributes['href'],
      ),
      rateSummary: _parseRateSummaryFromSummary(
        _parseMobileRatingSummary(container, pid),
      ),
      ratingSummary: _parseMobileRatingSummary(container, pid),
      poll: isFirst ? _parseMobilePoll(container) : null,
      comments: _parseMobilePostComments(container, pid),
    );
  }

  html_dom.Element? _findMobilePostActionFooter(html_dom.Element container) {
    final inlineFooter = container.querySelector('.threadlist_foot');
    if (inlineFooter != null) {
      return inlineFooter;
    }
    var sibling = container.nextElementSibling;
    while (sibling != null) {
      if (sibling.classes.contains('threadlist_foot')) {
        return sibling;
      }
      if (sibling.classes.contains('plc') || sibling.id.startsWith('pid')) {
        break;
      }
      sibling = sibling.nextElementSibling;
    }
    return null;
  }

  String? _parseMobileReplyUrl({
    required html_dom.Element container,
    required html_dom.Document document,
    required String pid,
    required bool isFirst,
  }) {
    final direct = _resolve(
      container.querySelector('#replybtn_$pid a.button')?.attributes['href'],
    );
    if (direct != null) {
      return direct;
    }
    if (!isFirst) {
      return null;
    }
    return _resolve(
      document
          .querySelector(
            '.foot_reply a[href*="action=reply"][href*="reppost="]',
          )
          ?.attributes['href'],
    );
  }

  String? _parseEditUrl(
    html_dom.Element container, {
    required String expectedTid,
    required String expectedPid,
  }) {
    // Do not depend on Discuz's query-parameter order or the exact markup
    // around the timestamp. The container boundary is the important part:
    // links from another floor must never become this post's edit target.
    final candidates = container.querySelectorAll('a[href]');
    final siteOrigin = _urlResolver.siteOrigin;
    if (!siteOrigin.hasScheme || siteOrigin.host.isEmpty) {
      return null;
    }
    final forumPath = siteOrigin.resolve('forum.php').path.toLowerCase();
    for (final anchor in candidates) {
      final resolved = _resolve(anchor.attributes['href']);
      final uri = resolved == null ? null : Uri.tryParse(resolved);
      if (uri == null ||
          !_hasSameOrigin(uri, siteOrigin) ||
          uri.userInfo.isNotEmpty ||
          uri.path.toLowerCase() != forumPath) {
        continue;
      }
      final query = _tryQueryParametersAll(uri);
      if (query == null) {
        continue;
      }
      final mod = _singleQueryValue(query, 'mod')?.toLowerCase();
      final action = _singleQueryValue(query, 'action')?.toLowerCase();
      final fid = _singleQueryValue(query, 'fid');
      final tid = _singleQueryValue(query, 'tid');
      final pid = _singleQueryValue(query, 'pid');
      if (mod != 'post' ||
          action != 'edit' ||
          !_isPositiveInteger(fid) ||
          !_isPositiveInteger(tid) ||
          !_isPositiveInteger(pid) ||
          tid != expectedTid.trim() ||
          pid != expectedPid.trim()) {
        continue;
      }
      return resolved;
    }
    return null;
  }

  bool _hasSameOrigin(Uri candidate, Uri siteOrigin) {
    return candidate.scheme.toLowerCase() == siteOrigin.scheme.toLowerCase() &&
        candidate.host.toLowerCase() == siteOrigin.host.toLowerCase() &&
        candidate.port == siteOrigin.port;
  }

  Map<String, List<String>>? _tryQueryParametersAll(Uri uri) {
    try {
      return uri.queryParametersAll;
    } on FormatException {
      return null;
    }
  }

  String? _singleQueryValue(Map<String, List<String>> query, String name) {
    final values = query[name];
    if (values == null || values.length != 1) {
      return null;
    }
    final value = values.single.trim();
    return value.isEmpty ? null : value;
  }

  bool _isPositiveInteger(String? value) {
    return value != null && _positiveIntegerPattern.hasMatch(value);
  }

  String _cleanMobilePostMessageHtml(
    html_dom.Element? messageNode, {
    required html_dom.Element postContainer,
  }) {
    return _cleanPostMessageHtml(
      _cloneWithoutMobilePoll(messageNode),
      postContainer: postContainer,
    );
  }

  html_dom.Element? _cloneWithoutMobilePoll(html_dom.Element? messageNode) {
    if (messageNode == null) {
      return null;
    }
    final clone = messageNode.clone(true);
    clone.querySelectorAll('.poll').forEach((node) => node.remove());
    return clone;
  }

  String _parseMobileDateline(html_dom.Element container) {
    final mtimeNode = container.querySelector('.authi .mtime');
    if (mtimeNode == null) {
      return '';
    }
    final clone = mtimeNode.clone(true);
    clone.querySelectorAll('.y').forEach((node) => node.remove());
    clone.querySelectorAll('.mgl').forEach((node) => node.remove());
    return _cleanText(clone.text).replaceFirst(RegExp(r'^发表于\s*'), '').trim();
  }

  ThreadPostRatingSummary? _parseMobileRatingSummary(
    html_dom.Element container,
    String pid,
  ) {
    final rateLog = container.querySelector('#ratelog_$pid');
    if (rateLog == null) {
      return null;
    }
    final allAnchors = rateLog.querySelectorAll(
      'a[href*="action=viewratings"][href*="pid="]',
    );
    final participantAnchor = allAnchors.isEmpty ? null : allAnchors.first;
    final viewAllAnchor = allAnchors.isEmpty ? null : allAnchors.last;
    final participantText = _cleanText(participantAnchor?.text ?? '');
    final rows = rateLog.querySelectorAll('li.flex-box.mli.p0');
    final ratings = <ThreadPostRating>[];
    var scoreText = '';
    for (final row in rows) {
      final text = _cleanText(row.text);
      if (text.isEmpty) {
        continue;
      }
      if (text.contains('参与人数') && text.contains('积分')) {
        final cells = row.querySelectorAll('div');
        if (cells.length > 1) {
          scoreText = _cleanText(cells[1].text);
        }
        continue;
      }
      if (_cleanText(viewAllAnchor?.text ?? '').isNotEmpty &&
          text == _cleanText(viewAllAnchor!.text)) {
        continue;
      }
      final userAnchor = _firstTextAnchor(row);
      if (userAnchor == null) {
        continue;
      }
      final cells = row.querySelectorAll('div');
      final score = cells.length > 1 ? _cleanText(cells[1].text) : '';
      final reason = cells.length > 2 ? _cleanText(cells[2].text) : '';
      ratings.add(
        ThreadPostRating(
          userName: _cleanText(userAnchor.text),
          userId: _extractUid(_resolve(userAnchor.attributes['href'])),
          score: score,
          reason: reason,
        ),
      );
    }
    if (participantText.isEmpty && scoreText.isEmpty && ratings.isEmpty) {
      return null;
    }
    return ThreadPostRatingSummary(
      participantText: participantText,
      scoreText: scoreText,
      viewAllUrl: _resolve(viewAllAnchor?.attributes['href']),
      ratings: List<ThreadPostRating>.unmodifiable(ratings),
    );
  }

  List<ThreadPostCommentEntry> _parseMobilePostComments(
    html_dom.Element container,
    String pid,
  ) {
    final commentRoot = container.querySelector('#comment_$pid');
    if (commentRoot == null) {
      return const <ThreadPostCommentEntry>[];
    }
    final output = <ThreadPostCommentEntry>[];
    for (final item in commentRoot.querySelectorAll(
      'div[id^="commentdetail_"]',
    )) {
      final authorAnchor = item.querySelector('.authi .mtit .z a[href]');
      final author = _cleanText(authorAnchor?.text ?? '');
      final dateline = _cleanText(
        item.querySelector('.authi .mtime')?.text ?? '',
      ).replaceFirst(RegExp(r'^发表于\s*'), '').trim();
      final message = _cleanPlainTextHtml(item.querySelector('.authi .mtxt'));
      if (author.isEmpty && dateline.isEmpty && message.isEmpty) {
        continue;
      }
      final authorUrl = _resolve(authorAnchor?.attributes['href']);
      output.add(
        ThreadPostCommentEntry(
          author: author,
          authorId: _extractUid(authorUrl),
          authorUrl: authorUrl,
          avatarUrl: _resolve(
            item.querySelector('.avatar img')?.attributes['src'],
          ),
          message: message,
          dateline: dateline,
        ),
      );
    }
    return List<ThreadPostCommentEntry>.unmodifiable(output);
  }

  ThreadPoll? _parseMobilePoll(html_dom.Element postContainer) {
    final pollRoot = postContainer.querySelector('.message .poll');
    if (pollRoot == null) {
      return null;
    }
    final summaryLines = pollRoot
        .querySelectorAll('.poll_txt')
        .map((node) => _cleanText(node.text))
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final summary = summaryLines.firstWhere(
      (text) => !text.contains('距结束还有'),
      orElse: () => '',
    );
    final deadlineText = summaryLines.firstWhere(
      (text) => text.contains('距结束还有'),
      orElse: () => '',
    );
    final options = _parseMobilePollOptions(pollRoot);
    final statusText = _parseMobilePollStatusText(pollRoot);
    final hasVoteInputs = _hasValidPollVoteInputs(pollRoot, options);
    if (summary.isEmpty && options.isEmpty) {
      return null;
    }
    final maxMatch = RegExp(r'最多可选\s*(\d+)\s*项').firstMatch(summary);
    return ThreadPoll(
      isMultipleChoice:
          pollRoot.querySelector('input[type="checkbox"]') != null ||
          summary.contains('多选'),
      canVote: hasVoteInputs && !_isAlreadyVotedStatus(statusText),
      maxChoices: int.tryParse(maxMatch?.group(1) ?? ''),
      summary: summary,
      deadlineText: deadlineText.isEmpty ? null : deadlineText,
      statusText: statusText.isEmpty ? null : statusText,
      options: List<ThreadPollOption>.unmodifiable(options),
    );
  }

  List<ThreadPollOption> _parseMobilePollOptions(html_dom.Element pollRoot) {
    final output = <ThreadPollOption>[];
    for (final item in pollRoot.querySelectorAll('.poll_box > p')) {
      final labelNode = item.querySelector('label');
      final label = _cleanText(labelNode?.text ?? '');
      if (label.isEmpty) {
        continue;
      }
      final input = item.querySelector('input[name="pollanswers[]"]');
      final statNode = item.querySelector('em');
      final statText = _cleanText(statNode?.text ?? '');
      final percent = _parseMobilePollPercent(statText);
      final voteCount = _parseMobilePollVoteCount(statText);
      output.add(
        ThreadPollOption(
          id: _parsePollOptionId(
            input: input,
            label: labelNode,
            fallback: output.length + 1,
          ),
          label: _stripPollNumber(label),
          voteCount: voteCount,
          percent: percent,
          colorHex: _parseInlineColor(statNode?.attributes['style']),
        ),
      );
    }
    return output;
  }

  String _parseMobilePollStatusText(html_dom.Element pollRoot) {
    final status = pollRoot.querySelector('.poll_box .xi1');
    return _cleanText(status?.text ?? '');
  }

  int? _parseMobilePollVoteCount(String text) {
    return int.tryParse(
      RegExp(r'\((\d+)\s*票?\)').firstMatch(text)?.group(1) ?? '',
    );
  }

  double? _parseMobilePollPercent(String text) {
    return double.tryParse(
      RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(text)?.group(1) ?? '',
    );
  }

  String? _parseInlineColor(String? style) {
    final value = style?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    return RegExp(
      r'color\s*:\s*(#[0-9a-fA-F]{3,8}|[a-zA-Z]+)',
    ).firstMatch(value)?.group(1);
  }

  List<ThreadPost> _parseDesktopPosts(
    html_dom.Document document, {
    required String expectedTid,
  }) {
    final output = <ThreadPost>[];
    for (final container in document.querySelectorAll(
      '#postlist > div[id^="post_"]',
    )) {
      final post = _parseDesktopPost(
        container,
        output.length,
        expectedTid: expectedTid,
      );
      if (post != null) {
        output.add(post);
      }
    }
    return output;
  }

  ThreadPost? _parseDesktopPost(
    html_dom.Element container,
    int index, {
    required String expectedTid,
  }) {
    final pid = _extractPid(container);
    if (pid.isEmpty) {
      return null;
    }

    final messageNode = container.querySelector(
      '#postmessage_$pid, td.t_f[id^="postmessage_"]',
    );
    final authorAnchor =
        container.querySelector('.pls .pi .authi a.xw1[href*="space-uid"]') ??
        container.querySelector('.authi a[href*="space-uid"]');
    final postNumberText = _cleanText(
      container.querySelector('#postnum$pid em')?.text ?? '',
    );
    final number = int.tryParse(postNumberText) ?? index + 1;
    final ratingSummary = _parseDesktopRatingSummary(container, pid);

    return ThreadPost(
      pid: pid,
      author: _cleanText(authorAnchor?.text ?? ''),
      authorId: _extractUid(_resolve(authorAnchor?.attributes['href'])) ?? '',
      message: _cleanPostMessageHtml(messageNode, postContainer: container),
      number: number,
      isFirst: number == 1,
      dateline: _parseDesktopDateline(container, pid),
      avatarUrl: _resolve(
        container.querySelector('.avatar img.user_avatar')?.attributes['src'] ??
            container.querySelector('.avatar img')?.attributes['src'],
      ),
      replyUrl: _resolve(
        container
            .querySelector(
              'a[href*="mod=post"][href*="action=reply"][href*="repquote"], a[href*="mod=post"][href*="action=reply"][href*="reppost"]',
            )
            ?.attributes['href'],
      ),
      editUrl: _parseEditUrl(
        container,
        expectedTid: expectedTid,
        expectedPid: pid,
      ),
      rateUrl: _parseActionUrl(container, 'rate'),
      commentUrl: _resolve(
        container
            .querySelector('a[href*="mod=misc"][href*="action=comment"]')
            ?.attributes['href'],
      ),
      rateSummary: _parseRateSummaryFromSummary(ratingSummary),
      ratingSummary: ratingSummary,
      poll: number == 1 ? _parseDesktopPoll(container) : null,
      tagLinks: _parseDesktopTagLinks(container),
      comments: _parseDesktopPostComments(container, pid),
    );
  }

  List<ThreadPostCommentEntry> _parseDesktopPostComments(
    html_dom.Element container,
    String pid,
  ) {
    final commentRoot =
        container.querySelector('#comment_$pid.cm') ??
        container.querySelector('div[id="comment_$pid"]') ??
        container.querySelector('div[id^="comment_"].cm');
    if (commentRoot == null) {
      return const <ThreadPostCommentEntry>[];
    }

    final output = <ThreadPostCommentEntry>[];
    for (final item in commentRoot.querySelectorAll('.pstl')) {
      final authorAnchor =
          item.querySelector('.psta a.xi2[href]') ??
          _firstTextAnchor(item.querySelector('.psta') ?? item);
      final messageNode = item.querySelector('.psti');
      final author = _cleanText(authorAnchor?.text ?? '');
      final message = _parseDesktopPostCommentMessage(messageNode);
      final dateline = _parseDesktopPostCommentDateline(messageNode);
      if (author.isEmpty && message.isEmpty && dateline.isEmpty) {
        continue;
      }
      final authorUrl = _resolve(authorAnchor?.attributes['href']);
      output.add(
        ThreadPostCommentEntry(
          author: author,
          authorId: _extractUid(authorUrl),
          authorUrl: authorUrl,
          avatarUrl: _resolve(
            item.querySelector('.psta img.user_avatar')?.attributes['src'] ??
                item.querySelector('.psta img')?.attributes['src'],
          ),
          message: message,
          dateline: dateline,
        ),
      );
    }
    return List<ThreadPostCommentEntry>.unmodifiable(output);
  }

  String _parseDesktopPostCommentMessage(html_dom.Element? messageNode) {
    return _cleanPlainTextHtml(
      messageNode,
      selectorsToRemove: const <String>['.xg1', 'script', 'style'],
    );
  }

  String _parseDesktopPostCommentDateline(html_dom.Element? messageNode) {
    final text = _cleanText(messageNode?.querySelector('.xg1')?.text ?? '');
    return text.replaceFirst(RegExp(r'^发表于\s*'), '').trim();
  }

  List<ThreadPostTagLink> _parseDesktopTagLinks(html_dom.Element container) {
    final output = <ThreadPostTagLink>[];
    final seenUrls = <String>{};
    for (final anchor in container.querySelectorAll(
      '.ptg a[href*="misc.php"][href*="mod=tag"][href*="id="]',
    )) {
      final label = _cleanText(anchor.text);
      final url = _resolve(anchor.attributes['href']);
      if (label.isEmpty || url == null || !seenUrls.add(url)) {
        continue;
      }
      output.add(
        ThreadPostTagLink(
          label: label,
          url: url,
          tagId: Uri.tryParse(url)?.queryParameters['id']?.trim(),
        ),
      );
    }
    return List<ThreadPostTagLink>.unmodifiable(output);
  }

  ThreadPoll? _parseDesktopPoll(html_dom.Element postContainer) {
    final pollRoot = postContainer.querySelector('#poll');
    if (pollRoot == null) {
      return null;
    }
    final summary = _cleanText(pollRoot.querySelector('.pinf')?.text ?? '');
    final deadlineText = _cleanText(
      pollRoot.querySelector('.ptmr')?.text ?? '',
    );
    final options = _parseDesktopPollOptions(pollRoot);
    if (summary.isEmpty && options.isEmpty) {
      return null;
    }
    final statusText = _parseDesktopPollStatusText(pollRoot);
    final hasVoteInputs = _hasValidPollVoteInputs(pollRoot, options);
    final canVote = hasVoteInputs && !_isAlreadyVotedStatus(statusText);
    final maxMatch = RegExp(r'最多可选\s*(\d+)\s*项').firstMatch(summary);
    return ThreadPoll(
      isMultipleChoice:
          pollRoot.querySelector('input[type="checkbox"]') != null ||
          summary.contains('多选'),
      canVote: canVote,
      maxChoices: int.tryParse(maxMatch?.group(1) ?? ''),
      summary: summary,
      deadlineText: deadlineText.isEmpty ? null : deadlineText,
      statusText: statusText.isEmpty ? null : statusText,
      options: List<ThreadPollOption>.unmodifiable(options),
    );
  }

  List<ThreadPollOption> _parseDesktopPollOptions(html_dom.Element pollRoot) {
    final output = <ThreadPollOption>[];
    final rows = pollRoot.querySelectorAll('table[summary="poll panel"] tr');
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final input = row.querySelector('input[name="pollanswers[]"]');
      final label = _cleanText(row.querySelector('label')?.text ?? '');
      if (label.isEmpty) {
        continue;
      }
      final resultRow = index + 1 < rows.length ? rows[index + 1] : null;
      final labelNode = row.querySelector('label');
      final optionId = _parsePollOptionId(
        input: input,
        label: labelNode,
        fallback: output.length + 1,
      );
      output.add(
        ThreadPollOption(
          id: optionId,
          label: _stripPollNumber(label),
          voteCount: _parseVoteCount(resultRow),
          percent: _parsePollPercent(resultRow),
          colorHex: _parsePollColor(resultRow),
        ),
      );
    }
    return output;
  }

  bool _hasValidPollVoteInputs(
    html_dom.Element pollRoot,
    List<ThreadPollOption> options,
  ) {
    final inputs = pollRoot.querySelectorAll('input[name="pollanswers[]"]');
    if (inputs.isEmpty || inputs.length != options.length) {
      return false;
    }
    final seen = <String>{};
    return options.every(
      (option) =>
          RegExp(r'^[1-9]\d*$').hasMatch(option.id) && seen.add(option.id),
    );
  }

  String _parsePollOptionId({
    required html_dom.Element? input,
    required html_dom.Element? label,
    required int fallback,
  }) {
    final inputValue =
        input?.attributes['value']?.trim() ?? input?.attributes['id']?.trim();
    if (inputValue != null && inputValue.isNotEmpty) {
      return inputValue;
    }
    final labelFor = label?.attributes['for']?.trim() ?? '';
    final optionMatch = RegExp(r'option_(\d+)').firstMatch(labelFor);
    final optionId = optionMatch?.group(1);
    if (optionId != null && optionId.isNotEmpty) {
      return optionId;
    }
    return fallback.toString();
  }

  String _parseDesktopPollStatusText(html_dom.Element pollRoot) {
    final rows = pollRoot.querySelectorAll('table[summary="poll panel"] tr');
    for (final row in rows.reversed) {
      if (row.querySelector('.pbr') != null ||
          row.querySelector('label') != null) {
        continue;
      }
      final text = _cleanText(row.text);
      if (_isAlreadyVotedStatus(text) || text.contains('谢谢您的参与')) {
        return text;
      }
    }
    return '';
  }

  bool _isAlreadyVotedStatus(String? text) {
    final value = text?.trim() ?? '';
    return value.contains('已经投过票') || value.contains('谢谢您的参与');
  }

  int? _parseVoteCount(html_dom.Element? row) {
    if (row == null || row.querySelector('.pbr') == null) {
      return null;
    }
    final text = _cleanText(row.text);
    final match = RegExp(r'\((\d+)\)').firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  double? _parsePollPercent(html_dom.Element? row) {
    if (row == null || row.querySelector('.pbr') == null) {
      return null;
    }
    final text = _cleanText(row.text);
    final textMatch = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(text);
    final textValue = double.tryParse(textMatch?.group(1) ?? '');
    if (textValue != null) {
      return textValue;
    }
    final style = row.querySelector('.pbr')?.attributes['style'] ?? '';
    final styleMatch = RegExp(
      r'width\s*:\s*(\d+(?:\.\d+)?)%',
    ).firstMatch(style);
    return double.tryParse(styleMatch?.group(1) ?? '');
  }

  String? _parsePollColor(html_dom.Element? row) {
    final style = row?.querySelector('.pbr')?.attributes['style'] ?? '';
    final match = RegExp(
      r'background(?:-color)?\s*:\s*(#[0-9a-fA-F]{3,8}|[a-zA-Z]+)',
    ).firstMatch(style);
    return match?.group(1);
  }

  String _cleanPostMessageHtml(
    html_dom.Element? messageNode, {
    html_dom.Element? postContainer,
  }) {
    final parts = <String>[
      _cleanPostMessageBodyHtml(messageNode),
      ..._cleanPostAttachmentImageHtml(
        postContainer: postContainer,
        messageNode: messageNode,
      ),
    ].where((part) => part.trim().isNotEmpty);
    return parts.join('\n').trim();
  }

  String _cleanPostMessageBodyHtml(html_dom.Element? messageNode) {
    final clone = _cloneAndSanitizeThreadHtml(
      messageNode,
      selectorsToRemove: const <String>['script', 'style', '.aimg_tip'],
      normalizeImageSources: true,
    );
    if (clone == null) {
      return '';
    }
    return clone.innerHtml.trim();
  }

  String _cleanPlainTextHtml(
    html_dom.Element? source, {
    List<String> selectorsToRemove = const <String>[],
  }) {
    final clone = _cloneAndSanitizeThreadHtml(
      source,
      selectorsToRemove: selectorsToRemove,
    );
    if (clone == null) {
      return '';
    }
    return _cleanText(clone.text);
  }

  html_dom.Element? _cloneAndSanitizeThreadHtml(
    html_dom.Element? source, {
    List<String> selectorsToRemove = const <String>[],
    bool normalizeImageSources = false,
  }) {
    if (source == null) {
      return null;
    }
    final clone = source.clone(true);
    if (selectorsToRemove.isNotEmpty) {
      clone
          .querySelectorAll(selectorsToRemove.join(', '))
          .forEach((node) => node.remove());
    }
    _removeObfuscatedThreadNodes(clone);
    if (normalizeImageSources) {
      _normalizeThreadImageSources(clone);
    }
    return clone;
  }

  void _normalizeThreadImageSources(html_dom.Element root) {
    for (final image in root.querySelectorAll('img')) {
      final realSource = _firstPresentAttribute(image, const <String>[
        'zoomfile',
        'file',
        'data-original',
        'data-src',
        'src',
      ]);
      if (realSource != null) {
        image.attributes['src'] = realSource;
      }
    }
  }

  void _removeObfuscatedThreadNodes(html_dom.Element root) {
    // Discuz anti-scraping may inject hidden jammer nodes into otherwise valid
    // post/comment HTML; remove them before downstream parsing and rendering.
    root.querySelectorAll('font.jammer, .jammer').forEach((node) {
      node.remove();
    });
    for (final element in root.querySelectorAll('[style]')) {
      final style = element.attributes['style']?.trim() ?? '';
      if (style.isEmpty) {
        continue;
      }
      for (final declaration in style.split(';')) {
        final separatorIndex = declaration.indexOf(':');
        if (separatorIndex <= 0) {
          continue;
        }
        final key = declaration
            .substring(0, separatorIndex)
            .trim()
            .toLowerCase();
        final value = declaration
            .substring(separatorIndex + 1)
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '');
        if (key == 'display' && value.startsWith('none')) {
          element.remove();
          break;
        }
      }
    }
  }

  List<String> _cleanPostAttachmentImageHtml({
    required html_dom.Element? postContainer,
    required html_dom.Element? messageNode,
  }) {
    if (postContainer == null) {
      return const <String>[];
    }
    final output = <String>[];
    final seenSources = _collectMessageImageSourceKeys(messageNode);
    for (final image in postContainer.querySelectorAll(
      'img[zoomfile], img[file], img[id^="aimg_"]',
    )) {
      if (!_looksLikeDiscuzAttachmentImage(image)) {
        continue;
      }
      final realSource = _firstPresentAttribute(image, const <String>[
        'zoomfile',
        'file',
        'data-original',
        'data-src',
        'src',
      ]);
      final sourceKey = _imageSourceKey(realSource);
      if (realSource == null ||
          sourceKey == null ||
          !seenSources.add(sourceKey)) {
        continue;
      }
      output.add(_cleanAttachmentImageTag(image, realSource));
    }
    return output;
  }

  Set<String> _collectMessageImageSourceKeys(html_dom.Element? messageNode) {
    if (messageNode == null) {
      return <String>{};
    }
    final sources = <String>{};
    for (final image in messageNode.querySelectorAll('img')) {
      final source = _firstPresentAttribute(image, const <String>[
        'zoomfile',
        'file',
        'data-original',
        'data-src',
        'src',
      ]);
      final sourceKey = _imageSourceKey(source);
      if (sourceKey != null) {
        sources.add(sourceKey);
      }
    }
    return sources;
  }

  String? _imageSourceKey(String? source) {
    final resolved = _resolve(source);
    if (resolved == null || resolved.isEmpty) {
      return null;
    }
    return Uri.tryParse(resolved)?.removeFragment().toString() ?? resolved;
  }

  bool _looksLikeDiscuzAttachmentImage(html_dom.Element image) {
    final aid = image.attributes['aid']?.trim();
    if (aid != null && aid.isNotEmpty) {
      return true;
    }
    final id = image.id.trim();
    if (id.startsWith('aimg_')) {
      return true;
    }
    return _hasAncestorClass(image, 'tattl') ||
        _hasAncestorClass(image, 'attm') ||
        _hasAncestorClass(image, 'savephotop');
  }

  String _cleanAttachmentImageTag(html_dom.Element image, String realSource) {
    final attributes = <String, String>{
      'src': realSource,
      'file': image.attributes['file']?.trim() ?? realSource,
      'zoomfile': image.attributes['zoomfile']?.trim() ?? realSource,
    };
    for (final name in const <String>[
      'id',
      'aid',
      'width',
      'height',
      'w',
      'h',
      'alt',
      'title',
    ]) {
      final value = image.attributes[name]?.trim();
      if (value != null && value.isNotEmpty) {
        attributes[name] = value;
      }
    }
    final serialized = attributes.entries
        .map((entry) => '${entry.key}="${_escapeAttribute(entry.value)}"')
        .join(' ');
    return '<img $serialized />';
  }

  String _escapeAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  bool _hasAncestorClass(html_dom.Node node, String className) {
    html_dom.Node? current = node.parentNode;
    while (current != null) {
      if (current is html_dom.Element && current.classes.contains(className)) {
        return true;
      }
      current = current.parentNode;
    }
    return false;
  }

  String _parseDesktopDateline(html_dom.Element container, String pid) {
    final text = _cleanText(
      container.querySelector('#authorposton$pid')?.text ?? '',
    );
    if (text.isNotEmpty) {
      return text.replaceFirst(RegExp(r'^发表于\s*'), '').trim();
    }
    final authText = _cleanText(
      container.querySelector('.pti .authi')?.text ?? '',
    );
    final match = RegExp(r'发表于\s*([^|]+)').firstMatch(authText);
    return match?.group(1)?.trim() ?? '';
  }

  String? _parseRateSummaryFromSummary(ThreadPostRatingSummary? ratingSummary) {
    if (ratingSummary == null) {
      return null;
    }
    final compact = [
      ratingSummary.participantText,
      ratingSummary.scoreText,
    ].where((item) => item.isNotEmpty).join(' · ');
    return compact.isEmpty ? null : compact;
  }

  ThreadPostRatingSummary? _parseDesktopRatingSummary(
    html_dom.Element container,
    String pid,
  ) {
    final rateLog = container.querySelector('#ratelog_$pid');
    if (rateLog == null) {
      return null;
    }
    final participantAnchor = rateLog.querySelector('a[title="查看全部评分"]');
    final participantText = _cleanText(participantAnchor?.text ?? '');
    final headerCells = rateLog.querySelectorAll('.ratl th');
    final scoreText = headerCells.length > 1
        ? _cleanText(headerCells[1].text)
        : '';
    final rows = rateLog.querySelectorAll('.ratl_l tr[id^="rate_"]');
    final ratings = <ThreadPostRating>[];
    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      final userAnchor = cells.isEmpty ? null : _firstTextAnchor(cells[0]);
      final userName = _cleanText(userAnchor?.text ?? '');
      final score = cells.length > 1 ? _cleanText(cells[1].text) : '';
      final reason = cells.length > 2 ? _cleanText(cells[2].text) : '';
      if (userName.isEmpty && score.isEmpty && reason.isEmpty) {
        continue;
      }
      ratings.add(
        ThreadPostRating(
          userName: userName,
          userId: _extractUid(_resolve(userAnchor?.attributes['href'])),
          avatarUrl: _resolve(
            cells.isEmpty
                ? null
                : cells[0].querySelector('img')?.attributes['src'],
          ),
          score: score,
          reason: reason,
        ),
      );
    }
    if (participantText.isEmpty && scoreText.isEmpty && ratings.isEmpty) {
      return null;
    }
    return ThreadPostRatingSummary(
      participantText: participantText,
      scoreText: scoreText,
      viewAllUrl: _resolve(participantAnchor?.attributes['href']),
      ratings: List<ThreadPostRating>.unmodifiable(ratings),
    );
  }

  html_dom.Element? _firstTextAnchor(html_dom.Element container) {
    for (final anchor in container.querySelectorAll(
      'a[href*="space-uid"], a[href*="home.php"][href*="uid="]',
    )) {
      if (_cleanText(anchor.text).isNotEmpty) {
        return anchor;
      }
    }
    return null;
  }

  String? _parseActionUrl(html_dom.Element container, String action) {
    final direct = _resolve(
      container
          .querySelector('a[href*="mod=misc"][href*="action=$action"]')
          ?.attributes['href'],
    );
    if (direct != null) {
      return direct;
    }
    for (final anchor in container.querySelectorAll(
      'a[onclick*="action=$action"]',
    )) {
      final onclick = anchor.attributes['onclick'] ?? '';
      final match = RegExp(
        r'''['"]([^'"]*mod=misc[^'"]*action='''
        '$action'
        r'''[^'"]*)['"]''',
      ).firstMatch(onclick);
      final parsed = _resolve(match?.group(1));
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  String? _parseReverseOrderUrl(html_dom.Document document) {
    for (final anchor in document.querySelectorAll('a[href*="ordertype=1"]')) {
      final label = _cleanText(anchor.text);
      if (label.contains('倒序')) {
        return _resolve(anchor.attributes['href']);
      }
    }
    return _resolve(
      document.querySelector('a[href*="ordertype=1"]')?.attributes['href'],
    );
  }

  String? _parseOnlyAuthorUrl(html_dom.Document document) {
    for (final anchor in document.querySelectorAll('a[href*="authorid="]')) {
      final label = _cleanText(anchor.text);
      if (label.contains('只看')) {
        return _resolve(anchor.attributes['href']);
      }
    }
    return _resolve(
      document.querySelector('a[href*="authorid="]')?.attributes['href'],
    );
  }

  String? _parseFavoriteUrl(html_dom.Document document) {
    return _resolve(
      document
          .querySelector(
            'a[href*="home.php"][href*="ac=favorite"][href*="type=thread"]',
          )
          ?.attributes['href'],
    );
  }

  String? _parseShareUrl(html_dom.Document document) {
    return _resolve(
      document
          .querySelector(
            'a[href*="home.php"][href*="ac=share"][href*="type=thread"]',
          )
          ?.attributes['href'],
    );
  }

  String _extractPid(html_dom.Element container) {
    final id = container.id.trim();
    final postMatch = RegExp(r'post_(\d+)').firstMatch(id);
    if (postMatch != null) {
      return postMatch.group(1)!;
    }
    final mobileMatch = RegExp(r'pid(\d+)').firstMatch(id);
    if (mobileMatch != null) {
      return mobileMatch.group(1)!;
    }
    final tableId = container.querySelector('table[id^="pid"]')?.id ?? '';
    return RegExp(r'pid(\d+)').firstMatch(tableId)?.group(1) ?? '';
  }

  String? _extractTid(html_dom.Document document) {
    final canonical = document
        .querySelector('link[rel="canonical"]')
        ?.attributes['href'];
    final canonicalTid =
        _extractQueryValue(canonical, 'tid') ??
        RegExp(
          r'thread-(\d+)-',
        ).firstMatch(Uri.tryParse(canonical ?? '')?.path ?? '')?.group(1);
    if (canonicalTid != null && canonicalTid.isNotEmpty) {
      return canonicalTid;
    }
    for (final anchor in document.querySelectorAll(
      'a[href*="mod=viewthread"], a[href*="thread-"]',
    )) {
      final url = _resolve(anchor.attributes['href']);
      final tid =
          _extractQueryValue(url, 'tid') ??
          RegExp(
            r'thread-(\d+)-',
          ).firstMatch(Uri.tryParse(url ?? '')?.path ?? '')?.group(1);
      if (tid != null && tid.isNotEmpty) {
        return tid;
      }
    }
    return null;
  }

  String? _extractFid(html_dom.Document document) {
    final breadcrumbFid = _extractForumFid(
      _resolve(_parseBreadcrumbForumAnchor(document)?.attributes['href']),
    );
    if (breadcrumbFid != null && breadcrumbFid.isNotEmpty) {
      return breadcrumbFid;
    }
    final curTypeFid = document
        .querySelector('a[rel="curforum"][fid]')
        ?.attributes['fid'];
    if (curTypeFid != null && curTypeFid.trim().isNotEmpty) {
      return curTypeFid.trim();
    }
    for (final anchor in document.querySelectorAll(
      '#pt a[href*="forum-"], a[href*="forumdisplay"][href*="fid="], a[href*="action=newthread"][href*="fid="]',
    )) {
      final fid = _extractForumFid(_resolve(anchor.attributes['href']));
      if (fid != null && fid.isNotEmpty) {
        return fid;
      }
    }
    return null;
  }

  String? _extractForumFid(String? url) {
    return _extractQueryValue(url, 'fid') ??
        RegExp(
          r'forum-(\d+)-',
        ).firstMatch(Uri.tryParse(url ?? '')?.path ?? '')?.group(1);
  }

  String? _extractTypeId(html_dom.Document document) {
    for (final anchor in document.querySelectorAll('a[href*="typeid="]')) {
      final typeId = _extractQueryValue(
        _resolve(anchor.attributes['href']),
        'typeid',
      );
      if (typeId != null && typeId.isNotEmpty) {
        return typeId;
      }
    }
    return null;
  }

  int _parseCurrentPage(html_dom.Document document, {required int fallback}) {
    final current = _parseFirstInt(
      document.querySelector('.pg strong')?.text ?? '',
    );
    return current > 0 ? current : fallback;
  }

  int? _parseLastPage(html_dom.Document document) {
    final last = _parseFirstInt(
      document.querySelector('.pg a.last')?.text ?? '',
    );
    if (last > 0) {
      return last;
    }
    var maxPage = 0;
    for (final anchor in document.querySelectorAll('.pg a')) {
      final parsed = _extractPageFromUrl(_resolve(anchor.attributes['href']));
      if (parsed > maxPage) {
        maxPage = parsed;
      }
    }
    return maxPage > 0 ? maxPage : null;
  }

  String? _firstPresentAttribute(
    html_dom.Element element,
    List<String> attributes,
  ) {
    for (final attribute in attributes) {
      final value = element.attributes[attribute]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? _extractUid(String? url) =>
      _extractQueryValue(url, 'uid') ??
      RegExp(
        r'space-uid-(\d+)',
      ).firstMatch(Uri.tryParse(url ?? '')?.path ?? '')?.group(1);

  int _extractPageFromUrl(String? url) {
    if (url == null || url.isEmpty) {
      return 0;
    }
    final queryPage = int.tryParse(_extractQueryValue(url, 'page') ?? '');
    if (queryPage != null) {
      return queryPage;
    }
    final path = Uri.tryParse(url)?.path ?? '';
    return int.tryParse(
          RegExp(r'thread-\d+-(\d+)-').firstMatch(path)?.group(1) ?? '',
        ) ??
        0;
  }

  String? _extractQueryValue(String? resolvedUrl, String key) {
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return null;
    }
    return Uri.tryParse(resolvedUrl)?.queryParameters[key]?.trim();
  }

  String? _resolve(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return _urlResolver.resolve(value).toString();
    } on FormatException {
      return null;
    }
  }

  int _parseLabeledInt(String source, String label) {
    final match = RegExp('$label\\s*[:：]\\s*(\\d+)').firstMatch(source);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  int _parseFirstInt(String source) {
    final match = RegExp(r'\d+').firstMatch(source);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  String _cleanText(String source) {
    return source
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripBrackets(String source) {
    return source.replaceAll(RegExp(r'^\[|\]$'), '').trim();
  }

  String _stripPollNumber(String source) {
    return source
        .replaceFirst(RegExp(r'^\s*\d+\.\s*(?:&nbsp;)?\s*'), '')
        .trim();
  }

  html_dom.Element _cloneWithout(
    html_dom.Element? source,
    List<String> selectors,
  ) {
    final clone = (source ?? html_dom.Element.tag('div')).clone(true);
    for (final selector in selectors) {
      clone.querySelectorAll(selector).forEach((node) => node.remove());
    }
    return clone;
  }
}

class _ThreadHeader {
  const _ThreadHeader({
    required this.subject,
    required this.views,
    required this.replies,
    this.typeName,
    this.forumName,
    this.forumUrl,
  });

  final String subject;
  final String? typeName;
  final String? forumName;
  final String? forumUrl;
  final int views;
  final int replies;
}
