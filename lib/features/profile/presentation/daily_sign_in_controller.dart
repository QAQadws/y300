import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

/// The state is owned by an authenticated session, not by a particular page.
final class DailySignInViewState {
  const DailySignInViewState({
    this.owner,
    this.snapshot,
    this.readFailure,
    this.commandResult,
    this.attemptForumDay,
    this.requiresExplicitRetry = false,
    this.isLoading = false,
    this.isSubmitting = false,
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
  final bool requiresExplicitRetry;
  final bool isLoading;
  final bool isSubmitting;

  // A command can cross forum midnight after preparation. A later page date
  // alone cannot prove which day the sent GET affected.
  bool get needsExplicitRetry =>
      requiresExplicitRetry ||
      commandResult is DataCommandOutcomeUnknown<ForumDailySignInReceipt>;
}

final dailySignInControllerProvider =
    NotifierProvider<DailySignInController, DailySignInViewState>(
      DailySignInController.new,
    );

/// Shared manual coordinator. A later startup trigger can call the same
/// submit method without creating another transport path or in-flight command.
class DailySignInController extends Notifier<DailySignInViewState> {
  int _generation = 0;
  Future<void>? _readFlight;
  Future<void>? _submitFlight;
  String? _submitFlightUid;
  final Set<String> _uncertainUids = <String>{};
  ForumRequestCancellation? _readCancellation;
  ForumRequestCancellation? _submitCancellation;

  @override
  DailySignInViewState build() {
    // One coordinator persists across the two native entry points. Stage 3
    // can reuse it for startup triggers without a second single-flight guard.
    final owner = ref.watch(verifiedProfileOwnerProvider);
    _generation++;
    _readCancellation?.cancel();
    _submitCancellation?.cancel();
    _readFlight = null;
    // Riverpod clears lifecycle callbacks on each dependency rebuild.
    ref.onDispose(() {
      _generation++;
      _readCancellation?.cancel();
      _submitCancellation?.cancel();
    });
    if (owner != null) {
      unawaited(Future<void>.microtask(ensureLoaded));
    }
    return DailySignInViewState(
      owner: owner,
      requiresExplicitRetry:
          owner != null && _uncertainUids.contains(owner.uid),
      isSubmitting:
          owner != null &&
          _submitFlight != null &&
          _submitFlightUid == owner.uid,
    );
  }

  Future<void> ensureLoaded() async {
    if (state.owner == null ||
        state.snapshot != null ||
        state.readFailure != null) {
      return;
    }
    await refresh();
  }

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
    state = DailySignInViewState(
      owner: owner,
      commandResult: previous.commandResult,
      attemptForumDay: previous.attemptForumDay,
      requiresExplicitRetry: _uncertainUids.contains(owner.uid),
      isLoading: true,
      isSubmitting: previous.isSubmitting,
    );
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
      final sameAttemptDay = previous.attemptForumDay == data.forumDay;
      final preserveUnknown =
          previous.commandResult
              is DataCommandOutcomeUnknown<ForumDailySignInReceipt>;
      final preserveNotSent =
          previous.commandResult is DataCommandNotSent<ForumDailySignInReceipt>;
      state = DailySignInViewState(
        owner: owner,
        snapshot: data,
        commandResult: sameAttemptDay || preserveUnknown || preserveNotSent
            ? previous.commandResult
            : null,
        attemptForumDay: sameAttemptDay || preserveUnknown || preserveNotSent
            ? previous.attemptForumDay
            : null,
        requiresExplicitRetry: _uncertainUids.contains(owner.uid),
        isSubmitting: previous.isSubmitting,
      );
      return;
    }
    state = DailySignInViewState(
      owner: owner,
      readFailure:
          result.failureOrNull ??
          const DataReadFailure(
            kind: DataReadFailureKind.parse,
            diagnosticMessage: 'daily_sign_in_provenance_unverified',
          ),
      commandResult: previous.commandResult,
      attemptForumDay: previous.attemptForumDay,
      requiresExplicitRetry: _uncertainUids.contains(owner.uid),
      isSubmitting: previous.isSubmitting,
    );
  }

  /// Explicit retry must be acknowledged by the caller after an unknown send.
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
        (state.needsExplicitRetry && !explicitlyRetryUnknown)) {
      return Future<void>.value();
    }
    final future = _submit(owner, snapshot.forumDay, _generation);
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
        state = DailySignInViewState(
          owner: state.owner,
          requiresExplicitRetry: _uncertainUids.contains(owner.uid),
        );
        unawaited(refresh());
      }
    });
  }

  Future<void> _submit(
    VerifiedProfileOwner owner,
    String forumDay,
    int generation,
  ) async {
    final priorResult = state.commandResult;
    final priorAttemptDay = state.attemptForumDay;
    final hadUncertainAttempt = _uncertainUids.contains(owner.uid);
    _uncertainUids.add(owner.uid);
    final cancellation = ForumRequestCancellation();
    _submitCancellation = cancellation;
    state = DailySignInViewState(
      owner: owner,
      snapshot: state.snapshot,
      commandResult: state.commandResult,
      attemptForumDay: state.attemptForumDay,
      requiresExplicitRetry: true,
      isSubmitting: true,
    );
    late final DataCommandResult<ForumDailySignInReceipt> result;
    try {
      result = await ref
          .read(dailySignInCommandProvider)
          .execute(
            ForumDailySignInRequest(
              userId: owner.uid,
              expectedForumDay: forumDay,
              cancellation: cancellation,
            ),
          );
    } on Object {
      // A transport exception cannot prove that the command did not reach the
      // server. Preserve the unknown result and require explicit user action.
      result = const DataCommandOutcomeUnknown(
        DataCommandFailure(
          kind: DataCommandFailureKind.unknown,
          retryPolicy: DataCommandRetryPolicy.explicitOnly,
          code: 'daily_sign_in_command_unconfirmed',
          diagnosticMessage: 'daily_sign_in_command_unconfirmed',
        ),
      );
    }
    if (result is DataCommandNotSent<ForumDailySignInReceipt> &&
        !hadUncertainAttempt) {
      _uncertainUids.remove(owner.uid);
    }
    if (!_isCurrent(owner, generation)) return;
    final preserveUnknown =
        result is DataCommandNotSent<ForumDailySignInReceipt> &&
        priorResult is DataCommandOutcomeUnknown<ForumDailySignInReceipt>;
    state = DailySignInViewState(
      owner: owner,
      snapshot: state.snapshot,
      commandResult: preserveUnknown ? priorResult : result,
      attemptForumDay: preserveUnknown ? priorAttemptDay : forumDay,
      requiresExplicitRetry: _uncertainUids.contains(owner.uid),
    );
    // This is display reconciliation only. The package command result remains
    // unknown if its own response lacked calibrated proof of application.
    await refresh();
  }

  bool _isCurrent(VerifiedProfileOwner owner, int generation) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(verifiedProfileOwnerProvider) == owner;
}
