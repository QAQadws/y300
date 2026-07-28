import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/data/services/user_profile_html_parser.dart';

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

  test('UserProfileHtmlParser parses my profile mobile page sample', () {
    final html = File('docs/html/我的资料/我的资料.html').readAsStringSync();
    const parser = UserProfileHtmlParser();

    final profile = parser.parse(html, fallbackUid: '597454');

    expect(profile.uid, '597454');
    expect(profile.username, '2834758851');
    expect(profile.title, '我的资料');
    expect(profile.avatarUrl, contains('noavatar.svg'));
    expect(profile.credits.map((item) => item.value), contains('65'));
    expect(profile.credits.map((item) => item.value), contains('7 点'));
    expect(profile.threadUrl, contains('do=thread'));
    expect(profile.blogUrl, contains('do=blog'));
    expect(profile.favoriteUrl, contains('do=favorite'));
    expect(profile.messageUrl, contains('do=pm'));
    expect(profile.friendUrl, contains('do=friend'));
    expect(profile.signUrl, contains('zqlj_sign'));
    expect(profile.settingsUrl, contains('spacecp'));
    expect(profile.logoutUrl, contains('action=logout'));
    expect(
      profile.actions.map((action) => action.label),
      containsAll(['我的主题', '我的日志', '我的收藏', '消息提醒', '我的好友', '每日签到']),
    );
    expect(
      profile.details.map((item) => '${item.label}:${item.value}'),
      contains('用户组:百合幼苗'),
    );
  });

  test('keeps a missing server title empty for presentation fallback', () {
    const parser = UserProfileHtmlParser();

    final profile = parser.parse(
      '<div class="userinfo"><h2 class="name">alice</h2></div>',
      fallbackUid: '509957',
    );

    expect(profile.username, 'alice');
    expect(profile.title, isEmpty);
  });
}
