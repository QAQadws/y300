import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/services/cache_budget_coordinator.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';

void main() {
  test(
    'capacity report sums regular usage and isolates participant failure',
    () async {
      final coordinator = CacheBudgetCoordinator(
        participants: <CacheBudgetParticipant>[
          _FakeParticipant(id: 'image', budgetedBytes: 100, longTermBytes: 40),
          _FakeParticipant(id: 'document', budgetedBytes: 25),
          _FakeParticipant(id: 'broken', budgetedBytes: 10)..failUsage = true,
        ],
        now: () => DateTime(2026, 7, 22),
      );

      final report = await coordinator.loadReport();

      expect(report.clearableBytes, 125);
      expect(report.budgetedBytes, 125);
      expect(report.longTermBytes, 40);
      expect(report.failedParticipantIds, <String>['broken']);
    },
  );

  test('prune uses priority then LRU and stops at the low watermark', () async {
    final deleted = <String>[];
    final image = _FakeParticipant(
      id: 'image',
      budgetedBytes: 300,
      candidates: <_CandidateSeed>[
        _CandidateSeed(
          key: 'newer-image',
          bytes: 100,
          accessedAt: DateTime(2026, 2, 1),
          priority: CacheEvictionPriority.regularImage,
        ),
        _CandidateSeed(
          key: 'older-image',
          bytes: 100,
          accessedAt: DateTime(2026, 1, 1),
          priority: CacheEvictionPriority.regularImage,
        ),
        _CandidateSeed(
          key: 'recent-reader',
          bytes: 100,
          accessedAt: DateTime(2025, 1, 1),
          priority: CacheEvictionPriority.recentReaderImage,
        ),
      ],
      onDelete: deleted.add,
    );
    final snapshot = _FakeParticipant(
      id: 'snapshot',
      budgetedBytes: 100,
      candidates: <_CandidateSeed>[
        _CandidateSeed(
          key: 'snapshot-1',
          bytes: 100,
          accessedAt: DateTime(2025, 1, 1),
          priority: CacheEvictionPriority.parsedSnapshot,
        ),
      ],
      onDelete: deleted.add,
    );
    final document = _FakeParticipant(
      id: 'document',
      budgetedBytes: 100,
      candidates: <_CandidateSeed>[
        _CandidateSeed(
          key: 'document-1',
          bytes: 100,
          accessedAt: DateTime(2024, 1, 1),
          priority: CacheEvictionPriority.document,
        ),
      ],
      onDelete: deleted.add,
    );
    final coordinator = CacheBudgetCoordinator(
      participants: <CacheBudgetParticipant>[image, snapshot, document],
    );

    final result = await coordinator.pruneToLimit(maxBytes: 300);

    expect(result.targetBytes, 150);
    expect(result.afterBytes, 100);
    expect(deleted, <String>[
      'older-image',
      'newer-image',
      'snapshot-1',
      'document-1',
    ]);
  });

  test('concurrent equivalent prune requests share one operation', () async {
    final gate = Completer<void>();
    final participant = _FakeParticipant(id: 'image', budgetedBytes: 0)
      ..usageGate = gate.future;
    final coordinator = CacheBudgetCoordinator(
      participants: <CacheBudgetParticipant>[participant],
    );

    final first = coordinator.pruneToLimit(maxBytes: 100);
    final second = coordinator.pruneToLimit(maxBytes: 100);
    expect(identical(first, second), isTrue);

    gate.complete();
    await Future.wait(<Future<CacheBudgetPruneResult>>[first, second]);
    expect(participant.loadUsageCalls, 1);
  });

  test('clear continues after a participant failure', () async {
    final regular = _FakeParticipant(id: 'image', budgetedBytes: 50);
    final broken = _FakeParticipant(id: 'document', budgetedBytes: 20)
      ..failClear = true;
    final coordinator = CacheBudgetCoordinator(
      participants: <CacheBudgetParticipant>[broken, regular],
    );

    final result = await coordinator.clearRegular();

    expect(result.deletedBytes, 50);
    expect(result.failedParticipantIds, <String>['document']);
    expect(regular.budgetedBytes, 0);
  });
}

class _CandidateSeed {
  const _CandidateSeed({
    required this.key,
    required this.bytes,
    required this.accessedAt,
    required this.priority,
  });

  final String key;
  final int bytes;
  final DateTime accessedAt;
  final CacheEvictionPriority priority;
}

class _FakeParticipant implements CacheBudgetParticipant {
  _FakeParticipant({
    required this.id,
    required this.budgetedBytes,
    this.longTermBytes = 0,
    this.candidates = const <_CandidateSeed>[],
    this.onDelete,
  });

  final String id;
  int budgetedBytes;
  final int longTermBytes;
  final List<_CandidateSeed> candidates;
  final void Function(String key)? onDelete;
  bool failUsage = false;
  bool failClear = false;
  Future<void>? usageGate;
  int loadUsageCalls = 0;
  final Set<String> _deleted = <String>{};

  @override
  String get participantId => id;

  @override
  Future<CacheParticipantUsage> loadUsage() async {
    loadUsageCalls += 1;
    await usageGate;
    if (failUsage) {
      throw StateError('usage failed');
    }
    return CacheParticipantUsage(
      clearableBytes: budgetedBytes,
      budgetedBytes: budgetedBytes,
      longTermBytes: longTermBytes,
    );
  }

  @override
  Future<List<CacheEvictionCandidate>> loadEvictionCandidates() async {
    return candidates
        .where((candidate) => !_deleted.contains(candidate.key))
        .map((candidate) {
          return CacheEvictionCandidate(
            participantId: participantId,
            cacheKey: candidate.key,
            bytes: candidate.bytes,
            lastAccessedAt: candidate.accessedAt,
            priority: candidate.priority,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<bool> deleteCandidate(CacheEvictionCandidate candidate) async {
    if (!_deleted.add(candidate.cacheKey)) {
      return false;
    }
    budgetedBytes -= candidate.bytes;
    onDelete?.call(candidate.cacheKey);
    return true;
  }

  @override
  Future<CacheParticipantClearResult> clearRegular() async {
    if (failClear) {
      throw StateError('clear failed');
    }
    final bytes = budgetedBytes;
    budgetedBytes = 0;
    return CacheParticipantClearResult(
      deletedEntries: candidates.length,
      deletedBytes: bytes,
    );
  }
}
