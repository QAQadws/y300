import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yamibo_forum_client/src/adapters/discuz_daily_sign_in_adapter.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';

void main() {
  test('facade preparation shares its read with a single command', () async {
    final harness = _Harness();
    final client = YamiboForumClientBuilder(
      config: harness.config,
      network: harness.network,
    ).buildStandardClient();
    final read = await client.prepareDailySignIn(
      const ForumDailySignInQuery(userId: '42'),
    );
    expect(
      (read
              as DataReadSuccess<
                ForumDailySignInPreparation,
                ForumDailySignInReadCapabilities
              >)
          .metadata
          .origin,
      DataReadOrigin.network,
    );
    expect(read.dataOrNull!.snapshot.status, ForumDailySignInStatus.unsigned);
    final token = read.dataOrNull!.token;
    expect(token.toString(), isNot(contains('fixtureToken')));
    final request = ForumDailySignInRequest(
      userId: '42',
      expectedForumDay: '20300412',
      preparationToken: token,
    );
    expect(
      await client.signInToday(request),
      isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>(),
    );
    expect(
      await client.signInToday(request),
      isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
    );
    expect(harness.network.requests, hasLength(2));
    expect(harness.network.requests.last.allowWafReplay, isFalse);
    expect(harness.network.requests.last.followRedirects, isFalse);
  });

  test('foreign, forged, wrong-UID and wrong-day proofs never send', () async {
    for (final invalidCase in ['foreign', 'forged', 'uid', 'day']) {
      final harness = _Harness();
      var token = await harness.prepare();
      var adapter = harness.adapter;
      if (invalidCase == 'foreign') adapter = harness.makeAdapter();
      if (invalidCase == 'forged') token = _ForgedToken();
      var gateCalls = 0;
      final result = await adapter.execute(
        ForumDailySignInRequest(
          userId: invalidCase == 'uid' ? '43' : '42',
          expectedForumDay: invalidCase == 'day' ? '20300413' : '20300412',
          preparationToken: token,
          beforeSend: (_) async {
            gateCalls++;
            return ForumDailySignInSendAuthorization.allow;
          },
        ),
      );
      expect(
        result,
        isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
        reason: invalidCase,
      );
      expect(gateCalls, 0);
      expect(harness.network.requests, hasLength(1));
    }
  });

  test('expiry is checked before authorization and again after it', () async {
    for (final duringGate in [false, true]) {
      final harness = _Harness();
      final token = await harness.prepare();
      var calls = 0;
      if (!duringGate) harness.timer.advance(const Duration(seconds: 30));
      final result = await harness.adapter.execute(
        ForumDailySignInRequest(
          userId: '42',
          preparationToken: token,
          beforeSend: (_) async {
            calls++;
            harness.timer.advance(const Duration(seconds: 30));
            return ForumDailySignInSendAuthorization.allow;
          },
        ),
      );
      expect(result, isA<DataCommandNotSent<ForumDailySignInReceipt>>());
      expect(calls, duringGate ? 1 : 0);
      expect(harness.network.requests, hasLength(1));
    }
  });

  test('proof is still usable just before its expiry', () async {
    final harness = _Harness();
    final token = await harness.prepare();
    harness.timer.advance(const Duration(milliseconds: 29999));
    expect(
      await harness.adapter.execute(
        ForumDailySignInRequest(userId: '42', preparationToken: token),
      ),
      isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>(),
    );
    expect(harness.network.requests, hasLength(2));
  });

  test(
    'preparation cancellation invalidates the proof across requests',
    () async {
      for (final duringGate in [false, true]) {
        final harness = _Harness();
        final cancellation = ForumRequestCancellation();
        final token = await harness.prepare(cancellation);
        if (!duringGate) cancellation.cancel();
        final result = await harness.adapter.execute(
          ForumDailySignInRequest(
            userId: '42',
            preparationToken: token,
            beforeSend: (_) async {
              cancellation.cancel();
              return ForumDailySignInSendAuthorization.allow;
            },
          ),
        );
        expect(result, isA<DataCommandNotSent<ForumDailySignInReceipt>>());
        expect(harness.network.requests, hasLength(1));
      }
    },
  );

  test(
    'concurrent use claims a proof before waiting for authorization',
    () async {
      final harness = _Harness();
      final token = await harness.prepare();
      final entered = Completer<void>();
      final gate = Completer<ForumDailySignInSendAuthorization>();
      final first = harness.adapter.execute(
        ForumDailySignInRequest(
          userId: '42',
          preparationToken: token,
          beforeSend: (_) {
            entered.complete();
            return gate.future;
          },
        ),
      );
      await entered.future;
      expect(
        await harness.adapter.execute(
          ForumDailySignInRequest(userId: '42', preparationToken: token),
        ),
        isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
      );
      gate.complete(ForumDailySignInSendAuthorization.allow);
      expect(
        await first,
        isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>(),
      );
      expect(harness.network.requests, hasLength(2));
    },
  );

  test('denied authorization consumes the proof without sending', () async {
    final harness = _Harness();
    final token = await harness.prepare();
    await harness.adapter.execute(
      ForumDailySignInRequest(
        userId: '42',
        preparationToken: token,
        beforeSend: (_) async => ForumDailySignInSendAuthorization.suppress,
      ),
    );
    expect(
      await harness.adapter.execute(
        ForumDailySignInRequest(userId: '42', preparationToken: token),
      ),
      isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
    );
    expect(harness.network.requests, hasLength(1));
  });
}

final class _Harness {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://forum.example.test'),
    userAgent: 'test-agent',
  );
  final network = _Network();
  final timer = _Timer();
  late final adapter = makeAdapter();

  DiscuzDailySignInAdapter makeAdapter() => DiscuzDailySignInAdapter(
    config: config,
    network: network,
    requestProfiles: DefaultForumRequestProfileResolver(config),
    createPreparationTimer: () => timer,
  );

  Future<ForumDailySignInPreparationToken> prepare([
    ForumRequestCancellation? cancellation,
  ]) async => (await adapter.prepare(
    ForumDailySignInQuery(userId: '42', cancellation: cancellation),
  )).dataOrNull!.token;
}

final class _Timer extends Stopwatch {
  Duration _elapsed = Duration.zero;

  void advance(Duration duration) => _elapsed += duration;

  @override
  Duration get elapsed => _elapsed;
}

final class _ForgedToken implements ForumDailySignInPreparationToken {}

final class _Network implements ForumClientNetwork {
  final requests = <ForumRequest>[];
  final unsigned = File(
    'test/fixtures/daily_sign_in/unsigned.html',
  ).readAsStringSync(encoding: utf8);

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
        body: request.uri.queryParameters.containsKey('sign')
            ? '<html>synthetic uncalibrated response</html>'
            : unsigned,
      ),
    );
  }
}
