import 'dart:io';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_daily_sign_in_page_parser.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  String fixture(String name) =>
      File('test/fixtures/daily_sign_in/$name.html').readAsStringSync();

  final unsigned = fixture('unsigned');
  final signed = fixture('signed');
  final pageUri = Uri.parse(
    'https://forum.example.test/plugin.php?id=zqlj_sign&mobile=2',
  );

  DiscuzDailySignInPage parse(
    String html, {
    Uri? sourceUri,
    Uri? requestedUri,
    String expectedUserId = '42',
  }) => const DiscuzDailySignInPageParser().parse(
    html,
    sourceUri: sourceUri ?? pageUri,
    requestedUri: requestedUri ?? pageUri,
    expectedUserId: expectedUserId,
  );

  void expectFailure(
    String html, {
    String? code,
    DataReadFailureKind kind = DataReadFailureKind.parse,
    Uri? sourceUri,
    Uri? requestedUri,
    String expectedUserId = '42',
  }) {
    expect(
      () => parse(
        html,
        sourceUri: sourceUri,
        requestedUri: requestedUri,
        expectedUserId: expectedUserId,
      ),
      throwsA(
        isA<DiscuzDailySignInParseFailure>()
            .having((failure) => failure.kind, 'kind', kind)
            .having((failure) => failure.code, 'code', code ?? anything),
      ),
    );
  }

  test('unsigned state binds identity, forum day, and ordered statistics', () {
    final page = parse(unsigned);
    expect(page.snapshot.userId, '42');
    expect(page.snapshot.forumDay, '20300412');
    expect(page.snapshot.status, ForumDailySignInStatus.unsigned);
    expect(page.snapshot.statistics?.map((entry) => entry.label), [
      '本月打卡',
      '累计打卡',
    ]);
    expect(page.snapshot.statistics?.map((entry) => entry.value), ['2天', '7天']);
    expect(page.signUri?.host, 'forum.example.test');
    expect(page.signUri?.path, '/plugin.php');
    expect(page.signUri?.queryParameters.keys.toSet(), {'id', 'sign'});
  });

  test('signed state never exposes an action, including poster button', () {
    final page = parse(signed);
    expect(page.snapshot.status, ForumDailySignInStatus.signed);
    expect(page.signUri, isNull);
    expect(page.snapshot.statistics, isNull);
  });

  test('device-side showtime script is not a date source', () {
    final html = unsigned.replaceFirst(
      'return new Date();',
      "return '2099年12月31日';",
    );
    expect(parse(html).snapshot.forumDay, '20300412');
  });

  test('login and guest pages require authentication', () {
    expectFailure(
      fixture('login'),
      sourceUri: Uri.parse('https://forum.example.test/member.php?mod=logging'),
      code: 'daily_sign_in_login_required',
      kind: DataReadFailureKind.unauthorized,
    );
    expectFailure(
      unsigned.replaceFirst("discuz_uid = '42'", "discuz_uid = '0'"),
      code: 'daily_sign_in_login_required',
      kind: DataReadFailureKind.unauthorized,
    );
  });

  for (final entry in <String, String>{
    'missing uid': unsigned.replaceFirst('discuz_uid', 'absent_uid'),
    'duplicate uid': unsigned.replaceFirst(
      '</head>',
      "<script>var discuz_uid = '42';</script></head>",
    ),
    'other user': unsigned.replaceFirst(
      "discuz_uid = '42'",
      "discuz_uid = '43'",
    ),
    'missing server date': unsigned.replaceFirst('2030年04月12日', '暂无日期'),
    'invalid server date': unsigned.replaceFirst('2030年04月12日', '2030年02月30日'),
    'calendar month conflict': unsigned.replaceFirst('2030年4月', '2030年5月'),
    'today day conflict': unsigned.replaceFirst(
      'day today">12',
      'day today">13',
    ),
    'missing today': unsigned.replaceFirst('day today', 'day'),
    'duplicate today': unsigned.replaceFirst(
      'class="day">13',
      'class="day today">13',
    ),
    'unknown today class': unsigned.replaceFirst(
      'day today',
      'day today uncertain',
    ),
    'button conflict': unsigned.replaceFirst('点击打卡', '今日已打卡'),
    'missing button': unsigned.replaceFirst('点击打卡', '请稍后'),
    'error page': fixture('error'),
    'WAF page': '<html><body><h1>Access denied</h1></body></html>',
    'invalid-sign homepage': '<html><body><h1>论坛首页</h1></body></html>',
  }.entries) {
    test('refuses ${entry.key}', () => expectFailure(entry.value));
  }

  test('expected account mismatch never yields unsigned state', () {
    expectFailure(
      unsigned,
      expectedUserId: '43',
      code: 'daily_sign_in_user_mismatch',
    );
  });

  for (final href in <String>[
    'https://attacker.example.test/plugin.php?id=zqlj_sign&sign=fixtureToken0001',
    '//attacker.example.test/plugin.php?id=zqlj_sign&sign=fixtureToken0001',
    'http://forum.example.test/plugin.php?id=zqlj_sign&sign=fixtureToken0001',
    'plugin.php?id=zqlj_sign&repair=fixtureToken0001',
    'plugin.php?id=zqlj_sign&timeoffset=8&sign=fixtureToken0001',
    'plugin.php?id=zqlj_sign&sign=fixtureToken0001&repairday=20300411',
    'plugin.php?id=zqlj_sign&sign=one&sign=two',
    'plugin.php?id=zqlj_sign&id=zqlj_sign&sign=fixtureToken0001',
    'plugin.php?id=zqlj_sign&sign=fixtureToken0001&mobile=2',
    'plugin.php?id=zqlj_sign&sign=fixtureToken0001#result',
    'plugin.php?id=zqlj_sign&sign=bad%26repair',
    'javascript:alert(1)',
  ]) {
    test('refuses malformed sign-in link: $href', () {
      expectFailure(
        unsigned.replaceFirst(
          'plugin.php?id=zqlj_sign&amp;sign=fixtureToken0001',
          href.replaceAll('&', '&amp;'),
        ),
        code: 'daily_sign_in_action_invalid',
      );
    });
  }

  test('noncanonical request or redirected response cannot imply unsigned', () {
    expectFailure(
      unsigned,
      requestedUri: Uri.parse(
        'https://forum.example.test/plugin.php?id=zqlj_sign&mobile=2&tb=my',
      ),
      code: 'daily_sign_in_response_uri_invalid',
    );
    expectFailure(
      unsigned,
      sourceUri: Uri.parse('https://forum.example.test/'),
      code: 'daily_sign_in_response_uri_invalid',
    );
    expectFailure(
      unsigned,
      sourceUri: Uri.parse(
        'https://other.example.test/plugin.php?id=zqlj_sign&mobile=2',
      ),
      code: 'daily_sign_in_response_uri_invalid',
    );
  });
}
