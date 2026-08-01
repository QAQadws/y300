import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/data/use_cases/novel_shelf_category_assign_use_case_impl.dart';

void main() {
  test(
    'DefaultNovelShelfCategoryAssignUseCase forwards source and target category ids',
    () async {
      final repository = _RecordingNovelRepository();
      final useCase = DefaultNovelShelfCategoryAssignUseCase(
        repository: repository,
      );

      final result = await useCase.assign(
        workIds: <String>{'novel-a', 'novel-b'},
        sourceCategoryId: 'default',
        targetCategoryId: 'archive',
      );

      expect(repository.calls, <_MoveNovelCall>[
        const _MoveNovelCall(
          novelId: 'novel-a',
          fromCategoryId: 'default',
          toCategoryId: 'archive',
        ),
        const _MoveNovelCall(
          novelId: 'novel-b',
          fromCategoryId: 'default',
          toCategoryId: 'archive',
        ),
      ]);
      expect(result.assignedWorkIds, <String>['novel-a', 'novel-b']);
      expect(result.failedWorkIds, isEmpty);
      expect(result.targetCategoryId, 'archive');
    },
  );

  test(
    'DefaultNovelShelfCategoryAssignUseCase keeps going after per-item failure',
    () async {
      final repository = _RecordingNovelRepository(
        failingNovelIds: const <String>{'novel-b'},
      );
      final useCase = DefaultNovelShelfCategoryAssignUseCase(
        repository: repository,
      );

      final result = await useCase.assign(
        workIds: <String>{'novel-a', 'novel-b', 'novel-c'},
        sourceCategoryId: 'default',
        targetCategoryId: 'archive',
      );

      expect(result.assignedWorkIds, <String>['novel-a', 'novel-c']);
      expect(result.failedWorkIds, <String>['novel-b']);
    },
  );
}

class _RecordingNovelRepository implements NovelRepository {
  _RecordingNovelRepository({this.failingNovelIds = const <String>{}});

  final Set<String> failingNovelIds;
  final List<_MoveNovelCall> calls = <_MoveNovelCall>[];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {
    calls.add(
      _MoveNovelCall(
        novelId: novelId,
        fromCategoryId: fromCategoryId,
        toCategoryId: toCategoryId,
      ),
    );
    if (failingNovelIds.contains(novelId)) {
      throw StateError('move failed');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MoveNovelCall {
  const _MoveNovelCall({
    required this.novelId,
    required this.fromCategoryId,
    required this.toCategoryId,
  });

  final String novelId;
  final String fromCategoryId;
  final String toCategoryId;

  @override
  bool operator ==(Object other) {
    return other is _MoveNovelCall &&
        other.novelId == novelId &&
        other.fromCategoryId == fromCategoryId &&
        other.toCategoryId == toCategoryId;
  }

  @override
  int get hashCode => Object.hash(novelId, fromCategoryId, toCategoryId);
}
