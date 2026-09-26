import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_providers.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_storage_providers.dart';
import 'package:y300/features/profile/domain/daily_sign_in_attempt_ledger.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

const _unchanged = Object();

/// The snapshot belongs to one verified session. The durable attempt record
/// belongs to the UID and therefore survives logout and process restart.
final class DailySignInViewState {
  const DailySignInViewState({
    this.owner,
    this.snapshot,
    this.readFailure,
    this.commandResult,
    this.attemptForumDay,
    this.automaticPolicy,
    this.checkpointState,
    this.autoEnabled,
    this.requiresExplicitRetry = false,
    this.isLoading = false,
    this.isSubmitting = false,
    this.isSavingAutoPreference = false,
    this.settingsUnavailable = false,
    this.checkpointUnavailable = false,
  });

  final VerifiedProfileOwner? owner;
  final ForumDailySignInSnapshot? snapshot;
  final DataReadFailure<
    ForumDailySignInSnapshot,
    ForumDailySignInReadCapabilities
  >?
  readFailure;
  final DataCommandResult<ForumDailySignInReceipt>? commandResult;
  final String? attemptForumDay;
  final DailySignInAutomaticPolicy? automaticPolicy;
  final DailySignInAttemptState? checkpointState;
  final bool? autoEnabled;
  final bool requiresExplicitRetry;
  final bool isLoading;
  final bool isSubmitting;
  final bool isSavingAutoPreference;
  final bool settingsUnavailable;
  final bool checkpointUnavailable;

  bool get storageUnavailable => settingsUnavailable || checkpointUnavailable;

  // A fresh forum date can release an older uncertain command after the
  // one-day pause. The previous command result alone cannot block forever.
  bool get needsExplicitRetry => requiresExplicitRetry;

  DailySignInViewState copyWith({
    Object? owner = _unchanged,
    Object? snapshot = _unchanged,
    Object? readFailure = _unchanged,
    Object? commandResult = _unchanged,
    Object? attemptForumDay = _unchanged,
    Object? automaticPolicy = _unchanged,
    Object? checkpointState = _unchanged,
    Object? autoEnabled = _unchanged,
    bool? requiresExplicitRetry,
    bool? isLoading,
    bool? isSubmitting,
    bool? isSavingAutoPreference,
    bool? settingsUnavailable,
    bool? checkpointUnavailable,
  }) => DailySignInViewState(
    owner: identical(owner, _unchanged)
        ? this.owner
        : owner as VerifiedProfileOwner?,
    snapshot: identical(snapshot, _unchanged)
        ? this.snapshot
        : snapshot as ForumDailySignInSnapshot?,
    readFailure: identical(readFailure, _unchanged)
        ? this.readFailure
        : readFailure
              as DataReadFailure<
                ForumDailySignInSnapshot,
                ForumDailySignInReadCapabilities
              >?,
    commandResult: identical(commandResult, _unchanged)
        ? this.commandResult
        : commandResult as DataCommandResult<ForumDailySignInReceipt>?,
    attemptForumDay: identical(attemptForumDay, _unchanged)
        ? this.attemptForumDay
        : attemptForumDay as String?,
    automaticPolicy: identical(automaticPolicy, _unchanged)
        ? this.automaticPolicy
        : automaticPolicy as DailySignInAutomaticPolicy?,
    checkpointState: identical(checkpointState, _unchanged)
        ? this.checkpointState
        : checkpointState as DailySignInAttemptState?,
    autoEnabled: identical(autoEnabled, _unchanged)
        ? this.autoEnabled
        : autoEnabled as bool?,
    requiresExplicitRetry: requiresExplicitRetry ?? this.requiresExplicitRetry,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    isSavingAutoPreference:
        isSavingAutoPreference ?? this.isSavingAutoPreference,
    settingsUnavailable: settingsUnavailable ?? this.settingsUnavailable,
    checkpointUnavailable: checkpointUnavailable ?? this.checkpointUnavailable,
  );
}

final dailySignInControllerProvider =
    NotifierProvider<DailySignInController, DailySignInViewState>(
      DailySignInController.new,
    );

/// Shared coordinator for the native panel and startup automation.
class DailySignInController extends Notifier<DailySignInViewState> {
  int _generation = 0;
  int _automaticEpoch = 0;
  Future<void>? _readFlight;
  Future<void>? _submitFlight;
  String? _submitFlightUid;
  Future<void>? _automaticFlight;
  VerifiedProfileOwner? _automaticFlightOwner;
  bool _submittingAutomatically = false;
  ForumRequestCancellation? _readCancellation;
  ForumRequestCancellation? _submitCancellation;

  @override
  DailySignInViewState build() {
    final owner = ref.watch(verifiedProfileOwnerProvider);
    _generation++;
    _automaticEpoch++;
    _readCancellation?.cancel();
    _submitCancellation?.cancel();
    _readFlight = null;
    ref.onDispose(() {
      _generation++;
      _automaticEpoch++;
      _readCancellation?.cancel();
      _submitCancellation?.cancel();
    });
    if (owner != null) {
      final generation = _generation;
      unawaited(
        Future<void>.microtask(() async {
          if (!_isCurrent(owner, generation)) return;
          await _loadAutoPreference(owner, generation);
        }),
      );
    }
    return DailySignInViewState(
      owner: owner,
      isSubmitting:
          owner != null &&
          _submitFlight != null &&
          _submitFlightUid == owner.uid,
    );
  }

  Future<void> _loadAutoPreference(
    VerifiedProfileOwner owner,
    int generation,
  ) async {
    try {
      final enabled = await ref
          .read(dailyAutoSignInSettingsProvider)
          .isEnabled(owner.uid);
      if (_isCurrent(owner, generation)) {
        state = state.copyWith(
          autoEnabled: enabled,
          settingsUnavailable: false,
        );
      }
    } on Object {
      if (_isCurrent(owner, generation)) {
        state = state.copyWith(autoEnabled: null, settingsUnavailable: true);
      }
    }
  }

  Future<void> setAutomaticEnabled(bool enabled) async {
    final owner = state.owner;
    if (owner == null || state.isSavingAutoPreference) return;
    if (!enabled) cancelAutomaticPending();
    final generation = _generation;
    final previous = state.autoEnabled;
    state = state.copyWith(autoEnabled: enabled, isSavingAutoPreference: true);
    try {
      await ref
          .read(dailyAutoSignInSettingsProvider)
          .setEnabled(owner.uid, enabled);
      if (_isCurrent(owner, generation)) {
        state = state.copyWith(
          isSavingAutoPreference: false,
          settingsUnavailable: false,
        );
      }
    } on Object {
      if (_isCurrent(owner, generation)) {
        state = state.copyWith(
          autoEnabled: previous,
          isSavingAutoPreference: false,
          settingsUnavailable: true,
        );
      }
    }
  }

  Future<void> ensureLoaded() async {
    if (state.owner == null ||
        state.snapshot != null ||
        state.readFailure != null) {
      return;
    }
    await refresh();
  }

  /// Explicit refreshes and startup checks share a network-only read.
  Future<void> refresh() {
    final owner = state.owner;
    if (owner == null) return Future<void>.value();
    if (state.isSubmitting) return _submitFlight ?? Future<void>.value();
    if (_readFlight != null) return _readFlight!;
    final future = _load(owner, _generation);
    _readFlight = future;
    return future.whenComplete(() {
      if (identical(_readFlight, future)) _readFlight = null;
    });
  }

  Future<void> _load(VerifiedProfileOwner owner, int generation) async {
    final previous = state;
    final cancellation = ForumRequestCancellation();
    _readCancellation = cancellation;
    state = state.copyWith(snapshot: null, readFailure: null, isLoading: true);
    late final DataReadResult<
      ForumDailySignInSnapshot,
      ForumDailySignInReadCapabilities
    >
    result;
    try {
      result = await ref
          .read(dailySignInRepositoryProvider)
          .load(
            ForumDailySignInQuery(
              userId: owner.uid,
              cancellation: cancellation,
            ),
          );
    } on Object {
      result = const DataReadFailure(
        kind: DataReadFailureKind.unknown,
        diagnosticMessage: 'daily_sign_in_read_failed',
      );
    }
    if (!_isCurrent(owner, generation)) return;
    if (result
        case DataReadSuccess<
          ForumDailySignInSnapshot,
          ForumDailySignInReadCapabilities
        >(
          :final data,
          :final metadata,
        )
        when data.userId == owner.uid &&
            metadata.origin == DataReadOrigin.network &&
            metadata.freshness == DataReadFreshness.current) {
      DailySignInAutomaticPolicy? policy;
      DailySignInAttemptState? checkpointState;
      var checkpointUnavailable = false;
      try {
        final ledger = ref.read(dailySignInAttemptLedgerProvider);
        if (data.status == ForumDailySignInStatus.signed) {
          await ledger.markConfirmedSigned(
            userId: owner.uid,
            forumDay: data.forumDay,
          );
        }
        policy = await ledger.automaticPolicy(
          userId: owner.uid,
          forumDay: data.forumDay,
        );
        final checkpoint = await ledger.readCheckpoint(owner.uid);
        if (checkpoint?.forumDay == data.forumDay) {
          checkpointState = checkpoint?.state;
        }
      } on Object {
        checkpointUnavailable = true;
      }
      if (!_isCurrent(owner, generation)) return;
      final sameAttemptDay = previous.attemptForumDay == data.forumDay;
      final keepPreviousUnknown =
          policy == DailySignInAutomaticPolicy.pausedPreviousDay &&
          previous.commandResult
              is DataCommandOutcomeUnknown<ForumDailySignInReceipt>;
      final keepDayChangedNotSent =
          previous.commandResult
              is DataCommandNotSent<ForumDailySignInReceipt> &&
          previous.commandResult?.failureOrNull?.code ==
              'daily_sign_in_forum_day_changed';
      final keepResult =
          sameAttemptDay || keepPreviousUnknown || keepDayChangedNotSent;
      state = state.copyWith(
        snapshot: data,
        readFailure: null,
        commandResult: keepResult ? previous.commandResult : null,
        attemptForumDay: keepResult ? previous.attemptForumDay : null,
        automaticPolicy: policy,
        checkpointState: checkpointState,
        // A successful read does not prove that a failed checkpoint write has
        // become durable. Keep this owner fail-closed until rebuilt.
        checkpointUnavailable:
            state.checkpointUnavailable || checkpointUnavailable,
        requiresExplicitRetry:
            policy != null && policy != DailySignInAutomaticPolicy.eligible,
        isLoading: false,
      );
      return;
    }
    state = state.copyWith(
      snapshot: null,
      readFailure:
          result.failureOrNull ??
          const DataReadFailure(
            kind: DataReadFailureKind.parse,
            diagnosticMessage: 'daily_sign_in_provenance_unverified',
          ),
      automaticPolicy: null,
      checkpointState: null,
      isLoading: false,
    );
  }

  /// Concurrent automatic requests coalesce. The startup host owns the
  /// once-per-UID launch budget; this coordinator owns protocol safety.
  Future<void> triggerAutomatic() {
    final owner = state.owner;
    if (owner == null) return Future<void>.value();
    if (_automaticFlight case final flight?) {
      if (_automaticFlightOwner == owner) return flight;
      return flight.then((_) {
        if (state.owner == owner) return triggerAutomatic();
      });
    }
    final future = _runAutomatic(owner, _generation, _automaticEpoch);
    _automaticFlight = future;
    _automaticFlightOwner = owner;
    return future.whenComplete(() {
      if (identical(_automaticFlight, future)) {
        _automaticFlight = null;
        _automaticFlightOwner = null;
      }
    });
  }

  /// Backgrounding or disabling the switch cancels a not-yet-sent automatic
  /// request. A sent request remains uncertain and its checkpoint is kept.
  void cancelAutomaticPending() {
    _automaticEpoch++;
    if (_submittingAutomatically) _submitCancellation?.cancel();
  }

  Future<void> _runAutomatic(
    VerifiedProfileOwner owner,
    int generation,
    int epoch,
  ) async {
    if (!_automaticIsCurrent(owner, generation, epoch)) return;
    if (_submitFlight case final flight?) await flight;
    if (!_automaticIsCurrent(owner, generation, epoch)) return;
    bool enabled;
    try {
      enabled = await ref
          .read(dailyAutoSignInSettingsProvider)
          .isEnabled(owner.uid);
    } on Object {
      if (_isCurrent(owner, generation)) {
        state = state.copyWith(settingsUnavailable: true, autoEnabled: null);
      }
      return;
    }
    if (!_automaticIsCurrent(owner, generation, epoch)) return;
    state = state.copyWith(autoEnabled: enabled, settingsUnavailable: false);
    if (!enabled) return;
    await refresh();
    if (!_automaticIsCurrent(owner, generation, epoch)) return;
    final snapshot = state.snapshot;
    if (snapshot == null ||
        snapshot.userId != owner.uid ||
        snapshot.status != ForumDailySignInStatus.unsigned ||
        state.isLoading ||
        state.readFailure != null ||
        state.checkpointUnavailable ||
        state.automaticPolicy != DailySignInAutomaticPolicy.eligible ||
        _submitFlight != null) {
      return;
    }
    await _startSubmit(
      owner,
      snapshot.forumDay,
      generation,
      automatic: true,
      automaticEpoch: epoch,
    );
  }

  /// Explicit retry is only accepted after the UI confirmation dialog.
  Future<void> submit({bool explicitlyRetryUnknown = false}) {
    if (_submitFlight != null) return _submitFlight!;
    final owner = state.owner;
    final snapshot = state.snapshot;
    if (owner == null ||
        snapshot == null ||
        snapshot.userId != owner.uid ||
        snapshot.status != ForumDailySignInStatus.unsigned ||
        state.isLoading ||
        state.isSubmitting ||
        state.storageUnavailable ||
        state.automaticPolicy == null ||
        (state.needsExplicitRetry && !explicitlyRetryUnknown)) {
      return Future<void>.value();
    }
    return _startSubmit(
      owner,
      snapshot.forumDay,
      _generation,
      automatic: false,
      manualOverride: explicitlyRetryUnknown,
    );
  }

  Future<void> _startSubmit(
    VerifiedProfileOwner owner,
    String forumDay,
    int generation, {
    required bool automatic,
    bool manualOverride = false,
    int? automaticEpoch,
  }) {
    if (_submitFlight != null) return _submitFlight!;
    final future = _executeSubmit(
      owner,
      forumDay,
      generation,
      automatic: automatic,
      manualOverride: manualOverride,
      automaticEpoch: automaticEpoch,
    );
    _submitFlight = future;
    _submitFlightUid = owner.uid;
    return future.whenComplete(() {
      if (!identical(_submitFlight, future)) return;
      _submitFlight = null;
      _submitFlightUid = null;
      if (ref.mounted &&
          state.owner?.uid == owner.uid &&
          state.owner != owner &&
          state.isSubmitting) {
        state = state.copyWith(isSubmitting: false);
        unawaited(refresh());
      }
    });
  }

  Future<void> _executeSubmit(
    VerifiedProfileOwner owner,
    String forumDay,
    int generation, {
    required bool automatic,
    required bool manualOverride,
    int? automaticEpoch,
  }) async {
    final previousResult = state.commandResult;
    final previousAttemptDay = state.attemptForumDay;
    final previousRetryGuard = state.requiresExplicitRetry;
    final cancellation = ForumRequestCancellation();
    _submitCancellation = cancellation;
    _submittingAutomatically = automatic;
    state = state.copyWith(isSubmitting: true, requiresExplicitRetry: true);
    DailySignInAttemptReservation? reservation;
    var gateStorageFailure = false;
    late final DataCommandResult<ForumDailySignInReceipt> result;
    try {
      result = await ref
          .read(dailySignInCommandProvider)
          .execute(
            ForumDailySignInRequest(
              userId: owner.uid,
              expectedForumDay: forumDay,
              cancellation: cancellation,
              beforeSend: (attempt) async {
                if (attempt.userId != owner.uid ||
                    attempt.forumDay != forumDay ||
                    cancellation.isCancelled ||
                    !_isCurrent(owner, generation) ||
                    (automatic && automaticEpoch != _automaticEpoch)) {
                  return ForumDailySignInSendAuthorization.suppress;
                }
                if (automatic) {
                  try {
                    if (!await ref
                        .read(dailyAutoSignInSettingsProvider)
                        .isEnabled(owner.uid)) {
                      return ForumDailySignInSendAuthorization.suppress;
                    }
                  } on Object {
                    gateStorageFailure = true;
                    return ForumDailySignInSendAuthorization.unavailable;
                  }
                }
                try {
                  reservation = await ref
                      .read(dailySignInAttemptLedgerProvider)
                      .reserve(
                        userId: owner.uid,
                        forumDay: forumDay,
                        manualOverride: manualOverride,
                      );
                } on Object {
                  gateStorageFailure = true;
                  return ForumDailySignInSendAuthorization.unavailable;
                }
                return reservation == null
                    ? ForumDailySignInSendAuthorization.suppress
                    : ForumDailySignInSendAuthorization.allow;
              },
            ),
          );
    } on Object {
      // An exception after the gate may mean that the GET reached the server.
      result = const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'daily_sign_in_command_unconfirmed',
          diagnosticMessage: 'daily_sign_in_command_unconfirmed',
        ),
      );
    } finally {
      _submittingAutomatically = false;
    }

    var checkpointUnavailable = gateStorageFailure;
    if (reservation case final reserved?) {
      try {
        final ledger = ref.read(dailySignInAttemptLedgerProvider);
        if (result is DataCommandNotSent<ForumDailySignInReceipt>) {
          await ledger.settleNotSent(reserved);
        } else if (result is DataCommandApplied<ForumDailySignInReceipt>) {
          await ledger.markConfirmedSigned(
            userId: owner.uid,
            forumDay: forumDay,
          );
        } else {
          await ledger.markUnknown(reserved);
        }
      } on Object {
        // A failed settlement leaves the durable pending entry as a safe block.
        checkpointUnavailable = true;
      }
    }
    if (!_isCurrent(owner, generation)) return;
    final keepPreviousUnknown =
        result is DataCommandNotSent<ForumDailySignInReceipt> &&
        previousResult is DataCommandOutcomeUnknown<ForumDailySignInReceipt>;
    state = state.copyWith(
      commandResult: keepPreviousUnknown ? previousResult : result,
      attemptForumDay: keepPreviousUnknown ? previousAttemptDay : forumDay,
      requiresExplicitRetry:
          checkpointUnavailable ||
          result is! DataCommandNotSent<ForumDailySignInReceipt> ||
          previousRetryGuard,
      checkpointUnavailable: checkpointUnavailable,
      isSubmitting: false,
    );
    // A positive read updates today's display only; it never upgrades an
    // uncalibrated command response to applied.
    await refresh();
  }

  bool _automaticIsCurrent(
    VerifiedProfileOwner owner,
    int generation,
    int epoch,
  ) => epoch == _automaticEpoch && _isCurrent(owner, generation);

  bool _isCurrent(VerifiedProfileOwner owner, int generation) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(verifiedProfileOwnerProvider) == owner;
}
