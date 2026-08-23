import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/data/services/forum_user_profile_html_parser.dart';

void main() {
  const parser = ForumUserProfileHtmlParser();

  test('parses public mobile profile into the source-neutral contract', () {
    final html = File('docs/html/个人页/一个个人页.html').readAsStringSync();

    final profile = parser.parse(
      html: html,
      expectedUserId: '509957',
      siteOrigin: 'https://bbs.yamibo.com/',
    );

    expect(profile.identity.userId, '509957');
    expect(profile.identity.displayName, 'zhongmefeishi');
    expect(profile.avatarUrl, contains('avatar_middle'));
    expect(profile.coverUrl, contains('avatar_big'));
    expect(profile.metrics.map((item) => item.value), contains('5263'));
    expect(profile.metrics.map((item) => item.label), contains('总积分'));
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

  test('parses self mobile profile without action or formhash fields', () {
    final html = File('docs/html/我的资料/我的资料.html').readAsStringSync();

    final profile = parser.parse(
      html: html,
      expectedUserId: '597454',
      siteOrigin: 'https://bbs.yamibo.com/',
    );

    expect(profile.identity.userId, '597454');
    expect(profile.identity.displayName, '2834758851');
    expect(profile.avatarUrl, contains('noavatar.svg'));
    expect(
      profile.metrics.map((item) => item.value),
      containsAll(['65', '7 点']),
    );
    expect(
      profile.details.map((item) => '${item.label}:${item.value}'),
      contains('用户组:百合幼苗'),
    );
    expect(profile.signatureHtml, isNull);
  });

  test('fails when the trusted UID field is absent or mismatched', () {
    const missingUid = '''
      <div class="userinfo">
        <h2 class="name">Alice</h2>
        <div class="myinfo_list"><ul><li><b>个人资料</b></li></ul></div>
      </div>
    ''';
    const mismatchedUid = '''
      <div class="userinfo">
        <h2 class="name">Alice</h2>
        <div class="myinfo_list"><ul><li>UID<span>99</span></li></ul></div>
      </div>
    ''';

    expect(
      () => parser.parse(
        html: missingUid,
        expectedUserId: '42',
        siteOrigin: 'https://bbs.yamibo.com/',
      ),
      throwsFormatException,
    );
    expect(
      () => parser.parse(
        html: mismatchedUid,
        expectedUserId: '42',
        siteOrigin: 'https://bbs.yamibo.com/',
      ),
      throwsFormatException,
    );
  });

  test('only reads the profile cover from a user avatar CSS rule', () {
    const html = '''
      <style>
        body { background-image: url(https://example.com/page.jpg); }
        .user_avatar { background-image: url('/profile.jpg') !important; }
      </style>
      <div class="userinfo">
        <h2 class="name">Alice</h2>
        <div class="myinfo_list"><ul><li>UID<span>42</span></li></ul></div>
      </div>
    ''';

    final profile = parser.parse(
      html: html,
      expectedUserId: '42',
      siteOrigin: 'https://bbs.yamibo.com/',
    );

    expect(profile.coverUrl, 'https://bbs.yamibo.com/profile.jpg');
  });
}
