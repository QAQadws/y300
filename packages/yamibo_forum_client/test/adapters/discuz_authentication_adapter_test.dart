import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  group('Discuz authentication contracts', () {
    test(
      'login uses forumindex formhash, v4 POST, then profile proof',
      () async {
        final network = _AuthenticationNetwork(<_Step>[
          _Step.json(
            module: 'forumindex',
            body: <String, Object?>{
              'Variables': <String, Object?>{'formhash': 'login-formhash'},
            },
          ),
          _Step.json(
            module: 'login',
            method: ForumRequestMethod.post,
            body: <String, Object?>{
              'Variables': <String, Object?>{},
              'Message': <String, Object?>{
                'messageval': 'login_succeed',
                'messagestr': 'ok',
              },
            },
          ),
          _Step.json(
            module: 'profile',
            body: <String, Object?>{
              'Variables': <String, Object?>{
                'member_uid': '42',
                'member_username': 'reader',
                'formhash': 'profile-formhash',
              },
            },
          ),
        ]);
        final cookies = MemoryForumCookieStore();
        final client = _client(network: network, cookies: cookies);

        final result = await client.loginWithPassword(
          const ForumPasswordLoginRequest(
            username: ' reader ',
            password: 'secret-value',
          ),
        );

        expect(result, isA<DataCommandApplied<ForumLoginReceipt>>());
        final receipt =
            (result as DataCommandApplied<ForumLoginReceipt>).receipt;
        expect(receipt.session.userId, '42');
        expect(receipt.session.username, 'reader');
        expect(network.requests.map(_module), <String>[
          'forumindex',
          'login',
          'profile',
        ]);
        final login = network.requests[1];
        expect(login.method, ForumRequestMethod.post);
        expect(login.uri.queryParameters['version'], '4');
        expect(login.uri.queryParameters['action'], 'login');
        expect(
          login.headers['Content-Type'],
          'application/x-www-form-urlencoded',
        );
        expect(login.body, <String, String>{
          'formhash': 'login-formhash',
          'loginsubmit': '1',
          'username': 'reader',
          'password': 'secret-value',
          'loginfield': 'auto',
          'cookietime': '1',
          'questionid': '0',
          'answer': '',
        });
        expect(result.toString(), isNot(contains('secret-value')));
      },
    );

    test('invalid credentials are not sent', () async {
      final network = _AuthenticationNetwork(const <_Step>[]);

      final result =
          await _client(
            network: network,
            cookies: MemoryForumCookieStore(),
          ).loginWithPassword(
            const ForumPasswordLoginRequest(username: ' ', password: ''),
          );

      expect(result, isA<DataCommandNotSent<ForumLoginReceipt>>());
      expect(result.failureOrNull?.kind, DataCommandFailureKind.validation);
      expect(network.requests, isEmpty);
    });

    test('login is unsupported without a Cookie port', () async {
      final network = _AuthenticationNetwork(const <_Step>[]);
      final client = YamiboForumClientBuilder(
        config: _config,
        network: network,
      ).buildStandardClient();

      final result = await client.loginWithPassword(
        const ForumPasswordLoginRequest(
          username: 'reader',
          password: 'secret-value',
        ),
      );

      expect(result, isA<DataCommandUnsupported<ForumLoginReceipt>>());
      expect(network.requests, isEmpty);
    });

    test('explicit login rejection does not request profile', () async {
      final network = _AuthenticationNetwork(<_Step>[
        _Step.json(
          module: 'forumindex',
          body: <String, Object?>{
            'Variables': <String, Object?>{'formhash': 'login-formhash'},
          },
        ),
        _Step.json(
          module: 'login',
          method: ForumRequestMethod.post,
          body: <String, Object?>{
            'Variables': <String, Object?>{},
            'Message': <String, Object?>{
              'messageval': 'login_invalid',
              'messagestr': 'fixture rejection',
            },
          },
        ),
      ]);

      final result =
          await _client(
            network: network,
            cookies: MemoryForumCookieStore(),
          ).loginWithPassword(
            const ForumPasswordLoginRequest(
              username: 'reader',
              password: 'bad',
            ),
          );

      expect(result, isA<DataCommandRejected<ForumLoginReceipt>>());
      expect(network.requests.map(_module), <String>['forumindex', 'login']);
      expect(result.failureOrNull?.code, 'login_invalid');
    });

    test(
      'login transport success with failed profile is outcome unknown',
      () async {
        final cookies = MemoryForumCookieStore();
        await cookies.merge(_config.siteOrigin, const <String, String>{
          'fixture_auth': 'possibly-applied',
        });
        final network = _AuthenticationNetwork(<_Step>[
          _Step.json(
            module: 'forumindex',
            body: <String, Object?>{
              'Variables': <String, Object?>{'formhash': 'login-formhash'},
            },
          ),
          _Step.json(
            module: 'login',
            method: ForumRequestMethod.post,
            body: <String, Object?>{
              'Variables': <String, Object?>{},
              'Message': <String, Object?>{'messageval': 'login_succeed'},
            },
          ),
          _Step.failure(
            module: 'profile',
            failure: const ForumTransportFailure(
              kind: ForumTransportFailureKind.timeout,
              code: 'profile_timeout',
            ),
          ),
        ]);

        final result = await _client(network: network, cookies: cookies)
            .loginWithPassword(
              const ForumPasswordLoginRequest(
                username: 'reader',
                password: 'pass',
              ),
            );

        expect(result, isA<DataCommandOutcomeUnknown<ForumLoginReceipt>>());
        expect(result.failureOrNull?.kind, DataCommandFailureKind.timeout);
        expect(
          await cookies.read(_config.siteOrigin),
          containsPair('fixture_auth', 'possibly-applied'),
        );
      },
    );

    test('login without explicit success proof is outcome unknown', () async {
      final network = _AuthenticationNetwork(<_Step>[
        _Step.json(
          module: 'forumindex',
          body: <String, Object?>{
            'Variables': <String, Object?>{'formhash': 'login-formhash'},
          },
        ),
        _Step.json(
          module: 'login',
          method: ForumRequestMethod.post,
          body: <String, Object?>{'Variables': <String, Object?>{}},
        ),
      ]);

      final result =
          await _client(
            network: network,
            cookies: MemoryForumCookieStore(),
          ).loginWithPassword(
            const ForumPasswordLoginRequest(
              username: 'reader',
              password: 'secret-value',
            ),
          );

      expect(result, isA<DataCommandOutcomeUnknown<ForumLoginReceipt>>());
      expect(result.failureOrNull?.code, 'login_success_unproven');
      expect(network.requests.map(_module), <String>['forumindex', 'login']);
    });

    test(
      'cancelled login stops formhash fallback before command POST',
      () async {
        final cancellation = ForumRequestCancellation();
        final network = _AuthenticationNetwork(<_Step>[
          _Step.callback(
            module: 'forumindex',
            callback: () {
              cancellation.cancel();
              return const ForumTransportError(
                ForumTransportFailure(
                  kind: ForumTransportFailureKind.cancelled,
                  code: 'request_cancelled',
                ),
              );
            },
          ),
        ]);

        final result =
            await _client(
              network: network,
              cookies: MemoryForumCookieStore(),
            ).loginWithPassword(
              ForumPasswordLoginRequest(
                username: 'reader',
                password: 'secret-value',
                cancellation: cancellation,
              ),
            );

        expect(result, isA<DataCommandNotSent<ForumLoginReceipt>>());
        expect(result.failureOrNull?.kind, DataCommandFailureKind.cancelled);
        expect(network.requests.map(_module), <String>['forumindex']);
      },
    );

    test(
      'logout uses only the standard protocol and clears proved session',
      () async {
        final sessions = MemoryForumSessionStore();
        final now = DateTime.now();
        await sessions.merge(
          ForumSessionSnapshot(
            isLoggedIn: true,
            userId: '42',
            username: 'reader',
            formhash: 'logout-formhash',
            updatedAt: now,
            formhashUpdatedAt: now,
            source: 'fixture',
          ),
        );
        final cookies = MemoryForumCookieStore();
        await cookies.merge(_config.siteOrigin, const <String, String>{
          'fixture_auth': 'token',
        });
        final network = _AuthenticationNetwork(<_Step>[
          _Step.json(
            module: 'login',
            body: <String, Object?>{
              'Variables': <String, Object?>{},
              'Message': <String, Object?>{'messageval': 'logout_succeed'},
            },
          ),
        ]);
        final client = _client(
          network: network,
          cookies: cookies,
          sessions: sessions,
        );

        final result = await client.logoutSession();

        expect(result, isA<DataCommandApplied<ForumLogoutReceipt>>());
        expect(network.requests, hasLength(1));
        final request = network.requests.single;
        expect(request.uri.queryParameters['action'], 'logout');
        expect(request.uri.queryParameters['formhash'], 'logout-formhash');
        expect(request.uri.queryParameters, isNot(contains('mlogout')));
        expect(request.uri.queryParameters, isNot(contains('hash')));
        expect(await cookies.read(_config.siteOrigin), isEmpty);
        expect(sessions.readCurrent(), isNull);
      },
    );

    test('inconclusive logout retains Cookie and session projection', () async {
      final sessions = MemoryForumSessionStore();
      final now = DateTime.now();
      await sessions.merge(
        ForumSessionSnapshot(
          isLoggedIn: true,
          userId: '42',
          username: 'reader',
          formhash: 'logout-formhash',
          updatedAt: now,
          formhashUpdatedAt: now,
          source: 'fixture',
        ),
      );
      final cookies = MemoryForumCookieStore();
      await cookies.merge(_config.siteOrigin, const <String, String>{
        'fixture_auth': 'token',
      });
      final network = _AuthenticationNetwork(<_Step>[
        _Step.failure(
          module: 'login',
          failure: const ForumTransportFailure(
            kind: ForumTransportFailureKind.timeout,
            code: 'logout_timeout',
          ),
        ),
      ]);

      final result = await _client(
        network: network,
        cookies: cookies,
        sessions: sessions,
      ).logoutSession();

      expect(result, isA<DataCommandOutcomeUnknown<ForumLogoutReceipt>>());
      expect(await cookies.read(_config.siteOrigin), isNotEmpty);
      expect(sessions.readCurrent()?.userId, '42');
    });

    test('explicitly rejected logout retains Cookie and session', () async {
      final sessions = MemoryForumSessionStore();
      final now = DateTime.now();
      await sessions.merge(
        ForumSessionSnapshot(
          isLoggedIn: true,
          userId: '42',
          username: 'reader',
          formhash: 'logout-formhash',
          updatedAt: now,
          formhashUpdatedAt: now,
          source: 'fixture',
        ),
      );
      final cookies = MemoryForumCookieStore();
      await cookies.merge(_config.siteOrigin, const <String, String>{
        'fixture_auth': 'token',
      });
      final network = _AuthenticationNetwork(<_Step>[
        _Step.json(
          module: 'login',
          body: <String, Object?>{
            'Variables': <String, Object?>{},
            'Message': <String, Object?>{'messageval': 'logout_denied'},
          },
        ),
      ]);

      final result = await _client(
        network: network,
        cookies: cookies,
        sessions: sessions,
      ).logoutSession();

      expect(result, isA<DataCommandRejected<ForumLogoutReceipt>>());
      expect(await cookies.read(_config.siteOrigin), isNotEmpty);
      expect(sessions.readCurrent()?.userId, '42');
      expect(network.requests, hasLength(1));
    });

    test('anonymous profile authoritatively clears the old identity', () async {
      final sessions = MemoryForumSessionStore();
      final old = DateTime.utc(2026, 8, 26, 1);
      await sessions.merge(
        ForumSessionSnapshot(
          isLoggedIn: true,
          userId: '42',
          username: 'reader',
          formhash: 'old-formhash',
          updatedAt: old,
          formhashUpdatedAt: old,
          source: 'fixture',
        ),
      );
      final network = _AuthenticationNetwork(<_Step>[
        _Step.json(
          module: 'profile',
          body: <String, Object?>{
            'Variables': <String, Object?>{
              'member_uid': '0',
              'member_username': '',
              'formhash': 'guest-formhash',
            },
          },
        ),
      ]);

      final result = await _client(
        network: network,
        cookies: MemoryForumCookieStore(),
        sessions: sessions,
      ).resolveSession();

      expect(result, isA<ForumSessionAnonymous>());
      expect(sessions.readCurrent()?.isLoggedIn, isFalse);
      expect(sessions.readCurrent()?.userId, '0');
      expect(sessions.readCurrent()?.username, isEmpty);
      expect(sessions.readCurrent()?.formhash, 'guest-formhash');
    });
  });
}

final _config = ForumClientConfig(
  siteOrigin: Uri.parse('https://bbs.example.invalid'),
  apiOrigin: Uri.parse('https://bbs.example.invalid/api/mobile/index.php'),
  userAgent: 'auth-contract-test',
);

YamiboForumClient _client({
  required ForumClientNetwork network,
  required ForumCookieStore cookies,
  ForumSessionStore? sessions,
}) => YamiboForumClientBuilder(
  config: _config,
  network: network,
  sessionStore: sessions ?? MemoryForumSessionStore(),
  cookieStore: cookies,
).buildStandardClient();

String _module(ForumRequest request) =>
    request.uri.queryParameters['module'] ?? '';

final class _Step {
  const _Step._({
    required this.module,
    required this.method,
    this.body,
    this.failure,
    this.callback,
  });

  factory _Step.json({
    required String module,
    ForumRequestMethod method = ForumRequestMethod.get,
    required Object? body,
  }) => _Step._(module: module, method: method, body: body);

  factory _Step.failure({
    required String module,
    ForumRequestMethod method = ForumRequestMethod.get,
    required ForumTransportFailure failure,
  }) => _Step._(module: module, method: method, failure: failure);

  factory _Step.callback({
    required String module,
    ForumRequestMethod method = ForumRequestMethod.get,
    required ForumTransportResult<ForumResponse<Object?>> Function() callback,
  }) => _Step._(module: module, method: method, callback: callback);

  final String module;
  final ForumRequestMethod method;
  final Object? body;
  final ForumTransportFailure? failure;
  final ForumTransportResult<ForumResponse<Object?>> Function()? callback;
}

final class _AuthenticationNetwork implements ForumClientNetwork {
  _AuthenticationNetwork(this._steps);

  final List<_Step> _steps;
  final List<ForumRequest> requests = <ForumRequest>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    if (_steps.isEmpty) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.unknown,
          code: 'fixture_exhausted',
        ),
      );
    }
    final step = _steps.removeAt(0);
    expect(_module(request), step.module);
    expect(request.method, step.method);
    final callback = step.callback;
    if (callback != null) return callback();
    final failure = step.failure;
    if (failure != null) return ForumTransportError(failure);
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: request.uri,
        statusCode: 200,
        headers: const <String, List<String>>{},
        body: step.body,
      ),
    );
  }
}
