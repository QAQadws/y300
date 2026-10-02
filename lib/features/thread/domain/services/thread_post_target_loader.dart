import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/thread/domain/models/thread_post_target.dart';
import 'package:y300/features/thread/domain/services/thread_post_route_resolver.dart';

typedef ThreadPostTargetRead =
    DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>;

/// Initial entry only: one ordinary read followed by at most one relocation.
final class ThreadPostTargetLoader {
  const ThreadPostTargetLoader({
    required this.readPage,
    this.readHandoff,
    required this.resolver,
    required this.invalidate,
  });

  final Future<ThreadPostTargetRead> Function(int page) readPage;
  final Future<ThreadPostTargetRead?> Function(
    ThreadDetailHandoff handoff,
    int page,
  )?
  readHandoff;
  final ThreadPostRouteResolver resolver;
  final Future<void> Function() invalidate;

  Future<ThreadPostTargetRead> load({
    required ThreadPostTarget target,
    required int page,
    ThreadDetailHandoff? initialHandoff,
    required bool Function() isCurrent,
  }) async {
    Future<ThreadPostTargetRead> readInitial(
      int requestedPage,
      ThreadDetailHandoff? handoff,
    ) async {
      if (handoff != null && readHandoff != null) {
        final reused = await readHandoff!(handoff, requestedPage);
        if (!isCurrent()) return _cancelled;
        if (reused != null) return reused;
      }
      return readPage(requestedPage);
    }

    var result = await readInitial(page, initialHandoff);
    if (!isCurrent()) return _cancelled;
    if (result
        is DataReadFailure<ThreadDetailData, ThreadDetailReadCapabilities>) {
      return result;
    }
    var data = result.dataOrNull!;
    if (data.tid.trim() != target.tid) return _unconfirmed;
    if (_contains(data, target.pid)) return result;

    // Fence old cache writers before locating again. The new locator response
    // can then be handed to the detail page without being invalidated itself.
    try {
      await invalidate();
    } catch (_) {
      return _unconfirmed;
    }
    if (!isCurrent()) return _cancelled;
    final located = await resolver.resolve(
      ThreadPostTarget(tid: target.tid, pid: target.pid),
    );
    if (!isCurrent()) return _cancelled;
    if (located case ApiFailure(:final error)) {
      return DataReadFailure(
        kind: switch (error.type) {
          ApiErrorType.network => DataReadFailureKind.network,
          ApiErrorType.timeout => DataReadFailureKind.timeout,
          ApiErrorType.unauthorized => DataReadFailureKind.unauthorized,
          ApiErrorType.server => DataReadFailureKind.server,
          _ => DataReadFailureKind.parse,
        },
        code: error.code ?? 'thread_post_target_unconfirmed',
        statusCode: error.statusCode,
        diagnosticMessage: 'thread_post_target_unconfirmed',
      );
    }
    final destination = located.dataOrNull!;
    result = await readInitial(destination.page, destination.detailHandoff);
    if (!isCurrent()) return _cancelled;
    if (result
        is DataReadFailure<ThreadDetailData, ThreadDetailReadCapabilities>) {
      return result;
    }
    data = result.dataOrNull!;
    return data.tid.trim() == target.tid && _contains(data, target.pid)
        ? result
        : _unconfirmed;
  }

  bool _contains(ThreadDetailData data, String pid) =>
      data.posts.any((post) => post.pid.trim() == pid);

  static const ThreadPostTargetRead _unconfirmed = DataReadFailure(
    kind: DataReadFailureKind.parse,
    code: 'thread_post_target_unconfirmed',
    diagnosticMessage: 'thread_post_target_unconfirmed',
  );
  static const ThreadPostTargetRead _cancelled = DataReadFailure(
    kind: DataReadFailureKind.cancelled,
    code: 'thread_post_target_cancelled',
    diagnosticMessage: 'thread_post_target_cancelled',
  );
}
