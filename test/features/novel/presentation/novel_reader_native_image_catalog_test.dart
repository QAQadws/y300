import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
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

final class _FrozenDisplay implements ForumHtmlDisplayImage {
  const _FrozenDisplay(
    this.sourceUrl,
    this.cacheKey,
    this.initialLayout,
    this.htmlSize,
  );
  @override
  final String sourceUrl, cacheKey;
  @override
  final ForumHtmlImageLayout initialLayout;
  @override
  final Size? htmlSize;
  @override
  bool get isSticker => false;
  @override
  Object get identity => (sourceUrl, cacheKey);
}

/// Catalog capture may describe resources only. Any image I/O is a test failure.
final class _SnapshotHost implements ForumHtmlImageHost {
  Size naturalSize = const Size(20, 10);
  final descriptions = <ForumHtmlDisplayImage>[];
  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) {
    final image = _FrozenDisplay(
      url.toString(),
      'image:$imageIndex',
      ForumHtmlImageLayout(displaySize: naturalSize, aspectRatio: 2),
      htmlSize,
    );
    descriptions.add(image);
    return image;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected image work: ${invocation.memberName}');
}

Future<NovelReaderNativePreparedChapter> _chapter([int images = 2]) async {
  final html = List.filled(images, _image).join();
  return _htmlChapter(html);
}

Future<NovelReaderNativePreparedChapter> _htmlChapter(String html) async {
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
    'actual Session fits frozen catalog sources in the containing styled block',
    () async {
      final chapter = await _htmlChapter(
        '<div style="padding-left:10px;padding-right:10px">'
        '<p style="letter-spacing:2px">A$_image B</p></div>',
      );
      final host = _SnapshotHost()..naturalSize = const Size(120, 60);
      final catalog =
          await NovelReaderNativeImageResources(
            chapter: chapter,
            host: host,
            policy: NativeReaderImageTestHost(),
          ).capture(
            cancellation: NovelReaderPaginationCancellationToken(),
            maxCodeUnits: 10000,
            scheduler: const NovelReaderNativeWorkScheduler(nextFrame: _yield),
          );
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 22,
      );
      addTearDown(cache.close);
      final session = ForumBodyTextPageSession(
        document: chapter.document,
        cache: cache,
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 10,
            height: 1,
          ),
          fontRevision: 'catalog-inline',
          linkColor: const Color(0xff0000ff),
          paragraphBefore: 0,
          paragraphAfter: 0,
        ),
        textScaler: const TextScaler.linear(2),
        width: 100,
        height: 100,
        layoutId: 'catalog-inline',
        limits: const ForumBodyTextPageSessionLimits(
          maxPages: 10,
          maxFragments: 100,
          maxParagraphs: 10,
          maxTextCodeUnits: 10000,
          maxRuns: 1000,
          maxIssuedLeases: 16,
        ),
        imageResolver: catalog.resolve,
        inlineImageResolver: (identity, element, style) {
          final source = catalog.sourceFor(identity, element)!;
          final size = catalog.layoutFor(identity, element)!.displaySize!;
          return ForumBodyInlineImageInput.fromSource(
            source: source,
            dimensions: PlaceholderDimensions(
              size: size,
              alignment: ui.PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: size.height,
            ),
          );
        },
      );
      addTearDown(session.close);
      host.naturalSize = const Size(400, 400);
      for (var i = 0; !session.isComplete && i < 10000; i++) {
        session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
      }
      expect(session.isComplete, isTrue);
      final job = session.openPagePreparation(0);
      addTearDown(job.close);
      for (var i = 0; !job.isReady && i < 10000; i++) {
        job.advance(maxFragments: 1, maxParts: 1);
      }
      final prepared = job.takeFragments();
      final view = (prepared.single as ForumBodyPreparedInlineFragment).view;
      final image = view.images.values.single;
      expect(image.rect.size, const Size(76, 38));
      expect(catalog.ownsInline(image.input), isTrue);
      expect(
        image.input.source,
        same(catalog.sourceFor(chapter.identity, image.input.element)),
      );
      expect(image.input.image.initialLayout.displaySize, const Size(120, 60));
      expect(host.descriptions, hasLength(1));
      expect(view.nativeLeases, hasLength(1));
      prepared.single.close();
      expect(cache.activeLeases, 0);
    },
  );

  test('frozen display sources survive fitting and reject equal-value foreign ownership', () async {
    final chapter = await _chapter(), host = _SnapshotHost();
    final resources = NovelReaderNativeImageResources(
      chapter: chapter,
      host: host,
      policy: NativeReaderImageTestHost(),
    );
    Future<NovelReaderNativeImageCatalog> capture({
      Map<String, ForumHtmlImageLayout> layouts = const {},
    }) => resources.capture(
      cancellation: NovelReaderPaginationCancellationToken(),
      maxCodeUnits: 10000,
      scheduler: const NovelReaderNativeWorkScheduler(nextFrame: _yield),
      resolvedLayouts: layouts,
    );
    final before = await capture();
    final first = chapter.document.nodeAtPath('0')! as ForumBodyElement;
    final second = chapter.document.nodeAtPath('1')! as ForumBodyElement;
    final source = before.sourceFor(chapter.identity, first)!;
    expect(source.image, same(host.descriptions.first));
    expect(source.entry, same(before.sequence.entries.first));
    expect(source.entry, same(before.resolve(chapter.identity, first)!.entry));
    expect(source, isNot(same(before.sourceFor(chapter.identity, second))));
    expect(
      before.layoutFor(chapter.identity, first)!.displaySize,
      const Size(20, 10),
    );
    final input = ForumBodyInlineImageInput.fromSource(
      source: source,
      dimensions: const PlaceholderDimensions(
        size: Size(80, 40),
        alignment: ui.PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: 30,
      ),
    );
    final fitted = input.fitWidth(40);
    expect(before.ownsInline(fitted), isTrue);
    expect(fitted.source, same(source));
    expect(host.descriptions, hasLength(2));
    host.naturalSize = const Size(40, 20);
    expect(
      before.layoutFor(chapter.identity, first)!.displaySize,
      const Size(20, 10),
    );
    final after = await capture();
    expect(after.geometryIdentity, isNot(before.geometryIdentity));
    expect(
      after.resolve(chapter.identity, first)!.aspectRatio,
      before.resolve(chapter.identity, first)!.aspectRatio,
    );
    expect(after.ownsInline(fitted), isFalse);
    final equivalent = await capture();
    expect(equivalent.geometryIdentity, after.geometryIdentity);
    final replacement = ForumBodyInlineImageInput.fromSource(
      source: equivalent.sourceFor(chapter.identity, first)!,
      dimensions: fitted.dimensions,
    );
    expect(after.ownsInline(replacement), isFalse);
    final clonedSource = ForumBodyInlineImageSource(
      document: chapter.document,
      element: first,
      image: source.image,
      entry: source.entry,
    );
    expect(
      before.ownsInline(
        ForumBodyInlineImageInput.fromSource(
          source: clonedSource,
          dimensions: input.dimensions,
        ),
      ),
      isFalse,
    );
    final foreign = const ForumBodyParser().parse(
      html: '$_image$_image',
      sourceId: 'source',
      conversionIdentity: 'none',
    );
    expect(
      () => before.sourceFor(
        chapter.identity,
        foreign.nodeAtPath('0')! as ForumBodyElement,
      ),
      throwsStateError,
    );
    final override = await capture(
      layouts: {
        '0': const ForumHtmlImageLayout(
          displaySize: Size(30, 15),
          aspectRatio: 2,
        ),
      },
    );
    expect(
      override.layoutFor(chapter.identity, first)!.displaySize,
      const Size(30, 15),
    );
    expect(
      override
          .sourceFor(chapter.identity, first)!
          .image
          .initialLayout
          .displaySize,
      const Size(40, 20),
    );
  });

  test('invalid frozen dimensions fail before native or image work', () async {
    final chapter = await _chapter(),
        host = _SnapshotHost()..naturalSize = const Size(double.nan, 20);
    await expectLater(
      NovelReaderNativeImageResources(
        chapter: chapter,
        host: host,
        policy: NativeReaderImageTestHost(),
      ).capture(
        cancellation: NovelReaderPaginationCancellationToken(),
        maxCodeUnits: 10000,
      ),
      throwsArgumentError,
    );
  });
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
