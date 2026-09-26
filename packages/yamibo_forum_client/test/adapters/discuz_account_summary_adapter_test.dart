import 'dart:io';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

final _fixture = File(
  'test/fixtures/account_summary/desktop.html',
).readAsStringSync();
final _origin = Uri.parse('https://forum.example.test');
final _config = ForumClientConfig(
  siteOrigin: _origin,
  apiOrigin: _origin.resolve('/api/mobile/index.php'),
  userAgent: 'fixture-mobile',
  desktopUserAgent: 'fixture-desktop',
);
const _query = CurrentAccountSummaryQuery(userId: '42');

void main() {
  test(
    'standard facade reads one desktop document and exposes distinct counts',
    () async {
      final network = _Network();
      final client = YamiboForumClientBuilder(
        config: _config,
        network: network,
      ).buildStandardClient();
      final result = await client.loadCurrentAccountSummary(_query);
      final data = result.dataOrNull!;
      expect(data.identity.userId, '42');
      expect(data.identity.displayName, 'Fixture & Reader');
      expect(data.groupName, 'Readers & 百合');
      expect(data.groupId, '10');
      expect(
        data.avatarUrl,
        'https://forum.example.test/uc_server/fixture_avatar.jpg',
      );
      expect(data.threadCount, 3);
      expect(data.replyCount, 7);
      expect(data.postCount, isNull);
      expect(data.creditTotal, 123);
      final success = result as _Success;
      expect(
        success.capabilities.supports(CurrentUserProfileCapability.replyCount),
        isTrue,
      );
      expect(
        success.capabilities.supports(CurrentUserProfileCapability.postCount),
        isFalse,
      );
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(success.metadata.freshness, DataReadFreshness.current);
      expect(network.requests, hasLength(1));
      final request = network.requests.single;
      expect(request.uri.path, '/home.php');
      expect(request.uri.queryParameters, {
        'mod': 'space',
        'uid': '42',
        'do': 'profile',
      });
      expect(request.headers['User-Agent'], 'fixture-desktop');
    },
  );

  test(
    'custom source overlay and missing-contract fallback are independent of API',
    () async {
      final network = _Network();
      final custom = ForumClientAdapterFactory(
        config: _config,
        network: network,
      ).createCurrentAccountSummary();
      final client = YamiboForumClientBuilder(config: _config, network: network)
          .buildStandardClient(
            sourceOverrides: ForumClientSourcePlan(
              currentAccountSummary: custom,
            ),
          );
      expect(client.currentAccountSummary, same(custom));
      expect(client.currentUserProfile, isNotNull);
      final missing = YamiboForumClient(
        config: _config,
        network: network,
        sourcePlan: const ForumClientSourcePlan(),
      );
      expect(
        (await missing.loadCurrentAccountSummary(_query)).failureOrNull?.kind,
        DataReadFailureKind.unsupported,
      );
      expect(network.requests, isEmpty);
    },
  );

  test('every cache policy still reads the network', () async {
    final network = _Network();
    final repository = _repository(network);
    for (final policy in CacheLoadPolicy.values) {
      await repository.load(_query, cachePolicy: policy);
    }
    expect(network.requests, hasLength(CacheLoadPolicy.values.length));
  });

  for (final uid in ['', '0', '-1', '42&uid=99']) {
    test('invalid query $uid does not send', () async {
      final network = _Network();
      final result = await _repository(
        network,
      ).load(CurrentAccountSummaryQuery(userId: uid));
      expect(result.failureOrNull?.kind, DataReadFailureKind.business);
      expect(network.requests, isEmpty);
    });
  }

  for (final value in [0, -7]) {
    test('total credits preserve $value', () async {
      final result = await _load(_fixture.replaceAll('123', '$value'));
      expect(result.dataOrNull?.creditTotal, value);
      expect(result.dataOrNull?.replyCount, 7);
    });
  }
  test('zero thread and reply counts are supported values', () async {
    final result = await _load(
      _fixture.replaceAll('主题数 3', '主题数 0').replaceAll('回帖数 7', '回帖数 0'),
    );
    expect(result.dataOrNull?.threadCount, 0);
    expect(result.dataOrNull?.replyCount, 0);
  });
  test('credits without upgrade tooltip still follow template order', () async {
    final result = await _load(
      _fixture.replaceAll('tip="积分 123, 距离下一级还需 77 积分"', ''),
    );
    expect(result.dataOrNull?.creditTotal, 123);
  });
  test('same-title extension with no unit never replaces total', () async {
    expect(
      (await _load(_fixture.replaceAll('91 点', '999'))).dataOrNull?.creditTotal,
      123,
    );
  });

  final absent = <String, (RegExp, CurrentUserProfileCapability)>{
    'thread': (
      RegExp(r'<a href="[^"]*type=thread[^"]*">[^<]*</a>'),
      CurrentUserProfileCapability.threadCount,
    ),
    'reply': (
      RegExp(r'<a href="[^"]*type=reply[^"]*">[^<]*</a>'),
      CurrentUserProfileCapability.replyCount,
    ),
    'group': (
      RegExp(r'<li><em class="xg1">.*?</li>'),
      CurrentUserProfileCapability.groupName,
    ),
    'avatar': (
      RegExp(r'<img[^>]+>'),
      CurrentUserProfileCapability.avatarReference,
    ),
    'credit rows': (
      RegExp(r'<li><em>积分</em>.*?</li>'),
      CurrentUserProfileCapability.creditTotal,
    ),
  };
  for (final entry in absent.entries) {
    test('missing ${entry.key} is unavailable instead of zero', () async {
      final result =
          await _load(_fixture.replaceAll(entry.value.$1, '')) as _Success;
      expect(result.capabilities.supports(entry.value.$2), isFalse);
    });
  }

  final invalid = <String, String>{
    'viewer repeated with invalid value': _fixture.replaceAll(
      '</script>',
      "; discuz_uid = 'invalid';</script>",
    ),
    'viewer mismatch': _fixture.replaceAll(
      "discuz_uid = '42'",
      "discuz_uid = '99'",
    ),
    'viewer missing': _fixture.replaceAll(
      "discuz_uid = '42'",
      "unused_uid = '42'",
    ),
    'viewer repeated': _fixture.replaceAll(
      '</script>',
      "; discuz_uid = '42';</script>",
    ),
    'profile mismatch': _fixture.replaceAll('(UID: 42)', '(UID: 99)'),
    'profile UID missing': _fixture.replaceAll('(UID: 42)', ''),
    'profile UID repeated': _fixture.replaceAll(
      '(UID: 42)</span>',
      '(UID: 42)</span><span class="xw0">(UID: 42)</span>',
    ),
    'mobile root': _fixture.replaceAll('class="u_profile"', 'class="userinfo"'),
    'error page': '<html><div class="alert_error">Fixture error</div></html>',
    'cross-site counts': _fixture.replaceAll(
      'href="home.php?mod=space&amp;uid=42&amp;do=thread',
      'href="https://other.example.test/home.php?mod=space&amp;uid=42&amp;do=thread',
    ),
    'counts UID mismatch': _fixture.replaceAll(
      'uid=42&amp;do=thread',
      'uid=99&amp;do=thread',
    ),
    'counts repeated query': _fixture.replaceAll(
      'type=reply&amp;',
      'type=reply&amp;type=reply&amp;',
    ),
    'counts repeated row': _fixture
        .replaceAll('type=thread', 'type=reply')
        .replaceAll('主题数 3', '回帖数 7'),
    'negative reply': _fixture.replaceAll('回帖数 7', '回帖数 -7'),
    'invalid thread': _fixture.replaceAll('主题数 3', '主题数 unknown'),
    'avatar UID mismatch': _fixture.replaceAll(
      'space-uid-42.html',
      'space-uid-99.html',
    ),
    'credit conflict': _fixture.replaceAll('tip="积分 123', 'tip="积分 124'),
    'invalid total before valid extension': _fixture
        .replaceAll('<em>积分</em>123', '<em>积分</em>invalid')
        .replaceAll('91 点', '91'),
    'missing total cannot use extension': _fixture.replaceAll(
      '<li><em>积分</em>123</li>',
      '',
    ),
  };
  for (final entry in invalid.entries) {
    test('${entry.key} fails closed', () async {
      final result = await _load(entry.value);
      expect(result.dataOrNull, isNull);
      expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      expect(
        result.failureOrNull?.diagnosticMessage,
        isNot(contains(entry.value)),
      );
    });
  }
  test('viewer guest and login forms are unauthorized', () async {
    for (final source in [
      _fixture.replaceAll("discuz_uid = '42'", "discuz_uid = '0'"),
      '<html><form id="loginform"></form></html>',
    ]) {
      expect(
        (await _load(source)).failureOrNull?.kind,
        DataReadFailureKind.unauthorized,
      );
    }
  });
  for (final destination in [
    'https://other.example.test/home.php?mod=space&uid=42&do=profile',
    'https://forum.example.test/home.php?mod=space&uid=99&do=profile',
    'https://forum.example.test/home.php?mod=space&uid=42&do=profile&mobile=2',
    'https://forum.example.test/home.php?mod=space&uid=42&uid=42&do=profile',
    'https://forum.example.test/member.php?mod=logging&action=login',
  ]) {
    test('unexpected final URL $destination is rejected', () async {
      final result = await _repository(
        _Network(uri: Uri.parse(destination)),
      ).load(_query);
      expect(result.dataOrNull, isNull);
      expect(result.failureOrNull, isNotNull);
    });
  }
  for (final failure in [
    ForumTransportFailureKind.network,
    ForumTransportFailureKind.timeout,
  ]) {
    test('$failure remains a structured transport failure', () async {
      final result = await _repository(_Network(failure: failure)).load(_query);
      expect(result.failureOrNull?.kind, toReadFailureKind(failure));
    });
  }
}

typedef _Success =
    DataReadSuccess<CurrentUserProfileData, CurrentUserProfileReadCapabilities>;
typedef _Result =
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>;
Future<_Result> _load(String html) =>
    _repository(_Network(body: html)).load(_query);
CurrentAccountSummaryRepository _repository(_Network network) =>
    ForumClientAdapterFactory(
      config: _config,
      network: network,
    ).createCurrentAccountSummary();

final class _Network implements ForumClientNetwork {
  _Network({String? body, this.uri, this.failure}) : body = body ?? _fixture;
  final String body;
  final Uri? uri;
  final ForumTransportFailureKind? failure;
  final List<ForumRequest> requests = [];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    if (failure case final kind?) {
      return ForumTransportError(
        ForumTransportFailure(kind: kind, code: 'fixture_failure'),
      );
    }
    return ForumTransportSuccess(
      ForumResponse(
        uri: uri ?? request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}
