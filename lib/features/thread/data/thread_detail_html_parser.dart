import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

class ThreadDetailHtmlParser {
  const ThreadDetailHtmlParser({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  ThreadDetailData parse(
    String html, {
    required String fallbackTid,
    required int fallbackPage,
    String fallbackSubject = '',
  }) {
    final document = html_parser.parse(html);
    final threadHeader = _parseThreadHeader(document);
    final posts = _parsePosts(document);
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

  _ThreadHeader _parseThreadHeader(html_dom.Document document) {
    final subject = _cleanText(
      document.querySelector('#thread_subject')?.text ?? '',
    );
    final typeAnchor = document.querySelector('.vwthd h1.ts a[href*="typeid"]');
    final typeName = _stripBrackets(_cleanText(typeAnchor?.text ?? ''));
    final forumAnchor =
        document.querySelector('a[rel="curforum"][fid]') ??
        document.querySelector('a[href*="forumdisplay"][href*="fid="]');
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

  List<ThreadPost> _parsePosts(html_dom.Document document) {
    final output = <ThreadPost>[];
    for (final container in document.querySelectorAll(
      '#postlist > div[id^="post_"]',
    )) {
      final post = _parsePost(container, output.length);
      if (post != null) {
        output.add(post);
      }
    }
    return output;
  }

  ThreadPost? _parsePost(html_dom.Element container, int index) {
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

    return ThreadPost(
      pid: pid,
      author: _cleanText(authorAnchor?.text ?? ''),
      authorId: _extractUid(_resolve(authorAnchor?.attributes['href'])) ?? '',
      message: _cleanPostMessageHtml(messageNode),
      number: number,
      isFirst: number == 1,
      dateline: _parseDateline(container, pid),
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
      rateUrl: _parseActionUrl(container, 'rate'),
      commentUrl: _resolve(
        container
            .querySelector('a[href*="mod=misc"][href*="action=comment"]')
            ?.attributes['href'],
      ),
      rateSummary: _parseRateSummary(container, pid),
      poll: number == 1 ? _parsePoll(container) : null,
    );
  }

  ThreadPoll? _parsePoll(html_dom.Element postContainer) {
    final form = postContainer.querySelector('form#poll');
    if (form == null) {
      return null;
    }
    final summary = _cleanText(form.querySelector('.pinf')?.text ?? '');
    final deadlineText = _cleanText(form.querySelector('.ptmr')?.text ?? '');
    final options = _parsePollOptions(form);
    if (summary.isEmpty && options.isEmpty) {
      return null;
    }
    final maxMatch = RegExp(r'最多可选\s*(\d+)\s*项').firstMatch(summary);
    return ThreadPoll(
      isMultipleChoice:
          form.querySelector('input[type="checkbox"]') != null ||
          summary.contains('多选'),
      maxChoices: int.tryParse(maxMatch?.group(1) ?? ''),
      summary: summary,
      deadlineText: deadlineText.isEmpty ? null : deadlineText,
      actionUrl: _resolve(form.attributes['action']),
      formHash: form
          .querySelector('input[name="formhash"]')
          ?.attributes['value']
          ?.trim(),
      options: List<ThreadPollOption>.unmodifiable(options),
    );
  }

  List<ThreadPollOption> _parsePollOptions(html_dom.Element form) {
    final output = <ThreadPollOption>[];
    final rows = form.querySelectorAll('table[summary="poll panel"] tr');
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final input = row.querySelector('input[name="pollanswers[]"]');
      final label = _cleanText(row.querySelector('label')?.text ?? '');
      if (input == null || label.isEmpty) {
        continue;
      }
      final resultRow = index + 1 < rows.length ? rows[index + 1] : null;
      output.add(
        ThreadPollOption(
          id:
              input.attributes['value']?.trim() ??
              input.attributes['id']?.trim() ??
              '',
          label: _stripPollNumber(label),
          voteCount: _parseVoteCount(resultRow),
          percent: _parsePollPercent(resultRow),
          colorHex: _parsePollColor(resultRow),
        ),
      );
    }
    return output;
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

  String _cleanPostMessageHtml(html_dom.Element? messageNode) {
    if (messageNode == null) {
      return '';
    }
    final clone = messageNode.clone(true);
    clone
        .querySelectorAll('script, style, .aimg_tip')
        .forEach((node) => node.remove());
    for (final image in clone.querySelectorAll('img')) {
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
    return clone.innerHtml.trim();
  }

  String _parseDateline(html_dom.Element container, String pid) {
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

  String? _parseRateSummary(html_dom.Element container, String pid) {
    final rateLog = container.querySelector('#ratelog_$pid');
    if (rateLog == null) {
      return null;
    }
    final participants = _cleanText(
      rateLog.querySelector('a[title="查看全部评分"]')?.text ?? '',
    );
    final score = _cleanText(
      rateLog.querySelector('.ratl th:nth-child(2)')?.text ?? '',
    );
    final compact = [
      participants,
      score,
    ].where((item) => item.isNotEmpty).join(' · ');
    return compact.isEmpty ? null : compact;
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
    final match = RegExp(r'post_(\d+)').firstMatch(id);
    if (match != null) {
      return match.group(1)!;
    }
    final tableId = container.querySelector('table[id^="pid"]')?.id ?? '';
    return RegExp(r'pid(\d+)').firstMatch(tableId)?.group(1) ?? '';
  }

  String? _extractTid(html_dom.Document document) {
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
    final curTypeFid = document
        .querySelector('a[rel="curforum"][fid]')
        ?.attributes['fid'];
    if (curTypeFid != null && curTypeFid.trim().isNotEmpty) {
      return curTypeFid.trim();
    }
    for (final anchor in document.querySelectorAll(
      'a[href*="forumdisplay"][href*="fid="], a[href*="action=newthread"][href*="fid="]',
    )) {
      final fid = _extractQueryValue(
        _resolve(anchor.attributes['href']),
        'fid',
      );
      if (fid != null && fid.isNotEmpty) {
        return fid;
      }
    }
    return null;
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
    return _urlResolver.resolve(value);
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
