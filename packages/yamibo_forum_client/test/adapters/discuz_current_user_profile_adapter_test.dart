import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  test(
    'profile API exposes a structured summary in one network read',
    () async {
      final harness = _Harness(
        space: const {
          // Discuz removes groupid from this nested user-group cache entry.
          'group': {'grouptitle': 'Fixture readers'},
        },
      );

      final result = await harness.load();
      final success = result as _Success;

      expect(success.data.identity.userId, '42');
      expect(success.data.identity.displayName, 'Fixture reader');
      expect(success.data.avatarUrl, 'https://example.test/avatar.png');
      expect(success.data.groupId, '10');
      expect(success.data.groupName, 'Fixture readers');
      expect(success.data.creditTotal, 12);
      expect(success.data.replyCount, isNull);
      expect(
        success.capabilities.supports(CurrentUserProfileCapability.replyCount),
        isFalse,
      );
      expect(
        success.capabilities.supports(CurrentUserProfileCapability.groupName),
        isTrue,
      );
      expect(success.metadata.origin, DataReadOrigin.network);
      expect(success.metadata.freshness, DataReadFreshness.current);
      expect(harness.network.requests, hasLength(1));
      expect(harness.network.requests.single.uri.queryParameters, {
        'module': 'profile',
        'version': '4',
      });
    },
  );

  test('group title markup and HTML entities become plain text', () async {
    final harness = _Harness(
      space: const {
        'group': {
          'grouptitle':
              ' <font color="#ff6600">Readers &amp; '
              '&#x767E;&#x5408;</font> ',
        },
      },
    );

    final result = await harness.load();

    expect(result.dataOrNull?.groupName, 'Readers & 百合');
  });

  final absentGroups = <String, Map<String, Object?>>{
    'missing group': {},
    'null group': {'group': null},
    'missing group title': {'group': <String, Object?>{}},
    'null group title': {
      'group': {'grouptitle': null},
    },
    'blank group title': {
      'group': {'grouptitle': ' \t\n '},
    },
    'empty markup': {
      'group': {'grouptitle': '<font color="red">&nbsp;</font>'},
    },
  };
  for (final entry in absentGroups.entries) {
    test('${entry.key} leaves group name unsupported', () async {
      final result = await _Harness(space: entry.value).load();
      final success = result as _Success;

      expect(success.data.groupName, isNull);
      expect(
        success.capabilities.supports(CurrentUserProfileCapability.groupName),
        isFalse,
      );
      expect(success.data.creditTotal, 12);
    });
  }

  final malformedGroups = <String, Object?>{
    'scalar group': 'readers',
    'list group': <Object?>[],
    'numeric group title': {'grouptitle': 42},
    'boolean group title': {'grouptitle': true},
    'nested group title': {'grouptitle': <String, Object?>{}},
    'list group title': {'grouptitle': <Object?>[]},
  };
  for (final entry in malformedGroups.entries) {
    test('${entry.key} fails instead of displaying a coerced value', () async {
      final result = await _Harness(space: {'group': entry.value}).load();

      expect(result.dataOrNull, isNull);
      expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
      expect(result.failureOrNull?.code, 'current_user_profile_parse_failed');
    });
  }

  for (final credits in <Object>[0, '0', -7, '-7']) {
    test(
      'credit total preserves signed value $credits (${credits.runtimeType})',
      () async {
        final result = await _Harness(space: {'credits': credits}).load();
        final success = result as _Success;

        expect(success.data.creditTotal, int.parse(credits.toString()));
        expect(
          success.capabilities.supports(
            CurrentUserProfileCapability.creditTotal,
          ),
          isTrue,
        );
      },
    );
  }

  test('missing optional credit total does not become zero', () async {
    final result = await _Harness(space: {'credits': null}).load();
    final success = result as _Success;

    expect(success.data.creditTotal, isNull);
    expect(
      success.capabilities.supports(CurrentUserProfileCapability.creditTotal),
      isFalse,
    );
  });

  test('invalid credit total continues to fail closed', () async {
    final result = await _Harness(space: {'credits': '12 points'}).load();

    expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
    expect(result.dataOrNull, isNull);
  });

  test('guest response remains unauthorized even with group data', () async {
    final result = await _Harness(
      variables: {'member_uid': '0'},
      space: {
        'uid': '0',
        'group': {'grouptitle': 'Guest'},
      },
    ).load();

    expect(result.failureOrNull?.kind, DataReadFailureKind.unauthorized);
    expect(result.dataOrNull, isNull);
  });

  for (final mismatch in <Map<String, Object?>>[
    {'uid': '99'},
    {'username': 'Different reader'},
  ]) {
    test(
      'inconsistent profile identity $mismatch cannot produce a summary',
      () async {
        final result = await _Harness(space: mismatch).load();

        expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
        expect(result.dataOrNull, isNull);
      },
    );
  }
}

typedef _Success =
    DataReadSuccess<CurrentUserProfileData, CurrentUserProfileReadCapabilities>;

final class _Harness {
  _Harness({
    Map<String, Object?> variables = const {},
    Map<String, Object?> space = const {},
  }) : network = _ProfileNetwork({
         'Variables': {
           'member_uid': '42',
           'member_username': 'Fixture reader',
           'member_avatar': 'https://example.test/avatar.png',
           'groupid': '10',
           ...variables,
           'space': {
             'uid': '42',
             'username': 'Fixture reader',
             'credits': '12',
             ...space,
           },
         },
       });

  final _ProfileNetwork network;

  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  load() => ForumClientAdapterFactory(
    config: ForumClientConfig(
      siteOrigin: Uri.parse('https://example.test'),
      apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
      userAgent: 'profile-test',
      desktopUserAgent: 'profile-test',
    ),
    network: network,
  ).createCurrentUserProfile().load(const CurrentUserProfileQuery());
}

final class _ProfileNetwork implements ForumClientNetwork {
  _ProfileNetwork(this.body);

  final Map<String, Object?> body;
  final List<ForumRequest> requests = [];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    return ForumTransportSuccess(
      ForumResponse(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}
