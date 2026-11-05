import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_exception.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_image_resources.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_preparation_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';

import '../test_support/native_reader_image_test_host.dart';

const _image = '<img src="https://bbs.yamibo.com/data/attachment/forum/a.png">';
Future<void> _yield() async {}

Future<NovelReaderNativePreparedChapter> _chapter([int images = 2]) async {
  final html = List.filled(images, _image).join();
  return await const DefaultNovelReaderNativePreparationService().prepare(
    episodeId: 'episode',
    sourceId: 'source',
    rawHtml: html,
    semanticDocument: const DiscuzNovelReaderDocumentParser(
      captureSourceProvenance: true,
    ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: const []),
    cancellation: NovelReaderPaginationCancellationToken(),
  ) as NovelReaderNativePreparedChapter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'frozen resource inputs keep distinct source slots and geometry identities',
    () async {
      final chapter = await _chapter();
      final host = NativeReaderImageTestHost();
      final resources = NovelReaderNativeImageResources(
        chapter: chapter,
        host: host,
        policy: host,
      );
      Future<NovelReaderNativeImageCatalog> capture(
        Map<String, ForumHtmlImageLayout> layouts,
      ) => resources.capture(
        cancellation: NovelReaderPaginationCancellationToken(),
        maxCodeUnits: 10000,
        scheduler: const NovelReaderNativeWorkScheduler(nextFrame: _yield),
        resolvedLayouts: layouts,
      );
      final before = await capture({});
      final after = await capture({
        '0': const ForumHtmlImageLayout(aspectRatio: 4),
      });
      final equivalent = await capture({
        '0': const ForumHtmlImageLayout(aspectRatio: 4, isFallback: true),
      });
      final first = chapter.document.nodeAtPath('0')! as ForumBodyElement;
      final second = chapter.document.nodeAtPath('1')! as ForumBodyElement;
      expect(before.resolve(chapter.identity, first)!.aspectRatio, 1);
      expect(after.resolve(chapter.identity, first)!.aspectRatio, 4);
      expect(after.resolve(chapter.identity, second)!.aspectRatio, 1);
      expect(after.geometryIdentity, isNot(before.geometryIdentity));
      expect(after.geometryIdentity, equivalent.geometryIdentity);
      expect(after.sequence.sourceId, 'episode');
      expect(after.sequence.entries.map((entry) => entry.index), [0, 1]);
      expect(
        after.sequence.entries.first,
        same(after.resolve(chapter.identity, first)!.entry),
      );
      expect(() => after.sequence.entries.clear(), throwsUnsupportedError);
      expect(after.owns(before.resolve(chapter.identity, first)!), isFalse);
      final foreign = const ForumBodyParser().parse(
        html: '$_image$_image',
        sourceId: 'source',
        conversionIdentity: 'none',
      );
      expect(
        () => after.resolve(
          chapter.identity,
          foreign.nodeAtPath('0')! as ForumBodyElement,
        ),
        throwsStateError,
      );
      expect(host.dimensions, isEmpty);
      expect(host.callbacks, isEmpty);
    },
  );

  test('resource metadata budget rejects capture before opening native or image work', () async {
    final chapter = await _chapter();
    final host = NativeReaderImageTestHost();
    await expectLater(
      NovelReaderNativeImageResources(
        chapter: chapter,
        host: host,
        policy: host,
      ).capture(
        cancellation: NovelReaderPaginationCancellationToken(),
        maxCodeUnits: 1,
      ),
      throwsA(
        isA<NovelReaderPaginationException>().having(
          (e) => e.code,
          'code',
          'nativeImageBudgetExceeded',
        ),
      ),
    );
    expect(host.dimensions, isEmpty);
    expect(host.callbacks, isEmpty);
  });

  test(
    'large pure catalog yields and cancellation retires its pending capture',
    () async {
      final chapter = await _chapter(128);
      final host = NativeReaderImageTestHost();
      final token = NovelReaderPaginationCancellationToken();
      final gate = Completer<void>();
      var waits = 0;
      final work =
          NovelReaderNativeImageResources(
            chapter: chapter,
            host: host,
            policy: host,
          ).capture(
            cancellation: token,
            maxCodeUnits: 100000,
            scheduler: NovelReaderNativeWorkScheduler(
              nextFrame: () {
                waits++;
                return gate.future;
              },
            ),
          );
      final checked = expectLater(
        work,
        throwsA(
          isA<NovelReaderPaginationException>().having(
            (e) => e.code,
            'code',
            'paginationCancelled',
          ),
        ),
      );
      expect(waits, 1);
      token.cancel();
      await checked;
      gate.complete();
      expect(host.dimensions, isEmpty);
      expect(host.callbacks, isEmpty);
    },
  );
}
