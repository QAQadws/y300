import 'package:html/dom.dart';

import '../contracts/forum_message_attention.dart';
import '../parsing/discuz_html_document.dart';
import '../parsing/discuz_message_attention_source.dart';
import '../parsing/discuz_navigation_viewer.dart';

/// Extracts arrival indicators from supported Discuz public HTML navigation.
///
/// This parser performs no I/O or JavaScript execution. Unsupported, partial,
/// erroneous, consuming, or identity-mismatched documents return `null`.
/// An observation alone does not establish response freshness or session order.
final class DiscuzMessageAttentionHtmlParser {
  /// Creates a parser bound to the expected forum origin.
  const DiscuzMessageAttentionHtmlParser({required this.siteOrigin});

  /// Expected HTTP(S) origin for the document and public navigation links.
  final Uri siteOrigin;

  /// Parses a complete response for [expectedUserId] at its final [sourceUri].
  ///
  /// Public navigation can occur in searches, tags and editor preparation as
  /// well as content pages. Consuming responses are deliberately excluded:
  /// their navigation may retain pre-consumption flags. `unknown` fields must
  /// never clear prior state.
  ForumMessageAttentionObservation? parse(
    String source, {
    required Uri sourceUri,
    required String expectedUserId,
  }) => parseDocument(
    DiscuzHtmlDocument.fromSource(source),
    sourceUri: sourceUri,
    expectedUserId: expectedUserId,
  );

  /// Extracts evidence from the same request-local document as business reads.
  ///
  /// The shared document remains unmodified. Completeness and EOF diagnostics
  /// still describe the original response; a repaired DOM alone cannot prove
  /// that the server sent a complete inactive navigation shell.
  ForumMessageAttentionObservation? parseDocument(
    DiscuzHtmlDocument source, {
    required Uri sourceUri,
    required String expectedUserId,
  }) {
    if (!_positiveId.hasMatch(expectedUserId) ||
        !acceptsDiscuzMessageAttentionHtmlSource(
          sourceUri,
          siteOrigin: siteOrigin,
        ) ||
        !source.isCompleteDocument ||
        source.hasUnexpectedEof) {
      return null;
    }
    final document = source.document;
    final body = document.body;
    if (body == null ||
        document.querySelector('#messagetext, .jump_c') != null ||
        _viewer(document) != expectedUserId) {
      return null;
    }

    final footers = body.children.where(
      (element) =>
          element.classes.contains('foot') &&
          element.classes.contains('flex-box'),
    );
    final desktopRoots = body.children.where(
      (element) => element.classes.contains('oyheader') || element.id == 'hd',
    );
    // Mixed shells or duplicate public containers cannot establish one snapshot.
    if (footers.isNotEmpty) {
      if (footers.length != 1 || desktopRoots.isNotEmpty) return null;
      return _mobile(footers.single, sourceUri, expectedUserId);
    }
    return _desktop(body, sourceUri, expectedUserId);
  }

  ForumMessageAttentionObservation? _mobile(
    Element footer,
    Uri sourceUri,
    String viewer,
  ) {
    final links = footer.children
        .where((element) => element.localName == 'a')
        .toList();
    if (links.length < 3 ||
        links.any((element) => !element.classes.contains('flex'))) {
      return null;
    }
    final messageLinks = links.where(
      (element) => _spaceLink(element, sourceUri, 'pm'),
    );
    final profileLinks = links.where(
      (element) => _ownSpaceLink(element, sourceUri, viewer),
    );
    if (messageLinks.length > 1 || profileLinks.length != 1) return null;
    final profileIcon = _mobileIcon(profileLinks.single, 'me');
    if (profileIcon == null) return null;
    final profile = _mobileDot(profileIcon);
    if (messageLinks.isEmpty) {
      // The default touch footer can use the second slot for portal/group/
      // feed rather than PM. Its profile dot proves a combined positive only;
      // the template conditionally suppresses this dot, so absence is unknown.
      return profile == true
          ? ForumMessageAttentionObservation(
              viewerUserId: viewer,
              source: ForumMessageAttentionSource.mobileHtml,
              combinedHint: _present,
            )
          : null;
    }
    final messageIcon = _mobileIcon(messageLinks.single, 'mb');
    if (messageIcon == null) return null;
    final message = _mobileDot(messageIcon);
    if (message == null || profile == null || (!message && profile)) {
      return null;
    }
    // The profile dot is conditional in the template; its absence is not zero.
    return ForumMessageAttentionObservation(
      viewerUserId: viewer,
      source: ForumMessageAttentionSource.mobileHtml,
      combinedHint: message ? _present : _absent,
    );
  }

  Element? _mobileIcon(Element link, String iconClass) {
    final spans = link.children.where(
      (element) =>
          element.localName == 'span' && element.classes.contains('foot-ico'),
    );
    if (spans.length != 1) return null;
    final icons = spans.single.children;
    if (icons.length != 1 ||
        icons.single.localName != 'em' ||
        !icons.single.classes.contains(iconClass)) {
      return null;
    }
    return icons.single;
  }

  bool? _mobileDot(Element icon) {
    if (icon.children.isEmpty) return false;
    if (icon.children.length == 1 &&
        icon.children.single.localName == 'i' &&
        icon.children.single.classes.contains('ico_msg')) {
      return true;
    }
    return null;
  }

  ForumMessageAttentionObservation? _desktop(
    Element body,
    Uri sourceUri,
    String viewer,
  ) {
    final tools = <Element>[];
    for (final root in body.children) {
      if (root.classes.contains('oyheader')) {
        tools.addAll(root.querySelectorAll('.header-tool'));
      } else if (root.id == 'hd') {
        tools.addAll(root.querySelectorAll('#um'));
      }
    }
    if (tools.length != 1) return null;
    final tool = tools.single;
    if (!tool
        .querySelectorAll('a')
        .any((link) => _ownSpaceLink(link, sourceUri, viewer))) {
      return null;
    }
    final pmLinks = tool.querySelectorAll('a#pm_ntc');
    final noticeLinks = tool.querySelectorAll('a#myprompt');
    if (pmLinks.length != 1 ||
        noticeLinks.length != 1 ||
        !_spaceLink(pmLinks.single, sourceUri, 'pm') ||
        !_spaceLink(noticeLinks.single, sourceUri, 'notice') ||
        !noticeLinks.single.classes.contains('showmenu')) {
      return null;
    }
    var pm = pmLinks.single.classes.contains('new') ? _present : _absent;
    var notifications = noticeLinks.single.classes.contains('new')
        ? _present
        : _unknown;
    int? count = notifications == _present
        ? _notificationCount(noticeLinks.single.text)
        : null;

    final menus = body.children.where(
      (element) => element.id == 'myprompt_menu',
    );
    if (menus.length > 1) return null;
    if (menus.length == 1) {
      final menu = menus.single;
      final menuPmLinks = menu.querySelectorAll('li > a#pm_ntc');
      if (menu.localName != 'ul' ||
          !menu.classes.contains('p_pop') ||
          menuPmLinks.length != 1 ||
          !_spaceLink(menuPmLinks.single, sourceUri, 'pm')) {
        return null;
      }
      final markers = menuPmLinks.single.children;
      if (markers.length != 1 || markers.single.localName != 'em') return null;
      final positive = markers.single.classes.contains('prompt_news');
      final negative = markers.single.classes.contains('prompt_news_0');
      if (positive == negative) return null;
      final menuPm = positive ? _present : _absent;
      if (pm != menuPm) pm = _unknown;
      // This menu is rendered only with the notification visibility gate open.
      // Without it, a plain myprompt link cannot establish an inactive hint.
      if (notifications == _unknown) {
        notifications = _absent;
        count = 0;
      }
    }
    if (pm == _unknown && notifications == _unknown) return null;
    return ForumMessageAttentionObservation(
      viewerUserId: viewer,
      source: ForumMessageAttentionSource.desktopHtml,
      privateMessages: pm,
      notifications: notifications,
      notificationCount: count,
    );
  }

  String? _viewer(Document document) {
    final head = document.head;
    if (head == null) return null;
    return discuzNavigationViewer(
      head
          .querySelectorAll('script:not([src])')
          .where(
            (script) => const {
              null,
              '',
              'text/javascript',
              'application/javascript',
            }.contains(script.attributes['type']?.trim().toLowerCase()),
          )
          .map((script) => script.text),
    );
  }

  bool _spaceLink(Element element, Uri sourceUri, String destination) {
    final uri = _link(element, sourceUri);
    if (uri == null || uri.path != '/home.php') return false;
    final query = _query(uri);
    return query != null &&
        query['mod'] == 'space' &&
        query['do'] == destination &&
        query.keys.every(const {'mod', 'do', 'mobile'}.contains);
  }

  bool _ownSpaceLink(Element element, Uri sourceUri, String viewer) {
    final uri = _link(element, sourceUri);
    if (uri == null) return false;
    final query = _query(uri);
    final rewrite = _ownSpaceRewrite.firstMatch(uri.path);
    if (rewrite != null) {
      // This link identifies the navigation's owner; it is not itself a
      // sampled response. Bare space rewrites may still consume on navigation.
      return rewrite[1] == viewer &&
          query != null &&
          (query['do'] == null || query['do'] == 'profile') &&
          query.keys.every(const {'do', 'mycenter', 'mobile'}.contains);
    }
    if (uri.path != '/home.php') return false;
    return query != null &&
        query['mod'] == 'space' &&
        query['uid'] == viewer &&
        (query['do'] == null || query['do'] == 'profile') &&
        query.keys.every(
          const {'mod', 'uid', 'do', 'mycenter', 'mobile'}.contains,
        );
  }

  Uri? _link(Element element, Uri sourceUri) {
    final href = element.attributes['href'];
    if (href == null || href.trim() != href || href.isEmpty) return null;
    try {
      final uri = sourceUri.resolve(href);
      return _sameOrigin(uri) && !uri.hasFragment ? uri : null;
    } on FormatException {
      return null;
    }
  }

  bool _sameOrigin(Uri uri) =>
      const {'http', 'https'}.contains(siteOrigin.scheme) &&
      siteOrigin.host.isNotEmpty &&
      siteOrigin.userInfo.isEmpty &&
      uri.scheme == siteOrigin.scheme &&
      uri.host == siteOrigin.host &&
      uri.port == siteOrigin.port &&
      uri.userInfo.isEmpty;

  Map<String, String>? _query(Uri uri) {
    try {
      final values = uri.queryParametersAll;
      if (values.values.any((value) => value.length != 1)) return null;
      return values.map((key, value) => MapEntry(key, value.single));
    } on FormatException {
      return null;
    }
  }

  int? _notificationCount(String text) {
    final match = _countSuffix.firstMatch(text);
    if (match == null ||
        text.substring(0, match.start).contains(RegExp(r'[()]'))) {
      return null;
    }
    final value = int.tryParse(match.group(1)!);
    return value != null && value > 0 && value <= 9007199254740991
        ? value
        : null;
  }

  static const _unknown = ForumMessageAttentionState.unknown;
  static const _absent = ForumMessageAttentionState.absent;
  static const _present = ForumMessageAttentionState.present;
  static final _positiveId = RegExp(r'^[1-9][0-9]*$');
  static final _countSuffix = RegExp(r'\(([0-9]+)\)\s*$');
  static final _ownSpaceRewrite = RegExp(r'^/space-uid-([1-9][0-9]*)\.html$');
}
