import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'forum_preparation_scheduler.dart';

/// Data-only input. The caller supplies the conversion that produced [html],
/// rather than deriving provenance from an in-progress settings preview.
final class ForumBodyPreparationInput {
  const ForumBodyPreparationInput({
    required this.html,
    required this.sourceId,
    required this.conversionIdentity,
    this.limits = const ForumBodyParseLimits(),
  });

  final String html;
  final String sourceId;
  final String conversionIdentity;
  final ForumBodyParseLimits limits;

  Object get identity => (
    html,
    sourceId,
    conversionIdentity,
    ForumBodyParser.revision,
    limits.maxCodeUnits,
    limits.maxNodes,
    limits.maxDepth,
  );

  ForumBodyDocument prepareSynchronously() => ForumBodyParser(limits: limits)
      .parse(
        html: html,
        sourceId: sourceId,
        conversionIdentity: conversionIdentity,
      );
}

typedef ForumBodyPreparationWorker = Future<ForumBodyDocument> Function(
  ForumBodyPreparationInput input,
);

Future<ForumBodyDocument> _runBodyWorker(ForumBodyPreparationInput input) =>
    Isolate.run(input.prepareSynchronously, debugName: 'forum-native-document');

/// Admission facade; returned documents are owned by the consuming session.
/// Cancellation retires queued work, while an already-running isolate retains
/// its slot until completion. Consumers must reject results from retired owners.
final class ForumBodyPreparationExecutor extends ChangeNotifier {
  ForumBodyPreparationExecutor({
    ForumPreparationScheduler? scheduler,
    this.codeUnitThreshold = 32 * 1024,
    ForumBodyPreparationWorker worker = _runBodyWorker,
  }) : assert(codeUnitThreshold >= 0),
       _scheduler = scheduler ?? ForumPreparationScheduler(),
       _ownsScheduler = scheduler == null,
       _worker = worker {
    _scope = _scheduler.createScope();
    _scheduler.addListener(_capacityChanged);
  }

  static final shared = ForumBodyPreparationExecutor(
    scheduler: ForumPreparationScheduler.shared,
  );

  final int codeUnitThreshold;
  final ForumPreparationScheduler _scheduler;
  final bool _ownsScheduler;
  final ForumBodyPreparationWorker _worker;
  late final ForumPreparationScope _scope;
  bool _closed = false;

  int get activeCount => _scheduler.activeCount;
  int get queuedCount => _scheduler.queuedCount;
  int get queuedCodeUnits => _scheduler.queuedCodeUnits;

  bool usesBackground(ForumBodyPreparationInput input) =>
      input.html.length >= codeUnitThreshold;

  ForumPreparationLease<ForumBodyDocument>? tryAcquire(
    ForumBodyPreparationInput input,
  ) {
    if (_closed) throw StateError('Body preparation executor is closed');
    final worker = _worker;
    return _scope.tryAcquire<ForumBodyDocument>(
      identity: (input.identity, worker),
      codeUnits: input.html.length,
      work: () => worker(input),
    );
  }

  void _capacityChanged() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _scheduler.removeListener(_capacityChanged);
    _scope.close();
    if (_ownsScheduler) _scheduler.dispose();
    super.dispose();
  }
}
