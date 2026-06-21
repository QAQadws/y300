import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/tags/data/yamibo_tag_thread_page_html_parser.dart';

void main() {
  group('YamiboTagThreadPageHtmlParser', () {
    test('parses desktop tag thread page sample', () {
      final html = File('docs/html/帖子详细页/tag页样例.html').readAsStringSync();
      final parser = YamiboTagThreadPageHtmlParser();

      final page = parser.parse(
        html: html,
        pageUrl:
            'https://bbs.yamibo.com/misc.php?mod=tag&id=21920&type=thread&page=1',
      );

      expect(page.tagId, '21920');
      expect(page.tagName, 'きさらぎ壱吾短篇集');
      expect(page.threads, hasLength(9));
      expect(page.pagination.currentPage, 1);
      expect(page.pagination.nextPageUrl, isNull);

      final first = page.threads.first;
      expect(first.tid, '572514');
      expect(first.subject, '【个人汉化】[きさらぎ壱吾]晒猫');
      expect(first.threadUrl, 'https://bbs.yamibo.com/thread-572514-1-1.html');
      expect(first.forumName, '中文百合漫画区');
      expect(first.forumUrl, 'https://bbs.yamibo.com/forum-30-1.html');
      expect(first.forumId, '30');
      expect(first.authorName, '2440760273');
      expect(first.authorId, '399468');
      expect(first.createdAt, '2026-6-15');
      expect(first.replyCount, 14);
      expect(first.viewCount, 3092);
      expect(first.lastPosterName, 'hyrami');
      expect(first.lastPostAt, '2026-6-18 20:55');
      expect(first.hasImageAttachment, isTrue);
    });
  });
}
