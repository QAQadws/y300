import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/profile/data/daily_sign_in_storage.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_providers.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_storage_providers.dart';
import 'package:y300/features/profile/domain/daily_sign_in_attempt_ledger.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

final _ownerProvider = StateProvider<VerifiedProfileOwner?>(
  (ref) => (uid: '42', revision: 0),
);

void main() {
  test('initialization and owner changes only load local settings', () async {
    final harness = _Harness();
    final container = harness.container();
    addTearDown(container.dispose);
    final controller = container.read(dailySignInControllerProvider.notifier);

    await _until(
      () => container.read(dailySignInControllerProvider).autoEnabled != null,
    );
    expect(harness.repository.reads, 0);
    container.read(_ownerProvider.notifier).state = (uid: '43', revision: 1);
    expect(container.read(dailySignInControllerProvider).owner?.uid, '43');
    await _until(
      () => container.read(dailySignInControllerProvider).autoEnabled != null,
    );
    expect(harness.repository.reads, 0);
    expect(harness.command.requests, isEmpty);

    await controller.refresh();
    expect(harness.repository.reads, 1);
    expect(
      container.read(dailySignInControllerProvider).snapshot?.userId,
      '43',
    );
  });

  test(
    'unknown automatic send is read-only today and pauses tomorrow',
    () async {
      final harness = _Harness();
      final container = harness.container();
      addTearDown(container.dispose);
      final controller = container.read(dailySignInControllerProvider.notifier);

      await controller.triggerAutomatic();
      expect(harness.command.sends, 1);
      expect(
        (await harness.ledger.readCheckpoint('42'))?.state,
        DailySignInAttemptState.unknown,
      );

      final readsAfterFirst = harness.repository.reads;
      await controller.triggerAutomatic();
      expect(harness.repository.reads, greaterThan(readsAfterFirst));
      expect(harness.command.sends, 1);

      harness.repository.forumDay = '20260926';
      await controller.triggerAutomatic();
      expect(harness.command.sends, 1);
      expect(
        container.read(dailySignInControllerProvider).automaticPolicy,
        DailySignInAutomaticPolicy.pausedPreviousDay,
      );

      harness.repository.forumDay = '20260927';
      await controller.triggerAutomatic();
      expect(harness.command.sends, 2);
      expect(harness.command.requests.last.expectedForumDay, '20260927');
    },
  );

  test('manual retry on paused day requires explicit confirmation', () async {
    final harness = _Harness();
    final container = harness.container();
    addTearDown(container.dispose);
    final controller = container.read(dailySignInControllerProvider.notifier);

    await controller.triggerAutomatic();
    harness.repository.forumDay = '20260926';
    await controller.triggerAutomatic();
    await controller.submit();
    expect(harness.command.sends, 1);

    await controller.submit(explicitlyRetryUnknown: true);
    expect(harness.command.sends, 2);
    expect(harness.command.requests.last.expectedForumDay, '20260926');
  });

  test('signed fresh page records status without sending', () async {
    final harness = _Harness();
    harness.repository.status = ForumDailySignInStatus.signed;
    final container = harness.container();
    addTearDown(container.dispose);
    final controller = container.read(dailySignInControllerProvider.notifier);

    await controller.triggerAutomatic();
    expect(harness.repository.reads, 1);
    expect(harness.command.sends, 0);
    expect(
      (await harness.ledger.readCheckpoint('42'))?.state,
      DailySignInAttemptState.confirmedSigned,
    );
  });

  test(
    'disabled automation skips all requests but permits manual actions',
    () async {
      final harness = _Harness();
      final container = harness.container();
      addTearDown(container.dispose);
      final controller = container.read(dailySignInControllerProvider.notifier);

      await controller.setAutomaticEnabled(false);
      await controller.triggerAutomatic();
      expect(harness.repository.reads, 0);
      expect(harness.command.sends, 0);
      await controller.refresh();
      expect(harness.repository.reads, 1);
      await controller.submit();
      expect(harness.command.sends, 1);

      final readsAfterManual = harness.repository.reads;
      await controller.setAutomaticEnabled(true);
      expect(harness.repository.reads, readsAfterManual);
      expect(harness.command.sends, 1);
    },
  );

  test(
    'unreadable automatic preference prevents all automatic requests',
    () async {
      final harness = _Harness();
      harness.store.failReads = true;
      final container = harness.container();
      addTearDown(container.dispose);
      final controller = container.read(dailySignInControllerProvider.notifier);

      await controller.triggerAutomatic();
      expect(harness.repository.reads, 0);
      expect(harness.command.requests, isEmpty);
      expect(
        container.read(dailySignInControllerProvider).settingsUnavailable,
        isTrue,
      );
    },
  );

  test('automatic startup shares an in-flight panel status read', () async {
    final harness = _Harness();
    final pending = Completer<void>();
    harness.repository.beforeRead = () => pending.future;
    harness.repository.status = ForumDailySignInStatus.signed;
    final container = harness.container();
    addTearDown(container.dispose);
    final controller = container.read(dailySignInControllerProvider.notifier);

    final panelRead = controller.refresh();
    final automatic = controller.triggerAutomatic();
    await Future<void>.delayed(Duration.zero);
    expect(harness.repository.reads, 1);
    pending.complete();
    await Future.wait([panelRead, automatic]);
    expect(harness.repository.reads, 1);
    expect(harness.command.requests, isEmpty);
  });

  test(
    'background cancellation during the first read prevents a send',
    () async {
      final harness = _Harness();
      final pending = Completer<void>();
      harness.repository.beforeRead = () => pending.future;
      final container = harness.container();
      addTearDown(container.dispose);
      final controller = container.read(dailySignInControllerProvider.notifier);

      final automatic = controller.triggerAutomatic();
      await _until(() => harness.repository.reads == 1);
      controller.cancelAutomaticPending();
      pending.complete();
      await automatic;
      expect(harness.command.requests, isEmpty);
      expect(await harness.ledger.readCheckpoint('42'), isNull);
    },
  );

  test('failed checkpoint write prevents the command send', () async {
    final harness = _Harness();
    harness.store.failWrites = true;
    final container = harness.container();
    addTearDown(container.dispose);
    final controller = container.read(dailySignInControllerProvider.notifier);

    await controller.triggerAutomatic();
    expect(harness.command.requests, hasLength(1));
    expect(harness.command.sends, 0);
    expect(
      container.read(dailySignInControllerProvider).storageUnavailable,
      isTrue,
    );
  });

  test('proven notSent releases a first attempt for a later trigger', () async {
    final harness = _Harness();
    harness.command.response = _notSent;
    final container = harness.container();
    addTearDown(container.dispose);
    final controller = container.read(dailySignInControllerProvider.notifier);

    await controller.triggerAutomatic();
    expect(harness.command.sends, 1);
    expect(await harness.ledger.readCheckpoint('42'), isNull);
    await controller.triggerAutomatic();
    expect(harness.command.sends, 2);
  });

  test('manual and automatic requests share one in-flight command', () async {
    final harness = _Harness();
    final pending = Completer<DataCommandResult<ForumDailySignInReceipt>>();
    harness.command.onAuthorized = () => pending.future;
    final container = harness.container();
    addTearDown(container.dispose);
    final controller = container.read(dailySignInControllerProvider.notifier);

    final automatic = controller.triggerAutomatic();
    await _until(() => harness.command.sends == 1);
    final manual = controller.submit();
    expect(harness.command.sends, 1);
    pending.complete(_unknown);
    await Future.wait([automatic, manual]);
    expect(harness.command.sends, 1);
  });

  test('late old-owner command cannot change a new owner view', () async {
    final harness = _Harness();
    final oldCommand = Completer<DataCommandResult<ForumDailySignInReceipt>>();
    harness.command.onAuthorized = () => oldCommand.future;
    final container = harness.container();
    addTearDown(container.dispose);
    final controller = container.read(dailySignInControllerProvider.notifier);

    final oldAutomatic = controller.triggerAutomatic();
    await _until(() => harness.command.sends == 1);
    harness.repository.signedUserId = '43';
    container.read(_ownerProvider.notifier).state = (uid: '43', revision: 1);
    final newAutomatic = controller.triggerAutomatic();
    oldCommand.complete(_unknown);
    await Future.wait([oldAutomatic, newAutomatic]);
    final state = container.read(dailySignInControllerProvider);
    expect(state.owner?.uid, '43');
    expect(state.snapshot?.status, ForumDailySignInStatus.signed);
    expect(state.commandResult, isNull);
    expect(harness.command.sends, 1);
  });
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 50 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}

const _unknown = DataCommandOutcomeUnknown<ForumDailySignInReceipt>(
  DataCommandFailure(
    kind: DataCommandFailureKind.parse,
    retryPolicy: DataCommandRetryPolicy.explicitOnly,
    code: 'synthetic_unknown',
    diagnosticMessage: 'synthetic_unknown',
  ),
);

const _notSent = DataCommandNotSent<ForumDailySignInReceipt>(
  DataCommandFailure(
    kind: DataCommandFailureKind.cancelled,
    retryPolicy: DataCommandRetryPolicy.explicitOnly,
    code: 'synthetic_not_sent',
    diagnosticMessage: 'synthetic_not_sent',
  ),
);

final class _Harness {
  final store = _MemoryStore();
  final repository = _Repository();
  final command = _Command();
  late final ledger = SharedPreferencesDailySignInAttemptLedger(store);
  late final settings = SharedPreferencesDailyAutoSignInSettings(store);

  ProviderContainer container() => ProviderContainer(
    overrides: [
      verifiedProfileOwnerProvider.overrideWith(
        (ref) => ref.watch(_ownerProvider),
      ),
      dailySignInRepositoryProvider.overrideWithValue(repository),
      dailySignInCommandProvider.overrideWithValue(command),
      dailySignInAttemptLedgerProvider.overrideWithValue(ledger),
      dailyAutoSignInSettingsProvider.overrideWithValue(settings),
    ],
  );
}

final class _Repository implements ForumDailySignInRepository {
  String forumDay = '20260925';
  ForumDailySignInStatus status = ForumDailySignInStatus.unsigned;
  String? signedUserId;
  int reads = 0;
  Future<void> Function()? beforeRead;

  @override
  ForumDailySignInSourceCapabilities get capabilities =>
      ForumDailySignInSourceCapabilities(
        values: DataCapabilitySet.supported(
          ForumDailySignInReadCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<ForumDailySignInSnapshot, ForumDailySignInReadCapabilities>
  >
  load(ForumDailySignInQuery query) async {
    reads++;
    await beforeRead?.call();
    return DataReadSuccess(
      data: ForumDailySignInSnapshot(
        userId: query.userId,
        forumDay: forumDay,
        status: query.userId == signedUserId
            ? ForumDailySignInStatus.signed
            : status,
      ),
      capabilities: ForumDailySignInReadCapabilities(
        values: DataCapabilitySet.supported(
          ForumDailySignInReadCapability.values,
        ),
      ),
      metadata: const DataReadMetadata.network(),
    );
  }
}

final class _Command implements ForumDailySignInCommand {
  final requests = <ForumDailySignInRequest>[];
  int sends = 0;
  DataCommandResult<ForumDailySignInReceipt> response = _unknown;
  Future<DataCommandResult<ForumDailySignInReceipt>> Function()? onAuthorized;

  @override
  ForumDailySignInCommandCapabilities get capabilities =>
      ForumDailySignInCommandCapabilities(
        values: DataCapabilitySet.supported(
          ForumDailySignInCommandCapability.values,
        ),
      );

  @override
  Future<DataCommandResult<ForumDailySignInReceipt>> execute(
    ForumDailySignInRequest request,
  ) async {
    requests.add(request);
    final authorization = await request.beforeSend!(
      ForumDailySignInPreparedAttempt(
        userId: request.userId,
        forumDay: request.expectedForumDay!,
      ),
    );
    if (authorization != ForumDailySignInSendAuthorization.allow ||
        (request.cancellation?.isCancelled ?? false)) {
      return _notSent;
    }
    sends++;
    return await onAuthorized?.call() ?? response;
  }
}

final class _MemoryStore implements PreferencesStore {
  final values = <String, Object>{};
  bool failWrites = false;
  bool failReads = false;

  @override
  Future<T?> read<T extends Object>(PreferenceKey<T> key) async {
    if (failReads) throw StateError('synthetic storage failure');
    final value = values[key.name];
    return value is T ? value : null;
  }

  @override
  Future<bool> contains<T extends Object>(PreferenceKey<T> key) async {
    if (failReads) throw StateError('synthetic storage failure');
    return values.containsKey(key.name);
  }

  @override
  Future<void> write<T extends Object>(PreferenceKey<T> key, T value) async {
    if (failWrites) throw StateError('synthetic storage failure');
    values[key.name] = value;
  }

  @override
  Future<void> remove<T extends Object>(PreferenceKey<T> key) async {
    values.remove(key.name);
  }
}
