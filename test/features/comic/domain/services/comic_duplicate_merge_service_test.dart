import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';

void main() {
  group('ComicDuplicateMergeService', () {
    test('mergeComic merges only the duplicate group connected to the comic', () async {
      final repository = _FakeDuplicateMergeRepository(
        groups: const <ComicDuplicateGroup>[
          ComicDuplicateGroup(
            comicIds: <String>{'comic:a', 'comic:b'},
            sharedTids: <String>{'100'},
          ),
          ComicDuplicateGroup(
            comicIds: <String>{'comic:c', 'comic:d'},
            sharedTids: <String>{'200'},
          ),
        ],
      );
      final service = ComicDuplicateMergeService(repository: repository);

      final result = await service.mergeComic(comicId: 'comic:b');

      expect(result.changed, isTrue);
      expect(result.targetComicId, 'comic:a');
      expect(repository.mergedGroups, <Set<String>>[
        <String>{'comic:a', 'comic:b'},
      ]);
    });

    test('mergeAllDuplicates repeats discovery until no duplicate group remains', () async {
      final repository = _FakeDuplicateMergeRepository(
        groups: const <ComicDuplicateGroup>[
          ComicDuplicateGroup(
            comicIds: <String>{'comic:a', 'comic:b'},
            sharedTids: <String>{'100'},
          ),
          ComicDuplicateGroup(
            comicIds: <String>{'comic:c', 'comic:d'},
            sharedTids: <String>{'200'},
          ),
        ],
      );
      final service = ComicDuplicateMergeService(repository: repository);

      final summary = await service.mergeAllDuplicates();

      expect(summary.changed, isTrue);
      expect(summary.mergedGroupCount, 2);
      expect(summary.removedComicCount, 2);
      expect(summary.replacements, const <String, String>{
        'comic:b': 'comic:a',
        'comic:d': 'comic:c',
      });
    });
  });
}

class _FakeDuplicateMergeRepository implements ComicDuplicateMergeRepository {
  _FakeDuplicateMergeRepository({
    required List<ComicDuplicateGroup> groups,
  }) : _groups = groups.toList(growable: true);

  final List<ComicDuplicateGroup> _groups;
  final List<Set<String>> mergedGroups = <Set<String>>[];

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({String? comicId}) async {
    if (comicId == null || comicId.trim().isEmpty) {
      return List<ComicDuplicateGroup>.unmodifiable(_groups);
    }
    return _groups
        .where((group) => group.comicIds.contains(comicId.trim()))
        .toList(growable: false);
  }

  @override
  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) async {
    mergedGroups.add(Set<String>.from(comicIds));
    _groups.removeWhere((group) => group.comicIds.containsAll(comicIds));
    final ordered = comicIds.toList(growable: false)..sort();
    final target = ordered.first;
    final removed = ordered.skip(1).toSet();
    return ComicDuplicateMergeResult(
      targetComicId: target,
      targetTitle: target,
      mergedComicIds: removed,
      replacements: <String, String>{
        for (final comicId in removed) comicId: target,
      },
      movedEpisodeCount: removed.length,
    );
  }
}
