import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/profile/data/models/profile_blog_models.dart';

class ProfileBlogHtmlParser {
  const ProfileBlogHtmlParser({
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
  }) : _urlResolver = urlResolver;

  final SiteUrlResolver _urlResolver;

  ProfileBlogListPageData parseList(
    String html, {
    required ProfileBlogView fallbackView,
    required ProfileBlogOrder fallbackOrder,
  }) {
    final document = html_parser.parse(html);
    final viewTabs = _parseTabs(document, '.dhnv a');
    final orderTabs = _parseTabs(document, '#dhnavs_li a');
    final activeView = _activeBlogView(viewTabs, fallbackView);
    final activeOrder = activeView == ProfileBlogView.all
        ? _activeBlogOrder(orderTabs, fallbackOrder)
        : fallbackOrder;
    final items = document
        .querySelectorAll('.threadlist > ul > li.list')
        .map(_parseListItem)
        .whereType<ProfileBlogListItem>()
        .toList(growable: false);

    return ProfileBlogListPageData(
      title: _cleanText(document.querySelector('.header h2')?.text ?? ''),
      activeView: activeView,
      activeOrder: activeOrder,
      viewTabs: List<ProfileBlogNavigationTab>.unmodifiable(viewTabs),
      orderTabs: List<ProfileBlogNavigationTab>.unmodifiable(orderTabs),
      items: List<ProfileBlogListItem>.unmodifiable(items),
      emptyMessage: _parseEmptyMessage(document),
      pagination: _parsePagination(document),
    );
  }

  ProfileBlogDetailData parseDetail(
    String html, {
    required String fallbackUrl,
  }) {
    final document = html_parser.parse(html);
    final title = _cleanText(document.querySelector('.view_tit')?.text ?? '');
    final authorAnchor = document.querySelector('.plc .authi .mtit a');
    final authorUrl = _resolve(authorAnchor?.attributes['href']);
    final uid = _uidFromUrl(authorUrl) ?? _uidFromUrl(fallbackUrl) ?? '';
    final id = _blogIdFromUrl(fallbackUrl) ?? _parseCommentFormBlogId(document);
    final statLine = document.querySelector('.plc .authi .mtime');
    final messageNode = document.querySelector('.plc .message');
    final actions = document
        .querySelectorAll('.threadlist_foot a[href]')
        .map(
          (anchor) => ProfileBlogAction(
            label: _cleanText(anchor.text),
            url: _resolve(anchor.attributes['href']) ?? '',
          ),
        )
        .where((action) => action.label.isNotEmpty && action.url.isNotEmpty)
        .toList(growable: false);
    final comments = document
        .querySelectorAll('li.doing_list_li')
        .map(_parseComment)
        .whereType<ProfileBlogComment>()
        .toList(growable: false);

    return ProfileBlogDetailData(
      id: id,
      uid: uid,
      title: title,
      author: _cleanText(authorAnchor?.text ?? ''),
      authorUrl: authorUrl,
      avatarUrl: _resolve(
        document.querySelector('.plc .avatar img')?.attributes['src'],
      ),
      dateline: _parseDetailDatelineFromNode(statLine),
      views: _parseStatByIcon(statLine, 'dm-eye'),
      commentsCount: _parseStatByIcon(statLine, 'dm-chat-s'),
      messageHtml: messageNode?.innerHtml.trim() ?? '',
      actions: List<ProfileBlogAction>.unmodifiable(actions),
      comments: List<ProfileBlogComment>.unmodifiable(comments),
      commentForm: _parseCommentForm(document),
    );
  }

  List<ProfileBlogNavigationTab> _parseTabs(
    html_dom.Document document,
    String selector,
  ) {
    return document
        .querySelectorAll(selector)
        .map((anchor) {
          final parentClass = anchor.parent?.className ?? '';
          final className = anchor.className;
          return ProfileBlogNavigationTab(
            label: _cleanText(anchor.text),
            url: _resolve(anchor.attributes['href']) ?? '',
            isActive:
                className.split(' ').contains('mon') ||
                parentClass.split(' ').contains('mon'),
          );
        })
        .where((tab) => tab.label.isNotEmpty && tab.url.isNotEmpty)
        .toList();
  }

  ProfileBlogListItem? _parseListItem(html_dom.Element item) {
    final blogAnchor = item.querySelector('a[href*="do=blog"][href*="id="]');
    final url = _resolve(blogAnchor?.attributes['href']);
    if (url == null) {
      return null;
    }
    final authorAnchor = item.querySelector('.muser h3 a');
    final authorUrl = _resolve(authorAnchor?.attributes['href']);
    return ProfileBlogListItem(
      id: _blogIdFromUrl(url) ?? '',
      uid: _uidFromUrl(url) ?? _uidFromUrl(authorUrl) ?? '',
      title: _cleanText(item.querySelector('.threadlist_tit')?.text ?? ''),
      excerpt: _cleanText(item.querySelector('.threadlist_mes')?.text ?? ''),
      author: _cleanText(authorAnchor?.text ?? ''),
      authorUrl: authorUrl,
      avatarUrl: _resolve(item.querySelector('.avatar img')?.attributes['src']),
      dateline: _cleanText(item.querySelector('.mtime span')?.text ?? ''),
      url: url,
    );
  }

  ProfileBlogComment? _parseComment(html_dom.Element item) {
    final commentNode = item.querySelector('.do_comment');
    final authorAnchor = item.querySelector('.muser h3 a');
    final messageHtml = commentNode?.innerHtml.trim();
    if (messageHtml == null || messageHtml.isEmpty) {
      return null;
    }
    return ProfileBlogComment(
      id: _commentId(item) ?? '',
      author: _cleanText(authorAnchor?.text ?? ''),
      authorUrl: _resolve(authorAnchor?.attributes['href']),
      avatarUrl: _resolve(item.querySelector('.avatar img')?.attributes['src']),
      dateline: _cleanText(item.querySelector('.mtime span')?.text ?? ''),
      messageHtml: messageHtml,
      replyUrl: _resolve(
        item.querySelector('a[href*="ac=comment"]')?.attributes['href'],
      ),
    );
  }

  ProfileBlogPagination? _parsePagination(html_dom.Document document) {
    final container = document.querySelector('.pg');
    if (container == null) {
      return null;
    }
    final currentPage =
        int.tryParse(
          _cleanText(container.querySelector('strong')?.text ?? ''),
        ) ??
        1;
    final totalText = _cleanText(
      container.querySelector('label span')?.text ?? '',
    );
    final totalPages = RegExp(r'(\d+)').firstMatch(totalText)?.group(1);
    return ProfileBlogPagination(
      currentPage: currentPage,
      totalPages: int.tryParse(totalPages ?? '') ?? currentPage,
      nextUrl: _resolve(container.querySelector('a.nxt')?.attributes['href']),
      multipageUrl: _resolve(
        document.querySelector('#multipage_url')?.attributes['value'],
      ),
    );
  }

  ProfileBlogCommentForm? _parseCommentForm(html_dom.Document document) {
    final form = document.querySelector('form[id^="quickcommentform"]');
    if (form == null) {
      return null;
    }
    final actionUrl = _resolve(form.attributes['action']);
    final formhash = form
        .querySelector('input[name="formhash"]')
        ?.attributes['value']
        ?.trim();
    final blogId = form
        .querySelector('input[name="id"]')
        ?.attributes['value']
        ?.trim();
    final referer = form
        .querySelector('input[name="referer"]')
        ?.attributes['value']
        ?.trim();
    if (actionUrl == null ||
        formhash == null ||
        formhash.isEmpty ||
        blogId == null ||
        blogId.isEmpty ||
        referer == null ||
        referer.isEmpty) {
      return null;
    }
    return ProfileBlogCommentForm(
      actionUrl: actionUrl,
      formhash: formhash,
      blogId: blogId,
      referer: referer,
    );
  }

  ProfileBlogView _activeBlogView(
    List<ProfileBlogNavigationTab> tabs,
    ProfileBlogView fallback,
  ) {
    final active = _firstActiveTab(tabs);
    return switch (active?.label) {
      '好友的日志' => ProfileBlogView.friends,
      '我的日志' => ProfileBlogView.mine,
      '随便看看' => ProfileBlogView.all,
      _ => fallback,
    };
  }

  ProfileBlogOrder _activeBlogOrder(
    List<ProfileBlogNavigationTab> tabs,
    ProfileBlogOrder fallback,
  ) {
    final active = _firstActiveTab(tabs);
    return switch (active?.label) {
      '推荐阅读的日志' => ProfileBlogOrder.hot,
      '最新发表的日志' => ProfileBlogOrder.latest,
      _ => fallback,
    };
  }

  String? _parseEmptyMessage(html_dom.Document document) {
    final text = _cleanText(
      document.querySelector('.threadlist h4')?.text ?? '',
    );
    return text.isEmpty ? null : text;
  }

  int _parseStatByIcon(html_dom.Element? statLine, String iconClass) {
    final icon = statLine?.querySelector('i.$iconClass');
    final value = icon?.nextElementSibling?.text;
    return int.tryParse(_cleanText(value ?? '')) ?? 0;
  }

  String _parseDetailDatelineFromNode(html_dom.Element? statLine) {
    if (statLine == null) {
      return '';
    }
    final metricNode = statLine.querySelector('span.y');
    final text = statLine.nodes
        .where((node) => node != metricNode)
        .map((node) => node.text)
        .join(' ');
    return _cleanText(text);
  }

  ProfileBlogNavigationTab? _firstActiveTab(
    List<ProfileBlogNavigationTab> tabs,
  ) {
    for (final tab in tabs) {
      if (tab.isActive) {
        return tab;
      }
    }
    return null;
  }

  String? _commentId(html_dom.Element item) {
    final raw = item.id.trim();
    return RegExp(r'comment_(\d+)_li').firstMatch(raw)?.group(1) ??
        RegExp(r'(\d+)').firstMatch(raw)?.group(1);
  }

  String _parseCommentFormBlogId(html_dom.Document document) {
    return document
            .querySelector('input[name="id"]')
            ?.attributes['value']
            ?.trim() ??
        '';
  }

  String? _blogIdFromUrl(String? rawUrl) {
    final uri = Uri.tryParse(rawUrl ?? '');
    return uri?.queryParameters['id']?.trim();
  }

  String? _uidFromUrl(String? rawUrl) {
    final uri = Uri.tryParse(rawUrl ?? '');
    return uri?.queryParameters['uid']?.trim();
  }

  String? _resolve(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return _urlResolver.resolve(raw);
  }

  String _cleanText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
