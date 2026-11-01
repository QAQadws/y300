import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart';

const _sides = [
  ForumBodyRubySide.over,
  ForumBodyRubySide.under,
  ForumBodyRubySide.over,
];

class _Fixture {
  _Fixture({bool dense = false}) {
    document = const ForumBodyParser().parse(
      html: dense
          ? '<p>${List.generate(200, (_) => '<span style="font-size:1px;white-space:pre"> </span>').join()}</p>'
          : '<p>'
                '<span style="font-size:20px;white-space:pre"> </span>'
                '<span style="font-size:10px;white-space:pre">  </span>'
                '<span style="font-size:15px;white-space:pre">    </span>'
                '<span style="font-size:8px;white-space:pre"> </span>'
                '<span style="font-size:40px">X</span>'
                '<span style="font-size:30px">Y</span>'
                '</p>',
      sourceId: 'actual-soft-space-members',
      conversionIdentity: 'none',
    );
    styles = const ForumBodyStyleResolver().resolve(
      document,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
      ),
    );
    contents = [
      for (var i = 0; i < (dense ? 200 : 6); i++)
        const ForumBodyParagraphContentBuilder().build(
          document: document,
          styles: styles,
          path: '0/$i',
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
    ];
  }
  late final ForumBodyDocument document;
  late final ForumBodyStyleResult styles;
  late final List<ForumBodyParagraphContent> contents;
  final cache = ForumBodyParagraphCache(
    maxEntries: 256,
    maxEstimatedBytes: 16 << 20,
  );

  ForumBodyTextRequest request(int index) =>
      ForumBodyTextRequest.paragraph(contents[index]);

  ForumBodyRubySoftSpaceRequest source({
    List<ForumBodyRubySoftSpaceMemberRequest>? members,
    List<ForumBodyRubySide> sides = _sides,
    int beforeColumn = 1,
    double maxWidth = 16384,
  }) => ForumBodyRubySoftSpaceRequest(
    beforeColumn: beforeColumn,
    members:
        members ??
        [
          (request: request(0), annotationIndex: null, gap: 0),
          (request: request(1), annotationIndex: null, gap: 0),
          (request: request(2), annotationIndex: 0, gap: 2),
          (request: request(3), annotationIndex: 2, gap: 1),
        ],
    sides: sides,
    maxWidth: maxWidth,
  );

  List<ForumBodyRubySoftSpaceMeasuredMember> measure(
    ForumBodyRubySoftSpaceRequest request,
  ) => [
    for (final member in request.members)
      ForumBodyRubySoftSpaceMeasuredMember(
        annotationIndex: member.annotationIndex,
        font: font(
          member.request,
          side: member.annotationIndex == null
              ? ForumBodyRubySide.over
              : request.sides[member.annotationIndex!],
          gap: member.gap,
        ),
      ),
  ];

  ForumBodyRubyAnnotationMetrics font(
    ForumBodyTextRequest request, {
    required ForumBodyRubySide side,
    double gap = 0,
  }) {
    final lease = request.acquire(
      cache,
      width: 200,
      textScaler: TextScaler.noScaling,
      cachedOnly: false,
    )!;
    try {
      return ForumBodyRubyAnnotationMetrics.measure(
        cache: cache,
        lease: lease,
        side: side,
        gap: gap,
      );
    } finally {
      lease.release();
    }
  }

  void close() {
    cache.close();
    expect(cache.activeLeases, 0);
    expect(cache.estimatedRetainedBytes, 0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final direction in TextDirection.values) {
    for (final q in [1, 7, 32]) {
      test(
        'actual mixed gaps keep levels and bound numeric work $direction q=$q',
        () {
          final f = _Fixture();
          addTearDown(f.close);
          final measured = f.measure(f.source());
          final work = ForumBodyRubySoftSpaceComposition(
            members: measured,
            sides: _sides,
            direction: direction,
          );
          expect(() => work.result, throwsStateError);
          var parts = 0;
          final native = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
          while (!work.isComplete && parts < 100) {
            final used = work.advance(maxParts: q);
            expect(used, inInclusiveRange(1, q));
            parts += used;
            expect((
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
            ), native);
            expect(f.cache.activeLeases, 0);
          }
          expect(parts, 15); // Two passes per rank/member and one publication.
          final m = work.result;
          expect(m.size, const Size(60, 46));
          expect(m.baseline, 42);
          expect(m.level.baseAscent + m.level.baseDescent, 20);
          expect(m.level.annotations.map((r) => r.hasAnnotation), [
            true,
            false,
            true,
          ]);
          expect(m.alignmentSignature, '010');
          expect(m.members.map((p) => p.input), measured);
          expect(
            m.members.map((p) => p.offset.dx),
            direction == TextDirection.ltr ? [10, 30, 0, 26] : [30, 10, 0, 26],
          );
          for (final member in m.members) {
            final box = member.input.font.bounds.shift(member.offset);
            expect(box.left, greaterThanOrEqualTo(-1e-4));
            expect(box.right, lessThanOrEqualTo(m.size.width + 1e-4));
            expect(box.top, greaterThanOrEqualTo(member.bandTop - 1e-4));
            expect(box.bottom, lessThanOrEqualTo(member.bandBottom + 1e-4));
          }
          expect(() => m.members.clear(), throwsUnsupportedError);
          expect(() => m.level.annotations.clear(), throwsUnsupportedError);
          expect(() => work.advance(maxParts: q), throwsStateError);
          f.close();
          expect(m.members.length, 4); // Numeric results outlive native owners.
        },
      );
    }
  }

  test('annotation-only gap never acquires an opposite base font strut', () {
    final f = _Fixture();
    addTearDown(f.close);
    final source = f.source(
      members: [(request: f.request(3), annotationIndex: 2, gap: 1)],
    );
    final m = ForumBodyRubySoftSpaceMetrics.compose(
      members: f.measure(source),
      sides: source.sides,
    );
    expect(source.nativeHandleCount, 1);
    expect(f.cache.layoutBuildCount, 1);
    expect(f.cache.pictureBuildCount, 0);
    expect(m.level.baseAscent, 0);
    expect(m.level.baseDescent, 0);
    expect(m.level.annotations.map((r) => r.hasAnnotation), [
      false,
      false,
      true,
    ]);
    expect(m.size, const Size(8, 9));
    expect(m.members.single.input.annotationIndex, 2);
    expect(m.members.single.bandTop, 0);
  });

  test('base-only gap contributes only its real base fonts', () {
    final f = _Fixture();
    addTearDown(f.close);
    final source = f.source(
      members: [
        (request: f.request(0), annotationIndex: null, gap: 0),
        (request: f.request(1), annotationIndex: null, gap: 0),
      ],
    );
    final m = ForumBodyRubySoftSpaceMetrics.compose(
      members: f.measure(source),
      sides: source.sides,
    );
    expect(source.nativeHandleCount, 2);
    expect(m.level.annotations.every((r) => !r.hasAnnotation), isTrue);
    expect(m.size, const Size(40, 20));
    expect(m.members.map((p) => p.input.annotationIndex), [null, null]);
  });

  for (final q in [1, 7, 32]) {
    test('dense original rank/member work is bounded q=$q', () {
      final f = _Fixture(dense: true);
      addTearDown(f.close);
      final sides = List.generate(100, (i) => _sides[i % 2]);
      final source = f.source(
        sides: sides,
        members: [
          for (var i = 0; i < 200; i++)
            (request: f.request(i), annotationIndex: i ~/ 2, gap: 0),
        ],
      );
      final measured = f.measure(source);
      final work = ForumBodyRubySoftSpaceComposition(
        members: measured,
        sides: sides,
      );
      var parts = 0;
      while (!work.isComplete && parts < 1000) {
        final used = work.advance(maxParts: q);
        expect(used, inInclusiveRange(1, q));
        parts += used;
        expect(f.cache.layoutBuildCount, 200);
        expect(f.cache.pictureBuildCount, 0);
        expect(f.cache.activeLeases, 0);
      }
      expect(parts, 601);
      expect(work.result.size, const Size(2, 100));
      expect(work.result.level.baseAscent, 0);
      expect(work.result.level.baseDescent, 0);
      expect(work.result.members.map((m) => m.input), measured);
    });
  }

  test(
    'larger row targets change only vertical positions using the same stack',
    () {
      final f = _Fixture();
      addTearDown(f.close);
      final members = f.measure(f.source());
      final intrinsic = ForumBodyRubySoftSpaceMetrics.compose(
        members: members,
        sides: _sides,
      );
      final base = f
          .request(4)
          .acquire(
            f.cache,
            width: 200,
            textScaler: TextScaler.noScaling,
            cachedOnly: false,
          )!;
      final annotation = f
          .request(5)
          .acquire(
            f.cache,
            width: 200,
            textScaler: TextScaler.noScaling,
            cachedOnly: false,
          )!;
      final empty = ForumBodyParagraphContent.anonymousInline(
        identity: f.document.identity,
        fontRevision: f.styles.fontRevision,
        styleRevision: f.styles.resolverRevision,
        style: f.contents.first.style,
      );
      late final ForumBodyRubyGroupMetrics column;
      try {
        column = ForumBodyRubyGroupMetrics.measureLayers(
          cache: f.cache,
          baseLease: base,
          annotations: [
            (
              content: annotation.content,
              lease: annotation,
              gap: 3.0,
              side: _sides[0],
            ),
            for (final side in _sides.skip(1))
              (content: empty, lease: null, gap: 0.0, side: side),
          ],
        );
      } finally {
        base.release();
        annotation.release();
      }
      final union = ForumBodyRubyLevelUnion.fromLevel(intrinsic.level);
      final merge = union.merge(column);
      while (!merge.isComplete) {
        expect(merge.advance(maxParts: 1), 1);
      }
      final before = f.cache.layoutBuildCount;
      final aligned = ForumBodyRubySoftSpaceMetrics.compose(
        members: members,
        sides: _sides,
        level: union.value,
      );
      expect(aligned.size.width, intrinsic.size.width);
      expect(
        aligned.members.map((p) => p.offset.dx),
        intrinsic.members.map((p) => p.offset.dx),
      );
      expect(aligned.members.map((p) => p.input), members);
      expect(aligned.level.baseAscent + aligned.level.baseDescent, 40);
      expect(aligned.size.height, greaterThan(intrinsic.size.height));
      expect(f.cache.layoutBuildCount, before);
    },
  );

  test(
    'requests snapshot original roles, source order and exact native members',
    () {
      final f = _Fixture();
      addTearDown(f.close);
      final members = f.source().members.toList();
      final sides = _sides.toList();
      final request = f.source(members: members, sides: sides);
      members.clear();
      sides.clear();
      expect(request.nativeHandleCount, 4);
      expect(request.members.map((m) => m.annotationIndex), [null, null, 0, 2]);
      final mapped = request.mapRequests(
        (r) => ForumBodyTextRequest.paragraph(r.content),
      );
      expect(mapped.beforeColumn, 1);
      expect(
        mapped.nativeRequests.map((r) => r.content),
        request.nativeRequests.map((r) => r.content),
      );
      expect(
        mapped.members.map((m) => (m.annotationIndex, m.gap)),
        request.members.map((m) => (m.annotationIndex, m.gap)),
      );
      expect(() => request.members.clear(), throwsUnsupportedError);
      expect(() => request.nativeRequests.clear(), throwsUnsupportedError);
      expect(() => request.sides.clear(), throwsUnsupportedError);
    },
  );

  for (var bad = 0; bad < 10; bad++) {
    test(
      'invalid real whitespace request rejects without native work mode=$bad',
      () {
        final f = _Fixture();
        addTearDown(f.close);
        expect(
          () => f.source(
            beforeColumn: bad == 0 ? 0 : 1,
            maxWidth: bad == 1 ? double.nan : 16384,
            sides: bad == 2 ? [] : _sides,
            members: switch (bad) {
              3 => [],
              4 => [(request: f.request(4), annotationIndex: null, gap: 0)],
              5 => [(request: f.request(0), annotationIndex: -1, gap: 0)],
              6 => [(request: f.request(0), annotationIndex: 3, gap: 0)],
              7 => [(request: f.request(0), annotationIndex: null, gap: 1)],
              8 => [
                for (var i = 0; i < 2; i++)
                  (request: f.request(0), annotationIndex: 0, gap: 0),
              ],
              9 => [
                (request: f.request(0), annotationIndex: 2, gap: 0),
                (request: f.request(1), annotationIndex: 0, gap: 0),
              ],
              _ => null,
            },
          ),
          throwsA(isA<ForumBodyRubyGroupException>()),
        );
        expect(f.cache.layoutBuildCount, 0);
      },
    );
  }

  for (var bad = 0; bad < 4; bad++) {
    test('late numeric failure cannot publish or resume mode=$bad', () {
      final f = _Fixture();
      addTearDown(f.close);
      final members = f.measure(f.source());
      final work = ForumBodyRubySoftSpaceComposition(
        members: bad == 0
            ? members.reversed.toList()
            : bad == 1
            ? [
                ...members.take(3),
                ForumBodyRubySoftSpaceMeasuredMember(
                  annotationIndex: -1,
                  font: members.last.font,
                ),
              ]
            : members,
        sides: bad == 2 ? [ForumBodyRubySide.under, ..._sides.skip(1)] : _sides,
        maxWidth: bad == 3 ? 59 : 16384,
      );
      final before = f.cache.layoutBuildCount;
      expect(() {
        while (!work.isComplete) {
          work.advance(maxParts: 1);
        }
      }, throwsA(isA<ForumBodyRubyGroupException>()));
      expect(() => work.result, throwsStateError);
      expect(() => work.advance(maxParts: 1), throwsStateError);
      expect(f.cache.layoutBuildCount, before);
    });
  }

  test(
    'source-free, empty and foreign contexts cannot stand in for actual gaps',
    () {
      final f = _Fixture();
      addTearDown(f.close);
      final foreign = const ForumBodyParser().parse(
        html: '<p style="white-space:pre"> </p>',
        sourceId: 'foreign-gap',
        conversionIdentity: 'none',
      );
      final reader = ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'ahem',
        linkColor: const Color(0xff0000ff),
      );
      final foreignContent = const ForumBodyParagraphContentBuilder().build(
        document: foreign,
        styles: const ForumBodyStyleResolver().resolve(foreign, reader),
        path: '0',
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      final empty = ForumBodyParagraphContent.anonymousInline(
        identity: f.document.identity,
        fontRevision: f.styles.fontRevision,
        styleRevision: f.styles.resolverRevision,
        style: f.contents.first.style,
      );
      for (final invalid in [empty, foreignContent]) {
        expect(
          () => f.source(
            members: [
              (request: f.request(0), annotationIndex: null, gap: 0),
              (
                request: ForumBodyTextRequest.paragraph(invalid),
                annotationIndex: 0,
                gap: 0,
              ),
            ],
          ),
          throwsA(isA<ForumBodyRubyGroupException>()),
        );
      }
      expect(f.cache.layoutBuildCount, 0);
    },
  );

  test(
    'numeric snapshots and too-small row targets cannot borrow missing levels',
    () {
      final f = _Fixture();
      addTearDown(f.close);
      final members = f.measure(f.source());
      final workMembers = members.toList();
      final sides = _sides.toList();
      final work = ForumBodyRubySoftSpaceComposition(
        members: workMembers,
        sides: sides,
      );
      workMembers.clear();
      sides.clear();
      while (!work.isComplete) {
        work.advance(maxParts: 1);
      }
      expect(work.result.members.map((m) => m.input), members);
      final baseOnly = ForumBodyRubySoftSpaceMetrics.compose(
        members: members.take(2).toList(),
        sides: _sides,
      );
      final invalid = ForumBodyRubySoftSpaceComposition(
        members: members,
        sides: _sides,
        level: baseOnly.level,
      );
      expect(() {
        while (!invalid.isComplete) {
          invalid.advance(maxParts: 1);
        }
      }, throwsA(isA<ForumBodyRubyGroupException>()));
      expect(() => invalid.result, throwsStateError);
      expect(() => invalid.advance(maxParts: 1), throwsStateError);
    },
  );
}
