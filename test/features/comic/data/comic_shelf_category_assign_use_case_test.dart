import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/use_cases/comic_shelf_category_assign_use_case_impl.dart';

void main() {
  test(
    'DefaultComicShelfCategoryAssignUseCase forwards source and target category ids',
    () async {
      final repository = _RecordingComicRepository();
      final useCase = DefaultComicShelfCategoryAssignUseCase(
        repository: repository,
      );

      final result = await useCase.assign(
        workIds: <String>{'comic-a', 'comic-b'},
        sourceCategoryId: 'default',
        targetCategoryId: 'romance',
      );

      expect(repository.calls, <_MoveComicCall>[
        const _MoveComicCall(
          comicId: 'comic-a',
          fromCategoryId: 'default',
          toCategoryId: 'romance',
        ),
        const _MoveComicCall(
          comicId: 'comic-b',
          fromCategoryId: 'default',
          toCategoryId: 'romance',
        ),
      ]);
      expect(result.assignedWorkIds, <String>['comic-a', 'comic-b']);
      expect(result.failedWorkIds, isEmpty);
      expect(result.targetCategoryId, 'romance');
    },
  );

  test(
    'DefaultComicShelfCategoryAssignUseCase keeps going after per-item failure',
    () async {
      final repository = _RecordingComicRepository(
        failingComicIds: const <String>{'comic-b'},
      );
      final useCase = DefaultComicShelfCategoryAssignUseCase(
        repository: repository,
      );

      final result = await useCase.assign(
        workIds: <String>{'comic-a', 'comic-b', 'comic-c'},
        sourceCategoryId: 'default',
        targetCategoryId: 'romance',
      );

      expect(result.assignedWorkIds, <String>['comic-a', 'comic-c']);
      expect(result.failedWorkIds, <String>['comic-b']);
    },
  );
}

class _RecordingComicRepository implements ComicRepository {
  _RecordingComicRepository({this.failingComicIds = const <String>{}});

  final Set<String> failingComicIds;
  final List<_MoveComicCall> calls = <_MoveComicCall>[];

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {
    calls.add(
      _MoveComicCall(
        comicId: comicId,
        fromCategoryId: fromCategoryId,
        toCategoryId: toCategoryId,
      ),
    );
    if (failingComicIds.contains(comicId)) {
      throw StateError('move failed');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MoveComicCall {
  const _MoveComicCall({
    required this.comicId,
    required this.fromCategoryId,
    required this.toCategoryId,
  });

  final String comicId;
  final String fromCategoryId;
  final String toCategoryId;

  @override
  bool operator ==(Object other) {
    return other is _MoveComicCall &&
        other.comicId == comicId &&
        other.fromCategoryId == fromCategoryId &&
        other.toCategoryId == toCategoryId;
  }

  @override
  int get hashCode => Object.hash(comicId, fromCategoryId, toCategoryId);
}
