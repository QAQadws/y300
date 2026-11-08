import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/services/image_cache_file_access.dart';

void main() {
  test(
    'overlapping and failed mutations retire resolution epochs until idle',
    () async {
      final access = ImageCacheFileAccess();
      final original = access.reusableEpoch;
      final first = Completer<int>();
      final second = Completer<int>();
      final a = access.mutate(() => first.future);
      final b = access.mutate(() => second.future);
      expect(access.reusableEpoch, isNull);
      first.complete(1);
      final publishedA = await a;
      expect(publishedA.value, 1);
      expect(access.reusableEpoch, isNull);
      second.complete(2);
      final publishedB = await b;
      expect(access.reusableEpoch, same(publishedB.epoch));
      expect(access.reusableEpoch, isNot(same(original)));
      expect(access.reusableEpoch, isNot(same(publishedA.epoch)));
      await expectLater(
        access.mutate<void>(() async => throw StateError('write')),
        throwsStateError,
      );
      expect(access.reusableEpoch, isNotNull);
      expect(access.reusableEpoch, isNot(same(publishedB.epoch)));
    },
  );

  test('publication waits for an active deletion of the same key', () async {
    final access = ImageCacheFileAccess();
    final started = Completer<void>();
    final release = Completer<void>();
    final deletion = access.deleteIfIdle('image', () async {
      started.complete();
      await release.future;
    });
    await started.future;
    var published = false;
    final publication = access.protect('image', () async {
      published = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(published, isFalse);

    // Unrelated images are not held behind this file's deletion.
    expect(await access.protect('other', () async => 7), 7);
    release.complete();
    expect(await deletion, isTrue);
    await publication;
    expect(published, isTrue);
  });

  test('read and deletion failures always release their key', () async {
    final access = ImageCacheFileAccess();
    await expectLater(
      access.protect<void>('image', () async => throw StateError('read')),
      throwsStateError,
    );
    await expectLater(
      access.deleteIfIdle('image', () async => throw StateError('delete')),
      throwsStateError,
    );
    expect(await access.protect('image', () async => 7), 7);
    expect(await access.deleteIfIdle('image', () async {}), isTrue);
  });

  test(
    'cleanup skips files until all concurrent publications finish',
    () async {
      final access = ImageCacheFileAccess();
      final releaseFirst = Completer<void>();
      final releaseSecond = Completer<void>();
      final first = access.protect('image', () => releaseFirst.future);
      final second = access.protect('image', () => releaseSecond.future);
      expect(await access.deleteIfIdle('image', () async {}), isFalse);
      releaseFirst.complete();
      await first;
      expect(await access.deleteIfIdle('image', () async {}), isFalse);
      releaseSecond.complete();
      await second;
      expect(await access.deleteIfIdle('image', () async {}), isTrue);
    },
  );
}
