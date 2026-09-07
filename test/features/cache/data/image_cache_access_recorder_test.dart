import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/data/services/image_cache_access_recorder.dart';

void main() {
  test('coalesces keys and commits the newest access in one batch', () async {
    final repository = _RecordingBatchRepository();
    final recorder = BufferedImageCacheAccessRecorder(
      repository: repository,
      flushInterval: const Duration(days: 1),
    );
    addTearDown(recorder.dispose);
    final first = DateTime(2026, 1, 1);
    final latest = DateTime(2026, 1, 2);

    recorder.record('same', first);
    recorder.record('same', latest);
    recorder.record('other', first);
    await recorder.flush();

    expect(repository.batches, hasLength(1));
    expect(repository.batches.single, <String, DateTime>{
      'same': latest,
      'other': first,
    });
    expect(repository.individualTouches, isEmpty);
  });

  test('keeps pending accesses after a failed batch', () async {
    final repository = _RecordingBatchRepository()..failNextBatch = true;
    final recorder = BufferedImageCacheAccessRecorder(
      repository: repository,
      flushInterval: const Duration(days: 1),
    );
    addTearDown(recorder.dispose);

    recorder.record('retry', DateTime(2026, 1, 1));
    await recorder.flush();
    expect(repository.batches, isEmpty);

    await recorder.flush();
    expect(repository.batches.single.keys, <String>['retry']);
  });
}

class _RecordingBatchRepository
    implements ImageCacheRepository, ImageCacheBatchAccessRepository {
  final batches = <Map<String, DateTime>>[];
  final individualTouches = <String>[];
  bool failNextBatch = false;

  @override
  Future<void> touchMany(Map<String, DateTime> accesses) async {
    if (failNextBatch) {
      failNextBatch = false;
      throw StateError('synthetic batch failure');
    }
    batches.add(Map<String, DateTime>.of(accesses));
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {
    individualTouches.add(cacheKey);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
