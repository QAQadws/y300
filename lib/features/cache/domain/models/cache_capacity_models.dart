import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

final class CacheCapacityReport {
  const CacheCapacityReport({
    required this.clearableBytes,
    required this.budgetedBytes,
    required this.longTermBytes,
    required this.calculatedAt,
    this.failedParticipantIds = const <String>[],
  });

  factory CacheCapacityReport.empty({DateTime? calculatedAt}) {
    return CacheCapacityReport(
      clearableBytes: 0,
      budgetedBytes: 0,
      longTermBytes: 0,
      calculatedAt: calculatedAt ?? DateTime.now(),
    );
  }

  final int clearableBytes;
  final int budgetedBytes;
  final int longTermBytes;
  final DateTime calculatedAt;
  final List<String> failedParticipantIds;

  bool get isPartial => failedParticipantIds.isNotEmpty;
}

final class CacheParticipantUsage {
  const CacheParticipantUsage({
    required this.clearableBytes,
    required this.budgetedBytes,
    this.longTermBytes = 0,
  });

  final int clearableBytes;
  final int budgetedBytes;
  final int longTermBytes;
}

enum CacheEvictionPriority {
  regularImage,
  parsedSnapshot,
  document,
  recentReaderImage,
}

final class CacheEvictionCandidate {
  const CacheEvictionCandidate({
    required this.participantId,
    required this.cacheKey,
    required this.bytes,
    required this.lastAccessedAt,
    required this.priority,
  });

  final String participantId;
  final String cacheKey;
  final int bytes;
  final DateTime lastAccessedAt;
  final CacheEvictionPriority priority;
}

final class CacheParticipantClearResult {
  const CacheParticipantClearResult({
    required this.deletedEntries,
    required this.deletedBytes,
  });

  static const empty = CacheParticipantClearResult(
    deletedEntries: 0,
    deletedBytes: 0,
  );

  final int deletedEntries;
  final int deletedBytes;
}

final class CacheBudgetPruneResult {
  const CacheBudgetPruneResult({
    required this.beforeBytes,
    required this.afterBytes,
    required this.deletedEntries,
    required this.deletedBytes,
    required this.targetBytes,
    this.failedParticipantIds = const <String>[],
  });

  final int beforeBytes;
  final int afterBytes;
  final int deletedEntries;
  final int deletedBytes;
  final int targetBytes;
  final List<String> failedParticipantIds;

  bool get isPartial => failedParticipantIds.isNotEmpty;
}

final class CacheBudgetClearResult {
  const CacheBudgetClearResult({
    required this.deletedEntries,
    required this.deletedBytes,
    this.failedParticipantIds = const <String>[],
  });

  final int deletedEntries;
  final int deletedBytes;
  final List<String> failedParticipantIds;

  bool get isPartial => failedParticipantIds.isNotEmpty;
}

abstract interface class CacheBudgetParticipant {
  String get participantId;

  Future<CacheParticipantUsage> loadUsage();

  Future<List<CacheEvictionCandidate>> loadEvictionCandidates();

  Future<bool> deleteCandidate(CacheEvictionCandidate candidate);

  Future<CacheParticipantClearResult> clearRegular();
}

abstract interface class CacheMutationReporter {
  void reportMutation(CacheNamespace namespace);
}

abstract interface class CacheMutationSource {
  Stream<CacheNamespace> get mutations;
}

final class NoopCacheMutationReporter implements CacheMutationReporter {
  const NoopCacheMutationReporter();

  @override
  void reportMutation(CacheNamespace namespace) {}
}
