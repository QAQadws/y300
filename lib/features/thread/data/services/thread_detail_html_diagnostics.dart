import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

final class ThreadDetailHtmlDiagnosticSnapshot {
  const ThreadDetailHtmlDiagnosticSnapshot({
    required this.bodyLength,
    required this.utf8Bytes,
    required this.template,
    required this.bodyId,
    required this.bodyClass,
    required this.title,
    required this.canonicalHref,
    required this.viewthreadCount,
    required this.viewTitleCount,
    required this.mobilePostContainerCount,
    required this.desktopPostTableCount,
    required this.postWrapperCount,
    required this.postMessageNodeCount,
    required this.imageCount,
    required this.attachmentImageCount,
    required this.fontTagCount,
    required this.scriptCount,
    required this.errorMarkers,
    required this.messageSnippet,
  });

  final int bodyLength;
  final int utf8Bytes;
  final String template;
  final String bodyId;
  final String bodyClass;
  final String title;
  final String canonicalHref;
  final int viewthreadCount;
  final int viewTitleCount;
  final int mobilePostContainerCount;
  final int desktopPostTableCount;
  final int postWrapperCount;
  final int postMessageNodeCount;
  final int imageCount;
  final int attachmentImageCount;
  final int fontTagCount;
  final int scriptCount;
  final List<String> errorMarkers;
  final String messageSnippet;

  String toLogFields() {
    return [
      'bodyLength=$bodyLength',
      'utf8Bytes=$utf8Bytes',
      'template=$template',
      'bodyId=${_quote(bodyId)}',
      'bodyClass=${_quote(bodyClass)}',
      'title=${_quote(title)}',
      'canonical=${_quote(canonicalHref)}',
      'viewthread=$viewthreadCount',
      'viewTitle=$viewTitleCount',
      'mobilePosts=$mobilePostContainerCount',
      'desktopPidTables=$desktopPostTableCount',
      'postWrappers=$postWrapperCount',
      'messageNodes=$postMessageNodeCount',
      'images=$imageCount',
      'aimg=$attachmentImageCount',
      'fontTags=$fontTagCount',
      'scripts=$scriptCount',
      'markers=${errorMarkers.isEmpty ? '-' : errorMarkers.join('|')}',
      if (messageSnippet.isNotEmpty) 'message=${_quote(messageSnippet)}',
    ].join(' ');
  }

  static String _quote(String value) {
    if (value.isEmpty) {
      return '""';
    }
    return '"${value.replaceAll('"', r'\"')}"';
  }
}

final class ThreadDetailHtmlDiagnostics {
  const ThreadDetailHtmlDiagnostics();

  ThreadDetailHtmlDiagnosticSnapshot inspect(String html) {
    final document = html_parser.parse(html);
    final body = document.body;
    final errorMarkers = _errorMarkers(document);
    return ThreadDetailHtmlDiagnosticSnapshot(
      bodyLength: html.length,
      utf8Bytes: utf8.encode(html).length,
      template: _template(document, errorMarkers),
      bodyId: body?.id.trim() ?? '',
      bodyClass: body?.classes.join(' ') ?? '',
      title: _compact(document.querySelector('title')?.text),
      canonicalHref:
          document.querySelector('link[rel="canonical"]')?.attributes['href'] ??
          '',
      viewthreadCount: document.querySelectorAll('.viewthread').length,
      viewTitleCount: document.querySelectorAll('.view_tit').length,
      mobilePostContainerCount: document
          .querySelectorAll('.viewthread .plc[id^="pid"]')
          .length,
      desktopPostTableCount: document
          .querySelectorAll('table[id^="pid"]')
          .length,
      postWrapperCount: document.querySelectorAll('[id^="post_"]').length,
      postMessageNodeCount: document
          .querySelectorAll('[id^="postmessage_"], td.t_f, .message')
          .length,
      imageCount: document.querySelectorAll('img').length,
      attachmentImageCount: document
          .querySelectorAll(
            'a[id^="aimg_"], img[id^="aimg_"], img[file], img[aid]',
          )
          .length,
      fontTagCount: document.querySelectorAll('font').length,
      scriptCount: document.querySelectorAll('script').length,
      errorMarkers: errorMarkers,
      messageSnippet: _messageSnippet(document),
    );
  }

  String _template(html_dom.Document document, List<String> errorMarkers) {
    final body = document.body;
    final mobilePostContainers = document
        .querySelectorAll('.viewthread .plc[id^="pid"]')
        .length;
    if (body?.id == 'forum' && mobilePostContainers > 0) {
      return 'mobile-thread';
    }
    if (document.querySelectorAll('table[id^="pid"]').isNotEmpty ||
        document.querySelector('#postlist') != null) {
      return 'desktop-thread';
    }
    if (errorMarkers.isNotEmpty) {
      return 'message-or-error';
    }
    if (body?.id == 'forum' && document.querySelector('.viewthread') != null) {
      return 'mobile-thread-shell';
    }
    return 'unknown';
  }

  List<String> _errorMarkers(html_dom.Document document) {
    final text = _compact(document.body?.text ?? document.text);
    final markers = <String>[];
    if (document.querySelector('#messagetext, .alert_error, .showmessage') !=
        null) {
      markers.add('discuz-message');
    }
    if (document.querySelector('#loginform, form[name="login"]') != null ||
        document.querySelector('input[name="username"]') != null) {
      markers.add('login-form');
    }
    final checks = <String, String>{
      'requires-login': '您需要登录',
      'permission-denied': '您无权',
      'thread-missing': '指定的主题不存在',
      'thread-deleted': '已被删除',
      'system-busy': '系统繁忙',
      'operation-denied': '抱歉',
    };
    for (final entry in checks.entries) {
      if (text.contains(entry.value)) {
        markers.add(entry.key);
      }
    }
    return List<String>.unmodifiable(markers);
  }

  String _messageSnippet(html_dom.Document document) {
    final node =
        document.querySelector('#messagetext') ??
        document.querySelector('.alert_error') ??
        document.querySelector('.showmessage');
    return _compact(node?.text, maxLength: 120);
  }

  static String _compact(String? text, {int maxLength = 80}) {
    final compacted = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compacted.length <= maxLength) {
      return compacted;
    }
    return '${compacted.substring(0, maxLength)}...';
  }
}
