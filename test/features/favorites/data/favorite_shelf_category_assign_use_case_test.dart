import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/favorite_shelf_category_assign_use_case_impl.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';

void main() {
  test('DefaultFavoriteShelfCategoryAssignUseCase parses favorite work ids and moves valid tids', () async {
    final repository = _RecordingFavoriteRepository();
    final useCase = DefaultFavoriteShelfCategoryAssignUseCase(
      repository: repository,
    );

    final result = await useCase.assign(
      workIds: <String>{'favorite:100', 'favorite:101'},
      sourceCategoryId: 'default',
      targetCategoryId: 'archive',
    );

    expect(
      repository.calls,
      <_MoveThreadCall>[
        const _MoveThreadCall(tid: '100', toCategoryId: 'archive'),
        const _MoveThreadCall(tid: '101', toCategoryId: 'archive'),
      ],
    );
    expect(result.assignedWorkIds, <String>['favorite:100', 'favorite:101']);
    expect(result.failedWorkIds, isEmpty);
    expect(result.targetCategoryId, 'archive');
  });

  test('DefaultFavoriteShelfCategoryAssignUseCase reports invalid ids and keeps going after failures', () async {
    final repository = _RecordingFavoriteRepository(
      failingTids: const <String>{'101'},
    );
    final useCase = DefaultFavoriteShelfCategoryAssignUseCase(
      repository: repository,
    );

    final result = await useCase.assign(
      workIds: <String>{'favorite:100', 'broken-id', 'favorite:101'},
      sourceCategoryId: 'default',
      targetCategoryId: 'archive',
    );

    expect(result.assignedWorkIds, <String>['favorite:100']);
    expect(result.failedWorkIds, <String>['broken-id', 'favorite:101']);
  });
}

class _RecordingFavoriteRepository implements LocalFavoriteRepository {
  _RecordingFavoriteRepository({
    this.failingTids = const <String>{},
  });

  final Set<String> failingTids;
  final List<_MoveThreadCall> calls = <_MoveThreadCall>[];

  @override
  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  }) async {
    calls.add(_MoveThreadCall(tid: tid, toCategoryId: toCategoryId));
    if (failingTids.contains(tid)) {
      throw StateError('move failed');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MoveThreadCall {
  const _MoveThreadCall({
    required this.tid,
    required this.toCategoryId,
  });

  final String tid;
  final String toCategoryId;

  @override
  bool operator ==(Object other) {
    return other is _MoveThreadCall &&
        other.tid == tid &&
        other.toCategoryId == toCategoryId;
  }

  @override
  int get hashCode => Object.hash(tid, toCategoryId);
}
