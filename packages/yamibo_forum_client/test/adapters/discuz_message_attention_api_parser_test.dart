import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final _origin = Uri.parse('https://forum.example.test');
final _sourceUri = _origin.resolve(
  '/api/mobile/index.php?module=forumindex&version=1&checknotice=1',
);
final _parser = DiscuzMessageAttentionApiParser(siteOrigin: _origin);
const _unknown = ForumMessageAttentionState.unknown;
const _absent = ForumMessageAttentionState.absent;
const _present = ForumMessageAttentionState.present;
const _zeroNotice = <String, Object?>{
  'newpm': '0',
  'newprompt': '0',
  'newmypost': '0',
};

void main() {
  test('extracts the public notice independently from a viewed profile', () {
    final source = jsonDecode(
      File(
        'test/fixtures/message_attention/api/notice.json',
      ).readAsStringSync(encoding: utf8),
    );
    final observation = _parse(source)!;
    expect(observation.viewerUserId, '42');
    expect(observation.source, ForumMessageAttentionSource.api);
    expect(observation.privateMessages, _present);
    expect(observation.notifications, _present);
    expect(observation.notificationCount, 8);
    expect(observation.combinedHint, _unknown);
    expect(observation.combined, _present);
  });

  test('native JSON integers retain the same notice semantics', () {
    final source = _envelope(
      uid: 42,
      notice: {'newpm': 1, 'newprompt': 3, 'newmypost': 5},
    )..['Version'] = 1;
    final observation = _parse(source)!;
    expect(observation.privateMessages, _present);
    expect(observation.notifications, _present);
    expect(observation.notificationCount, 8);
  });

  test('all three complete zero fields prove absence', () {
    final observation = _parse(_envelope())!;
    expect(observation.privateMessages, _absent);
    expect(observation.notifications, _absent);
    expect(observation.notificationCount, 0);
    expect(observation.combined, _absent);
  });

  for (final mask in [1, 2, 3, 8]) {
    test('newpm bit mask $mask expresses a hint without a message count', () {
      final observation = _parse(
        _envelope(notice: {..._zeroNotice, 'newpm': mask}),
      )!;
      expect(observation.privateMessages, _present);
      expect(observation.notifications, _absent);
      expect(observation.notificationCount, 0);
      expect(observation.combined, _present);
    });
  }

  test('post notifications alone are included in the combined hint', () {
    final observation = _parse(
      _envelope(notice: {..._zeroNotice, 'newmypost': '7'}),
    )!;
    expect(observation.privateMessages, _absent);
    expect(observation.notifications, _present);
    expect(observation.notificationCount, 7);
    expect(observation.combined, _present);
  });

  test('a partial zero is not proof that all notifications are absent', () {
    for (final field in ['newprompt', 'newmypost']) {
      final observation = _parse(
        _envelope(notice: {'newpm': '0', field: '0'}),
      )!;
      expect(observation.privateMessages, _absent);
      expect(observation.notifications, _unknown);
      expect(observation.notificationCount, isNull);
      expect(observation.combined, _unknown);
    }
  });

  test(
    'complete notification absence leaves omitted private messages unknown',
    () {
      final observation = _parse(
        _envelope(notice: {'newprompt': '0', 'newmypost': '0'}),
      )!;
      expect(observation.privateMessages, _unknown);
      expect(observation.notifications, _absent);
      expect(observation.notificationCount, 0);
      expect(observation.combined, _unknown);
    },
  );

  for (final positiveField in ['newprompt', 'newmypost']) {
    test('positive $positiveField proves presence without the other field', () {
      final observation = _parse(_envelope(notice: {positiveField: '2'}))!;
      expect(observation.privateMessages, _unknown);
      expect(observation.notifications, _present);
      expect(observation.notificationCount, isNull);
      expect(observation.combined, _present);
    });
  }

  test('newpush neither proves nor prevents the supported attention state', () {
    expect(_parse(_envelope(notice: {'newpush': '1'})), isNull);
    final observation = _parse(
      _envelope(notice: {..._zeroNotice, 'newpush': '1'}),
    )!;
    expect(observation.combined, _absent);
  });

  test('unrecognized or empty notice fields produce no observation', () {
    for (final notice in [
      null,
      <String, Object?>{},
      <String, Object?>{'newpm': 'bad', 'newprompt': '0'},
      <String, Object?>{'unknown': '1'},
      <Object?>[],
      'newpm=0',
    ]) {
      expect(_parse(_envelope(notice: notice)), isNull);
    }
    final source = _envelope();
    (source['Variables']! as Map<String, Object?>).remove('notice');
    expect(_parse(source), isNull);
  });

  test('malformed fields stay unknown without erasing valid neighbors', () {
    final invalid = <Object?>[
      null,
      -1,
      '-1',
      '-0',
      '+1',
      '0x1',
      1.0,
      true,
      false,
      '1e1',
      '1.0',
      '',
      ' 1',
      '1 ',
      '1\n',
      '١',
      '１',
      'NaN',
      <Object?>[],
      <String, Object?>{},
      9007199254740992,
      '9007199254740992',
      '9223372036854775808',
    ];
    for (final field in _zeroNotice.keys) {
      for (final value in invalid) {
        final observation = _parse(
          _envelope(notice: {..._zeroNotice, field: value}),
        )!;
        if (field == 'newpm') {
          expect(observation.privateMessages, _unknown);
          expect(observation.notifications, _absent);
          expect(observation.notificationCount, 0);
        } else {
          expect(observation.privateMessages, _absent);
          expect(observation.notifications, _unknown);
          expect(observation.notificationCount, isNull);
        }
        expect(observation.combined, _unknown);
      }
    }
  });

  test('a positive sibling survives a malformed notification field', () {
    for (final field in ['newprompt', 'newmypost']) {
      final sibling = field == 'newprompt' ? 'newmypost' : 'newprompt';
      final observation = _parse(
        _envelope(notice: {field: 'bad', sibling: '4'}),
      )!;
      expect(observation.notifications, _present);
      expect(observation.notificationCount, isNull);
      expect(observation.combined, _present);
    }
  });

  test(
    'notification sum overflow keeps presence and omits the unsafe count',
    () {
      final observation = _parse(
        _envelope(notice: {'newprompt': '9007199254740991', 'newmypost': '1'}),
      )!;
      expect(observation.notifications, _present);
      expect(observation.notificationCount, isNull);
      expect(observation.combined, _present);
    },
  );

  test('the exact integer boundary remains a valid notification count', () {
    final observation = _parse(
      _envelope(notice: {'newprompt': '9007199254740990', 'newmypost': '1'}),
    )!;
    expect(observation.notificationCount, 9007199254740991);
  });

  test(
    'viewer identity is never inferred from a viewed space or root field',
    () {
      for (final uid in [null, '0', '99']) {
        final source = _envelope(uid: uid)..['member_uid'] = '42';
        (source['Variables']! as Map<String, Object?>)['space'] = {'uid': '42'};
        expect(_parse(source), isNull);
      }
      final source = _envelope();
      (source['Variables']! as Map<String, Object?>).remove('member_uid');
      expect(_parse(source), isNull);
    },
  );

  test('malformed viewer and expected identities are rejected', () {
    for (final uid in <Object?>[
      '',
      '0',
      -1,
      '-1',
      '+42',
      '042',
      '42 ',
      '42\n',
      '0x2a',
      '42&uid=99',
      42.0,
      true,
      <Object?>['42'],
      '9223372036854775808',
    ]) {
      expect(_parse(_envelope(uid: uid)), isNull);
      if (uid is String) {
        expect(_parse(_envelope(), expectedUserId: uid), isNull);
      }
    }
  });

  test('invalid envelope structure never yields a zero snapshot', () {
    for (final source in <Object?>[
      null,
      <Object?>[],
      <String, Object?>{},
      <String, Object?>{'Variables': <Object?>[]},
      <Object?, Object?>{1: 'Variables'},
      <String, Object?>{
        'Variables': <Object?, Object?>{42: 'member_uid'},
      },
      <String, Object?>{
        'Variables': <String, Object?>{
          'member_uid': '42',
          'notice': <Object?, Object?>{1: 0},
        },
      },
      jsonEncode(_envelope()),
    ]) {
      expect(_parse(source), isNull);
    }
  });

  test('business notices and malformed Message shapes are excluded', () {
    for (final message in <Object?>[
      {'messageval': 'fixture_error', 'messagestr': 'Private fixture text'},
      {'messageval': ''},
      <Object?>[],
      '',
      false,
    ]) {
      expect(_parse(_envelope()..['Message'] = message), isNull);
    }
    expect(_parse(_envelope()..['Message'] = <String, Object?>{}), isNotNull);
    expect(_parse(_envelope()..['Message'] = null), isNotNull);
  });

  test('only reviewed passive read modules contribute observations', () {
    for (final module in [
      'forumindex',
      'forumdisplay',
      'viewthread',
      'profile',
      'myfavforum',
      'myfavthread',
      'smiley',
    ]) {
      expect(
        _parse(
          _envelope(),
          uri: _origin.resolve(
            '/api/mobile/index.php?module=$module&version=1',
          ),
        ),
        isNotNull,
      );
    }
    for (final module in [
      'mypm',
      'mynotelist',
      'publicpm',
      'checknewpm',
      'login',
      'logout',
      'register',
      'connect',
      'wechat_clearlogin',
      'sendpm',
      'newthread',
      'favthread',
      'pollvote',
      'unknown',
      '',
    ]) {
      expect(
        _parse(
          _envelope(),
          uri: _origin.resolve(
            '/api/mobile/index.php?module=$module&version=1',
          ),
        ),
        isNull,
      );
    }
  });

  test('foreign, ambiguous, or alternate-dispatch URLs are rejected', () {
    for (final url in [
      'https://other.example.test/api/mobile/index.php?module=forumindex',
      'http://forum.example.test/api/mobile/index.php?module=forumindex',
      'https://forum.example.test:8443/api/mobile/index.php?module=forumindex',
      'https://fixture@forum.example.test/api/mobile/index.php?module=forumindex',
      'https://forum.example.test/forum.php?module=forumindex',
      '/api/mobile/index.php?module=forumindex',
      'https://forum.example.test/api/mobile/index.php',
      'https://forum.example.test/api/mobile/index.php?module=forumindex#fixture',
      'https://forum.example.test/api/mobile/index.php?module=forumindex&module=forumindex',
      'https://forum.example.test/api/mobile/index.php?module=forumindex&version=1&version=1',
      'https://forum.example.test/api/mobile/index.php?module=forumindex&submodule=checkpost',
      'https://forum.example.test/api/mobile/index.php?module=profile&do=notice',
      'https://forum.example.test/api/mobile/index.php?module=profile&mod=spacecp',
      'https://forum.example.test/api/mobile/index.php?module=profile&action=login',
      'https://forum.example.test/api/mobile/index.php?module=forumindex&op=checknewpm',
    ]) {
      expect(_parse(_envelope(), uri: Uri.parse(url)), isNull, reason: url);
    }
  });

  test(
    'known matching API versions are accepted without changing the request',
    () {
      for (final version in ['1', '2', '3', '4']) {
        expect(
          _parse(
            _envelope()..['Version'] = version,
            uri: _origin.resolve(
              '/api/mobile/index.php?module=viewthread&version=$version',
            ),
          ),
          isNotNull,
        );
      }
      final source = _envelope()..remove('Version');
      expect(_parse(source), isNotNull);
      expect(
        _parse(
          _envelope(),
          uri: _origin.resolve('/api/mobile/index.php?module=forumindex'),
        ),
        isNotNull,
      );
    },
  );

  test('future, malformed, and conflicting API versions are excluded', () {
    for (final version in <Object?>[null, '99', '1 ', '+1', 1.0, true, '4']) {
      expect(_parse(_envelope()..['Version'] = version), isNull);
    }
    for (final version in ['99', '+1', '01']) {
      expect(
        _parse(
          _envelope(),
          uri: _origin.resolve(
            '/api/mobile/index.php?module=forumindex&version=$version',
          ),
        ),
        isNull,
      );
    }
  });
}

Map<String, Object?> _envelope({
  Object? uid = '42',
  Object? notice = _zeroNotice,
}) => <String, Object?>{
  'Version': '1',
  'Variables': <String, Object?>{'member_uid': uid, 'notice': notice},
};

ForumMessageAttentionObservation? _parse(
  Object? source, {
  Uri? uri,
  String expectedUserId = '42',
}) => _parser.parse(
  source,
  sourceUri: uri ?? _sourceUri,
  expectedUserId: expectedUserId,
);
