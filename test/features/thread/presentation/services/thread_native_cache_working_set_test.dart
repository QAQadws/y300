import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/services/thread_body_presentation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final lowMemory in [false, true]) {
    test(
      'short-paragraph working set remains cached below the byte budget ($lowMemory)',
      () {
        final store = ThreadBodyPresentationStore(lowMemory: lowMemory);
        addTearDown(store.clear);
        final cache = store.nativeCache.paragraphs;
        final document = const ForumBodyParser().parse(
          html: List.generate(1000, (i) => '<p>Forum paragraph $i.</p>').join(),
          sourceId: 'working-set',
          conversionIdentity: 'none',
        );
        final styles = const ForumBodyStyleResolver().resolve(
          document,
          ForumBodyReaderStyle(
            textStyle: const TextStyle(
              fontFamily: 'Ahem',
              fontSize: 10,
              height: 1,
            ),
            fontRevision: 'ahem',
            linkColor: Colors.blue,
            paragraphAfter: 0,
          ),
        );
        final inputs = List.generate(
          1000,
          (i) => const ForumBodyParagraphContentBuilder().build(
            document: document,
            styles: styles,
            path: '$i',
          ),
        );
        var nativeBytes = 0;
        for (final content in inputs) {
          final lease = cache.acquire(content: content, width: 240);
          nativeBytes += lease.nativeLayoutEstimatedBytes;
          lease.release();
        }
        expect(nativeBytes, lessThan(cache.maxEstimatedBytes));
        expect(cache.activeLeases, 0);
        final builds = cache.layoutBuildCount;
        for (final content in inputs) {
          final lease = cache.tryAcquireCached(content: content, width: 240);
          expect(lease, isNotNull);
          lease!.release();
        }
        expect(cache.layoutBuildCount, builds);
        expect(
          cache.estimatedRetainedBytes,
          lessThanOrEqualTo(cache.maxEstimatedBytes),
        );
        final current = cache.acquire(content: inputs.first, width: 240);
        store.trimNativeCache();
        expect(current.isActive, true);
        expect(cache.activeLeases, 1);
        current.release();
        store.clear();
        expect(cache.isClosed, true);
        expect(cache.activeLeases, 0);
        expect(cache.estimatedRetainedBytes, 0);
      },
    );
  }
}
