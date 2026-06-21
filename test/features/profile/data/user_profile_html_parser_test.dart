import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/data/user_profile_html_parser.dart';

void main() {
  test('UserProfileHtmlParser parses mobile profile page sample', () {
    final html = File('docs/html/个人页/一个个人页.html').readAsStringSync();
    const parser = UserProfileHtmlParser();

    final profile = parser.parse(html, fallbackUid: '509957');

    expect(profile.uid, '509957');
    expect(profile.username, 'zhongmefeishi');
    expect(profile.title, 'zhongmefeishi的资料');
    expect(profile.avatarUrl, contains('avatar_middle'));
    expect(profile.coverUrl, contains('avatar_big'));
    expect(profile.credits.map((item) => item.value), contains('5263'));
    expect(profile.credits.map((item) => item.label), contains('总积分'));
    expect(profile.threadUrl, contains('do=thread'));
    expect(profile.blogUrl, contains('do=blog'));
    expect(profile.messageUrl, contains('do=pm'));
    expect(profile.friendUrl, contains('friend'));
    expect(profile.signatureHtml, contains('Make a deal with god'));
    expect(profile.signatureHtml, contains('<img'));
    expect(
      profile.details.map((item) => '${item.label}:${item.value}'),
      contains('用户组:百合達人'),
    );
    expect(
      profile.details.map((item) => '${item.label}:${item.value}'),
      contains('最后访问:2026-6-21 14:40'),
    );
  });
}
