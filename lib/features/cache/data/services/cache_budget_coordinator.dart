import 'dart:math' as math;

import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';

final class CacheBudgetCoordinator {
  CacheBudgetCoordinator({
    required List<CacheBudgetParticipant> participants,
    DateTime Function()? now,
    this.lowWatermarkRatio = 0.5,
  }) : _participants = List<CacheBudgetParticipant>.unmodifiable(participants),
       _now = now ?? DateTime.now;

  final List<CacheBudgetParticipant> _participants;
  final DateTime Function() _now;
  final double lowWatermarkRatio;
  Future<CacheBudgetPruneResult>? _activePrune;
  int? _activeMaxBytes;

  Future<CacheCapacityReport> loadReport() async {
    var clearableBytes = 0;
    var budgetedBytes = 0;
    var longTermBytes = 0;
    final failures = <String>[];
    for (final participant in _participants) {
      try {
        final usage = await participant.loadUsage();
        clearableBytes += math.max(0, usage.clearableBytes);
        budgetedBytes += math.max(0, usage.budgetedBytes);
        longTermBytes += math.max(0, usage.longTermBytes);
      } catch (_) {
        failures.add(participant.participantId);
      }
    }
    return CacheCapacityReport(
      clearableBytes: clearableBytes,
      budgetedBytes: budgetedBytes,
      longTermBytes: longTermBytes,
      calculatedAt: _now(),
      failedParticipantIds: List<String>.unmodifiable(failures),
    );
  }

  Future<CacheBudgetPruneResult> pruneToLimit({required int maxBytes}) {
    final normalizedMax = math.max(0, maxBytes);
    final active = _activePrune;
    final activeMax = _activeMaxBytes;
    if (active != null && activeMax != null) {
      if (normalizedMax >= activeMax) {
        return active;
      }
      return active.then((_) => pruneToLimit(maxBytes: normalizedMax));
    }

    late final Future<CacheBudgetPruneResult> operation;
    _activeMaxBytes = normalizedMax;
    operation = _pruneToLimit(normalizedMax).whenComplete(() {
      if (identical(_activePrune, operation)) {
        _activePrune = null;
        _activeMaxBytes = null;
      }
    });
    _activePrune = operation;
    return operation;
  }

  Future<CacheBudgetPruneResult> _pruneToLimit(int maxBytes) async {
    final before = await loadReport();
    final targetBytes = before.budgetedBytes > maxBytes
        ? (maxBytes * lowWatermarkRatio).floor()
        : maxBytes;
    if (before.budgetedBytes <= maxBytes) {
      return CacheBudgetPruneResult(
        beforeBytes: before.budgetedBytes,
        afterBytes: before.budgetedBytes,
        deletedEntries: 0,
        deletedBytes: 0,
        targetBytes: targetBytes,
        failedParticipantIds: before.failedParticipantIds,
      );
    }

    final candidates = <CacheEvictionCandidate>[];
    final participantsById = <String, CacheBudgetParticipant>{};
    final failures = <String>{...before.failedParticipantIds};
    for (final participant in _participants) {
      participantsById[participant.participantId] = participant;
      try {
        candidates.addAll(await participant.loadEvictionCandidates());
      } catch (_) {
        failures.add(participant.participantId);
      }
    }
    candidates.sort(_compareCandidates);

    var estimatedBytes = before.budgetedBytes;
    var deletedEntries = 0;
    var deletedBytes = 0;
    for (final candidate in candidates) {
      if (estimatedBytes <= targetBytes) {
        break;
      }
      final participant = participantsById[candidate.participantId];
      if (participant == null) {
        failures.add(candidate.participantId);
        continue;
      }
      try {
        if (await participant.deleteCandidate(candidate)) {
          deletedEntries += 1;
          final bytes = math.max(0, candidate.bytes);
          deletedBytes += bytes;
          estimatedBytes = math.max(0, estimatedBytes - bytes);
        }
      } catch (_) {
        failures.add(candidate.participantId);
      }
    }

    final after = await loadReport();
    failures.addAll(after.failedParticipantIds);
    return CacheBudgetPruneResult(
      beforeBytes: before.budgetedBytes,
      afterBytes: after.budgetedBytes,
      deletedEntries: deletedEntries,
      deletedBytes: deletedBytes,
      targetBytes: targetBytes,
      failedParticipantIds: List<String>.unmodifiable(failures),
    );
  }

  Future<CacheBudgetClearResult> clearRegular() async {
    final active = _activePrune;
    if (active != null) {
      await active;
    }
    var deletedEntries = 0;
    var deletedBytes = 0;
    final failures = <String>[];
    for (final participant in _participants) {
      try {
        final result = await participant.clearRegular();
        deletedEntries += result.deletedEntries;
        deletedBytes += result.deletedBytes;
      } catch (_) {
        failures.add(participant.participantId);
      }
    }
    return CacheBudgetClearResult(
      deletedEntries: deletedEntries,
      deletedBytes: deletedBytes,
      failedParticipantIds: List<String>.unmodifiable(failures),
    );
  }

  int _compareCandidates(
    CacheEvictionCandidate left,
    CacheEvictionCandidate right,
  ) {
    final priority = left.priority.index.compareTo(right.priority.index);
    if (priority != 0) {
      return priority;
    }
    final accessed = left.lastAccessedAt.compareTo(right.lastAccessedAt);
    if (accessed != 0) {
      return accessed;
    }
    final participant = left.participantId.compareTo(right.participantId);
    if (participant != 0) {
      return participant;
    }
    return left.cacheKey.compareTo(right.cacheKey);
  }
}
