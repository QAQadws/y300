import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/models/novel_reader_source_provenance.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_anchor_map.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_anchor_binder.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_hint_search.dart';

const _url = 'https://bbs.yamibo.com/data/attachment/forum/a.png';

final class _Fixture {
  _Fixture(
    this.html, {
    NovelReaderSourceProvenanceLimits limits =
        const NovelReaderSourceProvenanceLimits(),
  }) {
    semantic = DiscuzNovelReaderDocumentParser(
      captureSourceProvenance: true,
      sourceProvenanceLimits: limits,
    ).parse(episodeId: 'episode', rawHtml: html, fallbackParagraphs: const []);
    body = const ForumBodyParser().parse(
      html: html.trim(),
      sourceId: 'source',
      conversionIdentity: 'none',
    );
  }
  final String html;
  late final NovelReaderDocument semantic;
  late final ForumBodyDocument body;
  NovelReaderNativeAnchorMap bind({
    List<NovelReaderImageSourceOrigin>? images,
    NovelReaderNativeAnchorBindingLimits limits =
        const NovelReaderNativeAnchorBindingLimits(),
  }) => NovelReaderNativeAnchorBinder(limits: limits).bind(
    episodeId: 'episode',
    sourceId: 'source',
    bodyDocument: body,
    semanticDocument: images == null
        ? semantic
        : NovelReaderDocument(
            episodeId: semantic.episodeId,
            rawHtmlHash: semantic.rawHtmlHash,
            body: semantic.body,
            plainText: semantic.plainText,
            wordCount: semantic.wordCount,
            textConversionIdentity: semantic.textConversionIdentity,
            sourceProvenance: NovelReaderSourceProvenance(
              inputHash: semantic.sourceProvenance!.inputHash,
              origins: semantic.sourceProvenance!.origins,
              images: images,
            ),
          ),
  );
}

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource(this.cacheKey);
  @override
  final String cacheKey;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('image-only input retains exact paths, duplicate slots and no text coordinates', () {
    final f = _Fixture(
      '<!--comment--><img zoomfile="$_url" src="thumb"><img src="$_url">',
    );
    final map = f.bind();
    expect(f.semantic.sourceProvenance!.origins, isEmpty);
    expect(map.segments, isEmpty);
    expect(map.sourceRuneLength, 0);
    expect(map.images.map((e) => e.path), ['1', '2']);
    expect(map.images.map((e) => e.imageIndex), [0, 1]);
    expect(map.images.map((e) => e.anchor.nodeId), ['node-0', 'node-1']);
    for (final image in map.images) {
      expect(map.imageAtPath(image.path), same(image));
      expect(image.url, _url);
      expect(image.rawSource, _url);
      expect(image.anchor.textOffset, 0);
      expect(image.anchor.formatVersion, 1);
      expect(
        image.anchor.textIdentity,
        NovelReaderAnchorFormat.layoutTextIdentity(
          '',
          f.semantic.sourceProvenance!.inputHash,
        ),
      );
      expect(map.sourceCandidates(image.anchor), isEmpty);
      expect(map.imageCandidatePaths(image.anchor), [image.path]);
      expect(
        map.imageCandidatePaths(
          image.anchor.copyWith(textOffset: 1),
          allowNodeCompatibility: true,
        ),
        isEmpty,
      );
      expect(map.hasVerifiedTextIdentity(image.anchor), isTrue);
    }
    expect(() => map.images.clear(), throwsUnsupportedError);
  });

  test('structured and linked images bind their actual walk without swallowing adjacent text', () {
    final f = _Fixture(
      '<div>A<img src="$_url"><b>B</b>'
      '<a href="https://bbs.yamibo.com/">C<img src="$_url"></a></div>'
      '<a href="https://bbs.yamibo.com/"><img src="$_url"></a>',
    );
    final map = f.bind();
    expect(map.images.map((e) => e.path), ['0/1', '0/3/1', '1/0']);
    expect(map.images.map((e) => e.anchor.nodeId), [
      'node-1',
      'node-2',
      'node-3',
    ]);
    expect(f.semantic.blocks.whereType<RichImageBlock>(), hasLength(3));
    expect(f.semantic.plainText, 'ABC');
    expect(map.segments, hasLength(3));
    expect(map.images.map((e) => e.imageIndex), [0, 1, 2]);
  });

  test('image discovery respects excluded subtrees and existing forum chrome policy', () {
    final f = _Fixture(
      '<div><button><img src="$_url"></button></div>'
      '<p><img src="https://bbs.yamibo.com/static/image/common/smile.gif"></p>'
      '<img src="$_url">',
    );
    final map = f.bind();
    expect(f.semantic.blocks.whereType<RichImageBlock>(), hasLength(1));
    expect(map.images.single.path, '2');
    expect(map.images.single.imageIndex, 0);
  });

  test('whole-input identity prevents repeated image insertion from appearing exact', () {
    final before = _Fixture('<img src="$_url"><img src="$_url">').bind();
    final after = _Fixture(
      '<img src="$_url"><img src="$_url"><img src="$_url">',
    ).bind();
    final old = before.images.last.anchor;
    expect(after.hasVerifiedTextIdentity(old), isFalse);
    expect(after.imageCandidatePaths(old), isEmpty);
    expect(after.imageCandidatePaths(old, allowNodeCompatibility: true), ['1']);
    expect(
      after.imageCandidatePaths(old.copyWith(formatVersion: 900)),
      isEmpty,
    );
    expect(
      after.imageCandidatePaths(
        old.copyWith(formatVersion: 900),
        allowNodeCompatibility: true,
      ),
      ['1'],
    );
  });

  for (final limits in [
    const NovelReaderSourceProvenanceLimits(maxEntries: 1),
    const NovelReaderSourceProvenanceLimits(maxSourceCodeUnits: 1),
    const NovelReaderSourceProvenanceLimits(maxPathCodeUnits: 1),
  ]) {
    test(
      'resource capture shares text budgets and fails the whole sidecar: $limits',
      () {
        final f = _Fixture('<p>A</p><img src="$_url">', limits: limits);
        expect(f.semantic.sourceProvenance, isNull);
        expect(f.semantic.plainText, 'A');
        expect(f.semantic.blocks.whereType<RichImageBlock>(), hasLength(1));
      },
    );
  }

  test(
    'uncaptured images do not create an apparently usable source sidecar',
    () {
      final semantic = const DiscuzNovelReaderDocumentParser().parse(
        episodeId: 'episode',
        rawHtml: '<a href="https://bbs.yamibo.com/"><img src="$_url"></a>',
        fallbackParagraphs: const [],
      );
      expect(semantic.sourceProvenance, isNull);
      expect(semantic.blocks.whereType<RichImageBlock>(), hasLength(1));
    },
  );

  test(
    'foreign path, raw source, semantic target or duplicate origin is rejected',
    () {
      final f = _Fixture('<p>A</p><img src="$_url"><img src="$_url">');
      final valid = f.semantic.sourceProvenance!.images;
      for (final origins in [
        [
          NovelReaderImageSourceOrigin(
            path: '0/0',
            nodeId: valid.first.nodeId,
            rawSource: _url,
          ),
        ],
        [
          NovelReaderImageSourceOrigin(
            path: '1',
            nodeId: valid.first.nodeId,
            rawSource: 'thumb',
          ),
        ],
        [
          const NovelReaderImageSourceOrigin(
            path: '1',
            nodeId: 'node-0',
            rawSource: _url,
          ),
        ],
        [valid.first, valid.first],
        [valid.last, valid.first],
      ]) {
        expect(
          () => f.bind(images: origins),
          throwsA(isA<NovelReaderNativeAnchorBindingException>()),
        );
      }
      expect(
        () => f.bind(
          limits: const NovelReaderNativeAnchorBindingLimits(
            origins: NovelReaderSourceProvenanceLimits(maxEntries: 2),
          ),
        ),
        throwsA(isA<NovelReaderNativeAnchorBindingException>()),
      );
    },
  );

  test('image hints scan exact fragment paths, never a neighboring zero-length source range', () {
    final f = _Fixture('<img src="$_url"><img src="$_url"><img src="$_url">');
    final anchors = f.bind();
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final session = ForumBodyTextPageSession(
      document: f.body,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontSize: 10),
        fontRevision: 'system',
        linkColor: const Color(0xff0000ff),
      ),
      cache: cache,
      layoutId: 'images',
      width: 100,
      height: 50,
      limits: const ForumBodyTextPageSessionLimits(
        maxPages: 10,
        maxFragments: 10,
        maxParagraphs: 10,
        maxTextCodeUnits: 10000,
        maxRuns: 0,
        maxIssuedLeases: 3,
      ),
      imageResolver: (identity, node) {
        final source = anchors.imageAtPath(node.path)!;
        return ForumBodyImageInput(
          identity: identity,
          element: node,
          entry: ForumHtmlReadableImageEntry(
            index: source.imageIndex,
            url: source.url,
            rawSrc: source.rawSource,
            resource: _Resource('slot:${source.imageIndex}'),
          ),
          layout: const ForumHtmlImageLayout(aspectRatio: 2),
        );
      },
    );
    addTearDown(session.close);
    while (!session.isComplete) {
      session.advance(maxEvents: 1, maxLines: 1);
    }
    for (final (index, image) in anchors.images.indexed) {
      final search = NovelReaderNativePageHintSearch(
        snapshot: session.snapshot,
        layoutId: 'images',
        anchors: anchors,
        anchor: image.anchor,
        maxBufferedCandidates: 1,
      );
      final pages = <int>[];
      while (!search.isComplete) {
        final step = search.advance(maxPages: 1, maxFragments: 1);
        expect(step.fragmentsRead, lessThanOrEqualTo(1));
        pages.addAll(search.takeCandidates().map((e) => e.pageIndex));
      }
      expect(pages, [index]);
      search.close();
    }
    expect(cache.layoutBuildCount, 0);
    expect(anchors.sourceRuneLength, 0);
  });
}
