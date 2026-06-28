import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/services/thread_detail_html_parser.dart';

void main() {
  test('ThreadDetailHtmlParser extracts main post bottom tag links', () {
    final html = File('docs/html/帖子详细页/一个电脑端漫画帖子.html').readAsStringSync();
    const parser = ThreadDetailHtmlParser();

    final detail = parser.parse(html, fallbackTid: '571955', fallbackPage: 1);

    final firstPost = detail.posts.firstWhere((post) => post.isFirst);
    expect(firstPost.tagLinks.map((tag) => tag.label), contains('提灯喵汉化组'));
    expect(firstPost.tagLinks.map((tag) => tag.label), contains('伏見七尾'));
    expect(firstPost.tagLinks.map((tag) => tag.label), contains('銃爺'));
    expect(firstPost.tagLinks.map((tag) => tag.label), contains('狱门抚子在此'));
    expect(
      firstPost.tagLinks.map((tag) => tag.url),
      contains('https://bbs.yamibo.com/misc.php?mod=tag&id=20674'),
    );
    expect(firstPost.tagLinks.last.tagId, '20674');
  });
}
