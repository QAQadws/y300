import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/profile/data/daily_sign_in_storage.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_storage_providers.dart';
import 'package:y300/features/profile/domain/daily_sign_in_attempt_ledger.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

final _owner = StateProvider<VerifiedProfileOwner?>(
  (ref) => (uid: '42', revision: 0),
);

void main() {
  for (final signed in [false, true]) {
    test(
      'automatic round uses three HTTP requests; readback signed=$signed',
      () async {
        final h = _Harness();
        h.network.signedAfterSend = signed;
        await h.controller.triggerAutomatic();
        expect(h.network.operations, ['read', 'submit', 'read']);
        expect(
          h.state.commandResult,
          isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>(),
        );
        expect(
          h.state.snapshot?.status,
          signed
              ? ForumDailySignInStatus.signed
              : ForumDailySignInStatus.unsigned,
        );
        expect(
          (await h.ledger.readCheckpoint('42'))?.state,
          signed
              ? DailySignInAttemptState.confirmedSigned
              : DailySignInAttemptState.unknown,
        );
        expect(h.state.isSubmitting, isFalse);
        final submit = h.network.requests[1];
        expect(submit.followRedirects, isFalse);
        expect(submit.allowWafReplay, isFalse);
      },
    );
  }

  test('signed preparation ends after one read', () async {
    final h = _Harness();
    h.network.page = _signed;
    await h.controller.triggerAutomatic();
    expect(h.network.operations, ['read']);
    expect(
      (await h.ledger.readCheckpoint('42'))?.state,
      DailySignInAttemptState.confirmedSigned,
    );
  });

  for (final day in ['20300412', '20300411']) {
    test('unresolved checkpoint on $day allows only one read', () async {
      final h = _Harness();
      final reservation = await h.ledger.reserve(userId: '42', forumDay: day);
      await h.ledger.markUnknown(reservation!);
      await h.controller.triggerAutomatic();
      expect(h.network.operations, ['read']);
      expect(h.state.needsExplicitRetry, isTrue);
    });
  }

  test('disabled automation makes no request', () async {
    final h = _Harness();
    await h.settings.setEnabled('42', false);
    await h.controller.triggerAutomatic();
    expect(h.network.requests, isEmpty);
  });

  for (final page in [
    '<html>error</html>',
    _unsigned.replaceFirst("discuz_uid = '42'", "discuz_uid = '43'"),
  ]) {
    test('untrusted preparation does not submit or read again', () async {
      final h = _Harness();
      h.network.page = page;
      await h.controller.triggerAutomatic();
      expect(h.network.operations, ['read']);
      expect(h.state.readFailure, isNotNull);
    });
  }

  for (final status in [302, 405, 0]) {
    test(
      'submit status $status stays unknown with exactly one readback',
      () async {
        final h = _Harness();
        h.network.submitStatus = status;
        await h.controller.triggerAutomatic();
        expect(h.network.operations, ['read', 'submit', 'read']);
        expect(
          h.state.commandResult,
          isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>(),
        );
      },
    );
  }

  test('panel read and automatic preparation share one request', () async {
    final h = _Harness();
    final entered = Completer<void>();
    final release = Completer<void>();
    h.network.beforeResponse = (_, index) async {
      if (index == 0) {
        entered.complete();
        await release.future;
      }
    };
    final panel = h.controller.refresh();
    await entered.future;
    final automatic = h.controller.triggerAutomatic();
    await Future<void>.delayed(Duration.zero);
    expect(h.network.operations, ['read']);
    release.complete();
    await Future.wait([panel, automatic]);
    expect(h.network.operations, ['read', 'submit', 'read']);
  });

  test('readback holds the flight for concurrent refresh and submit', () async {
    final h = _Harness();
    final entered = Completer<void>();
    final release = Completer<void>();
    h.network.beforeResponse = (_, index) async {
      if (index == 2) {
        entered.complete();
        await release.future;
      }
    };
    final automatic = h.controller.triggerAutomatic();
    await entered.future;
    expect(h.state.isSubmitting, isTrue);
    final refresh = h.controller.refresh();
    final manual = h.controller.submit();
    final again = h.controller.triggerAutomatic();
    release.complete();
    await Future.wait([automatic, refresh, manual, again]);
    expect(h.network.operations, ['read', 'submit', 'read']);
    expect(h.state.isSubmitting, isFalse);
  });

  test(
    'manual click prepares again and an automatic arrival joins it',
    () async {
      final h = _Harness();
      await h.controller.refresh();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.network.beforeResponse = (_, index) async {
        if (index == 1) {
          entered.complete();
          await release.future;
        }
      };
      final manual = h.controller.submit();
      await entered.future;
      final automatic = h.controller.triggerAutomatic();
      release.complete();
      await Future.wait([manual, automatic]);
      expect(h.network.operations, ['read', 'read', 'submit', 'read']);
    },
  );

  for (final changedDay in [false, true]) {
    test(
      'manual fresh page signed/day-changed stops without extra read ($changedDay)',
      () async {
        final h = _Harness();
        await h.controller.refresh();
        h.network.page = changedDay ? _nextDay(_unsigned) : _signed;
        await h.controller.submit();
        expect(h.network.operations, ['read', 'read']);
        expect(
          h.state.commandResult,
          isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
        );
        expect(
          h.state.snapshot?.forumDay,
          changedDay ? '20300413' : '20300412',
        );
        if (changedDay) {
          expect(
            h.state.commandResult?.failureOrNull?.code,
            'daily_sign_in_forum_day_changed',
          );
        }
      },
    );
  }

  test('checkpoint persistence failure prevents send and readback', () async {
    final h = _Harness();
    h.store.failWrites = true;
    await h.controller.triggerAutomatic();
    expect(h.network.operations, ['read']);
    expect(
      h.state.commandResult,
      isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
    );
    expect(h.state.storageUnavailable, isTrue);
  });

  test(
    'manual preparation failure never sends or performs a readback',
    () async {
      final h = _Harness();
      await h.controller.refresh();
      h.network.page = '<html>error</html>';
      await h.controller.submit();
      expect(h.network.operations, ['read', 'read']);
      expect(
        h.state.commandResult,
        isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
      );
      expect(h.state.readFailure, isNotNull);
    },
  );

  test(
    'failed readback retains unknown checkpoint without another request',
    () async {
      final h = _Harness();
      h.network.beforeResponse = (_, index) async {
        if (index == 1) h.network.page = '<html>error</html>';
      };
      await h.controller.triggerAutomatic();
      expect(h.network.operations, ['read', 'submit', 'read']);
      expect(
        h.state.commandResult,
        isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>(),
      );
      expect(h.state.readFailure, isNotNull);
      expect(
        (await h.ledger.readCheckpoint('42'))?.state,
        DailySignInAttemptState.unknown,
      );
    },
  );

  test(
    'cancelling while persisting pending releases only this reservation',
    () async {
      final h = _Harness();
      h.store.beforeWrite = h.controller.cancelAutomaticPending;
      await h.controller.triggerAutomatic();
      expect(h.network.operations, ['read']);
      expect(
        h.state.commandResult,
        isA<DataCommandNotSent<ForumDailySignInReceipt>>(),
      );
      expect(await h.ledger.readCheckpoint('42'), isNull);
    },
  );

  for (final duringSubmit in [false, true]) {
    test(
      'background cancellation stops remaining work ($duringSubmit)',
      () async {
        final h = _Harness();
        h.network.beforeResponse = (_, index) async {
          if (index == (duringSubmit ? 1 : 0)) {
            h.controller.cancelAutomaticPending();
          }
        };
        await h.controller.triggerAutomatic();
        expect(
          h.network.operations,
          duringSubmit ? ['read', 'submit'] : ['read'],
        );
        expect(
          (await h.ledger.readCheckpoint('42'))?.state,
          duringSubmit ? DailySignInAttemptState.unknown : null,
        );
      },
    );
  }

  for (final nextOwner in <VerifiedProfileOwner?>[
    null,
    (uid: '43', revision: 1),
    (uid: '42', revision: 1),
  ]) {
    test('owner change invalidates the first preparation $nextOwner', () async {
      final h = _Harness();
      h.network.beforeResponse = (_, index) async {
        if (index == 0) {
          h.container.read(_owner.notifier).state = nextOwner;
          expect(h.state.owner, nextOwner);
        }
      };
      await h.controller.triggerAutomatic();
      expect(h.network.operations, ['read']);
      expect(h.state.snapshot, isNull);
      expect(await h.ledger.readCheckpoint('42'), isNull);
    });

    test('late readback cannot update changed owner $nextOwner', () async {
      final h = _Harness();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.network.beforeResponse = (_, index) async {
        if (index == 2) {
          entered.complete();
          await release.future;
        }
      };
      final automatic = h.controller.triggerAutomatic();
      await entered.future;
      h.container.read(_owner.notifier).state = nextOwner;
      expect(h.state.owner, nextOwner);
      if (nextOwner?.uid == '42') {
        h.network.page = '<html>new session error</html>';
      }
      release.complete();
      await automatic;
      expect(h.state.snapshot, isNull);
      expect(h.state.commandResult, isNull);
      expect(
        (await h.ledger.readCheckpoint('42'))?.state,
        DailySignInAttemptState.unknown,
      );
    });
  }

  test(
    'cross-day readback does not resubmit or confirm the old attempt',
    () async {
      final h = _Harness();
      h.network.beforeResponse = (_, index) async {
        if (index == 1) h.network.page = _nextDay(_unsigned);
      };
      await h.controller.triggerAutomatic();
      expect(h.network.operations, ['read', 'submit', 'read']);
      expect(
        h.state.commandResult,
        isA<DataCommandOutcomeUnknown<ForumDailySignInReceipt>>(),
      );
      expect(
        h.state.automaticPolicy,
        DailySignInAutomaticPolicy.pausedPreviousDay,
      );
    },
  );
}

String _fixture(String name) => File(
  'packages/yamibo_forum_client/test/fixtures/daily_sign_in/$name.html',
).readAsStringSync(encoding: utf8);

final _unsigned = _fixture('unsigned');
final _signed = _fixture('signed');

String _nextDay(String page) => page
    .replaceFirst('2030年04月12日', '2030年04月13日')
    .replaceFirst('class="day today">12', 'class="day today">13');

final class _Harness {
  _Harness() {
    addTearDown(() => container.dispose());
  }

  final network = _Network();
  final store = _Store();
  late final ledger = SharedPreferencesDailySignInAttemptLedger(store);
  late final settings = SharedPreferencesDailyAutoSignInSettings(store);
  late final client = YamiboForumClientBuilder(
    config: ForumClientConfig(
      siteOrigin: Uri.parse('https://forum.example.test'),
      userAgent: 'test-agent',
    ),
    network: network,
  ).buildStandardClient();
  late final container = ProviderContainer(
    overrides: [
      yamiboForumClientProvider.overrideWithValue(client),
      verifiedProfileOwnerProvider.overrideWith((ref) => ref.watch(_owner)),
      dailySignInAttemptLedgerProvider.overrideWithValue(ledger),
      dailyAutoSignInSettingsProvider.overrideWithValue(settings),
    ],
  );
  DailySignInController get controller =>
      container.read(dailySignInControllerProvider.notifier);
  DailySignInViewState get state =>
      container.read(dailySignInControllerProvider);
}

final class _Network implements ForumClientNetwork {
  final requests = <ForumRequest>[];
  List<String> get operations => requests
      .map(
        (request) =>
            request.uri.queryParameters.containsKey('sign') ? 'submit' : 'read',
      )
      .toList();
  String page = _unsigned;
  bool signedAfterSend = false;
  int submitStatus = 200;
  bool _sent = false;
  Future<void> Function(ForumRequest, int)? beforeResponse;

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    final index = requests.length;
    requests.add(request);
    final submitting = request.uri.queryParameters.containsKey('sign');
    final body = submitting
        ? '<html>synthetic response</html>'
        : (_sent && signedAfterSend ? _signed : page);
    await beforeResponse?.call(request, index);
    if (submitting) _sent = true;
    if (submitting && submitStatus == 0) {
      return const ForumTransportError(
        ForumTransportFailure(
          kind: ForumTransportFailureKind.timeout,
          code: 'synthetic_timeout',
        ),
      );
    }
    return ForumTransportSuccess(
      ForumResponse(
        uri: request.uri,
        statusCode: submitting ? submitStatus : 200,
        headers: const {},
        body: body,
      ),
    );
  }
}

final class _Store implements PreferencesStore {
  final values = <String, Object>{};
  bool failWrites = false;
  void Function()? beforeWrite;

  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async =>
      values[key.name] as T?;

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async =>
      values.containsKey(key.name);

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    beforeWrite?.call();
    if (failWrites) throw StateError('synthetic failure');
    values[key.name] = value;
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async =>
      values.remove(key.name);
}
