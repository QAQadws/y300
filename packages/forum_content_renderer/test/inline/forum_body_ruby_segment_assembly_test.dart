import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_segment_layout.dart';

import 'test_support/ruby_segment_fixture.dart';
import 'test_support/ruby_row_fixture.dart';

ForumBodyRubySegmentAssembly _assembly(
  RubySegmentFixture fixture,
  ForumBodyRubySegmentMetrics metrics,
  List<ForumBodyRubyGroupLayout> columns, {
  List<ForumBodyParagraphContent>? spans,
  void Function()? ensureOwner,
}) => ForumBodyRubySegmentAssembly(
  cache: fixture.cache,
  metrics: metrics,
  columns: [
    for (final column in columns)
      (
        base: column.inspectMembers().base.content,
        annotations: [
          for (final item in column.inspectMembers().annotations) item.content,
        ],
      ),
  ],
  spans: spans ?? fixture.annotations,
  ensureOwner: ensureOwner,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final q in [1, 7, 32]) {
    test(
      'actual 100-rank columns and spans assemble within q=$q without final rescan',
      () {
        final fixture = RubySegmentFixture(dense: true);
        addTearDown(fixture.close);
        final metrics = fixture.compose();
        final columns = fixture.prepareColumns(metrics);
        final job = _assembly(fixture, metrics, columns);
        addTearDown(job.close);
        var units = 0;
        var calls = 0;
        void drain() {
          while (job.hasPendingMember) {
            final before = (
              fixture.cache.layoutBuildCount,
              fixture.cache.pictureBuildCount,
              fixture.cache.activeLeases,
            );
            final step = job.advance(maxParts: q);
            expect(step, inInclusiveRange(1, q));
            units += step;
            calls++;
            expect((
              fixture.cache.layoutBuildCount,
              fixture.cache.pictureBuildCount,
              fixture.cache.activeLeases,
            ), before);
          }
        }

        for (final (index, column) in columns.indexed) {
          job.addColumn(column);
          if (q == 1) {
            expect(job.advance(maxParts: q), 1);
            units++;
            calls++;
            expect(
              job.preparedColumnCount,
              index,
            ); // Only its header was checked.
          }
          drain();
          expect(job.preparedColumnCount, index + 1);
        }
        expect(
          job.advance(maxParts: q),
          0,
        ); // It owns no next source member yet.
        for (final (index, content) in fixture.annotations.indexed) {
          job.addSpan((content: content, lease: fixture.lease(content)));
          drain();
          expect(job.preparedSpanCount, index + 1);
        }
        while (!job.isReady) {
          units += job.advance(maxParts: q);
          calls++;
        }
        expect(units, 303); // 2 * (header+100 ranks) +100 spans +publication.
        expect(calls, greaterThanOrEqualTo((303 / q).ceil()));
        expect(job.nativeLeases.length, 102);
        final before = (
          fixture.cache.layoutBuildCount,
          fixture.cache.pictureBuildCount,
          fixture.cache.activeLeases,
        );
        final layout = job.takeLayout();
        job.close();
        try {
          expect((
            fixture.cache.layoutBuildCount,
            fixture.cache.pictureBuildCount,
            fixture.cache.activeLeases,
          ), before);
          expect(job.nativeLeases, isEmpty);
          expect(layout.nativeLeases.length, 102);
          final box = layout
              .selectionBoxesForSpan(spanIndex: 99, startUtf16: 1, endUtf16: 2)
              .single;
          final hit = layout.sourceAt(
            Offset(box.left + .001, (box.top + box.bottom) / 2),
          );
          expect(hit.spanIndex, 99);
          expect(hit.position.isExact, isTrue);
          expect(
            hit.position.sourceRune,
            fixture.annotations.last.projection.sourceAtUtf16(1).sourceRune,
          );
        } finally {
          layout.close();
        }
        fixture.close();
        expect(fixture.cache.activeLeases, 0);
        expect(fixture.cache.estimatedRetainedBytes, 0);
      },
    );
  }

  for (final cancel in [false, true]) {
    test(
      '100 actual column glyph ranks validate individually, cancel=$cancel',
      () {
        final fixture = RubyRowFixture();
        addTearDown(fixture.close);
        final metrics = ForumBodyRubySegmentMetrics.compose(
          columns: fixture.metrics,
          spans: const [],
        );
        final columns = <ForumBodyRubyGroupLayout>[];
        ForumBodyRubySegmentAssembly? job;
        try {
          for (final request in fixture.columns) {
            final prepare = ForumBodyRubyGroupPreparation.fromLayerRequests(
              cache: fixture.cache,
              base: request.base,
              annotations: request.annotations,
              level: metrics.level,
              ensureOwner: () {},
            );
            try {
              while (!prepare.isReady) {
                prepare.advance(maxParts: 7);
              }
              columns.add(prepare.takeLayout());
            } finally {
              prepare.close();
            }
          }
          expect(fixture.cache.activeLeases, 202);
          job = ForumBodyRubySegmentAssembly(
            cache: fixture.cache,
            metrics: metrics,
            columns: [
              for (final parts in fixture.parts)
                (base: parts.first, annotations: parts.skip(1).toList()),
            ],
            spans: const [],
          );
          final before = (
            fixture.cache.layoutBuildCount,
            fixture.cache.pictureBuildCount,
          );
          var units = 0;
          for (final (index, column) in columns.indexed) {
            job.addColumn(column);
            expect(job.advance(maxParts: 1), 1);
            units++;
            expect(job.preparedColumnCount, index);
            if (cancel) break;
            for (var rank = 0; rank < 100; rank++) {
              expect(job.advance(maxParts: 1), 1);
              units++;
              expect(job.preparedColumnCount, rank == 99 ? index + 1 : index);
            }
          }
          if (cancel) {
            job.close();
            expect(columns.first.isActive, isFalse);
            expect(columns.last.isActive, isTrue);
            expect(fixture.cache.activeLeases, 101);
          } else {
            expect(job.advance(maxParts: 1), 1);
            units++;
            expect(units, 203);
            expect(job.isReady, isTrue);
            final layout = job.takeLayout();
            expect(layout.nativeLeases.length, 202);
            layout.close();
            expect(fixture.cache.activeLeases, 0);
          }
          expect((
            fixture.cache.layoutBuildCount,
            fixture.cache.pictureBuildCount,
          ), before);
        } finally {
          job?.close();
          for (final column in columns) {
            column.close();
          }
        }
      },
    );
  }

  test(
    'canceling a partial column retires only ownership already passed in',
    () {
      final fixture = RubySegmentFixture(dense: true);
      addTearDown(fixture.close);
      final metrics = fixture.compose();
      final columns = fixture.prepareColumns(metrics);
      final job = _assembly(fixture, metrics, columns);
      try {
        job.addColumn(columns.first);
        expect(job.advance(maxParts: 1), 1);
        job.close();
        job.close();
        expect(columns.first.isActive, isFalse);
        expect(columns.last.isActive, isTrue);
        expect(fixture.cache.activeLeases, 101);
        expect(job.nativeLeases, isEmpty);
        expect(() => job.takeLayout(), throwsStateError);
      } finally {
        for (final column in columns) {
          column.close();
        }
        job.close();
      }
    },
  );

  test(
    'owner callback cancellation between quanta cannot publish a late layout',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final metrics = fixture.compose();
      final columns = fixture.prepareColumns(metrics);
      late ForumBodyRubySegmentAssembly job;
      var retire = false;
      job = _assembly(
        fixture,
        metrics,
        columns,
        ensureOwner: () {
          if (retire) job.close();
        },
      );
      try {
        job.addColumn(columns.first);
        job.advance(maxParts: 1);
        retire = true;
        expect(() => job.advance(maxParts: 1), throwsStateError);
        expect(job.isReady, isFalse);
        expect(job.nativeLeases, isEmpty);
        expect(columns.first.isActive, isFalse);
        expect(columns.last.isActive, isTrue);
        expect(fixture.cache.activeLeases, 5);
      } finally {
        for (final column in columns) {
          column.close();
        }
        job.close();
      }
    },
  );

  for (final releaseMember in [false, true]) {
    test(
      'ready transfer rejects late owner/member retirement, member=$releaseMember',
      () {
        final fixture = RubySegmentFixture();
        addTearDown(fixture.close);
        final metrics = fixture.compose();
        final columns = fixture.prepareColumns(metrics);
        var retired = false;
        final job = _assembly(
          fixture,
          metrics,
          columns,
          ensureOwner: () {
            if (retired) throw StateError('retired');
          },
        );
        addTearDown(job.close);
        for (final column in columns) {
          job.addColumn(column);
          while (job.hasPendingMember) {
            job.advance(maxParts: 1);
          }
        }
        for (final content in fixture.annotations) {
          job.addSpan((content: content, lease: fixture.lease(content)));
          while (job.hasPendingMember) {
            job.advance(maxParts: 1);
          }
        }
        while (!job.isReady) {
          job.advance(maxParts: 1);
        }
        if (releaseMember) {
          fixture.lease(fixture.annotations.first).release();
        } else {
          retired = true;
        }
        expect(() => job.takeLayout(), throwsStateError);
        expect(job.nativeLeases, isEmpty);
        expect(fixture.cache.activeLeases, 0);
      },
    );
  }

  test(
    'a stale but equal-text last span cannot bind current source inputs',
    () {
      final fixture = RubySegmentFixture(dense: true);
      final other = RubySegmentFixture(dense: true);
      addTearDown(fixture.close);
      addTearDown(other.close);
      final metrics = fixture.compose();
      final columns = fixture.prepareColumns(metrics);
      final expected = [...fixture.annotations]..[99] = other.annotations.last;
      final job = _assembly(fixture, metrics, columns, spans: expected);
      addTearDown(job.close);
      for (final column in columns) {
        job.addColumn(column);
        while (job.hasPendingMember) {
          job.advance(maxParts: 1);
        }
      }
      for (final content in fixture.annotations.take(99)) {
        job.addSpan((content: content, lease: fixture.lease(content)));
        job.advance(maxParts: 1);
      }
      expect(job.preparedSpanCount, 99);
      job.addSpan((
        content: fixture.annotations.last,
        lease: fixture.lease(fixture.annotations.last),
      ));
      expect(
        () => job.advance(maxParts: 1),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(job.isReady, isFalse);
      expect(job.nativeLeases, isEmpty);
      expect(fixture.cache.activeLeases, 0);
      expect(other.cache.activeLeases, 102);
    },
  );

  test('source vectors are snapshotted before caller mutation', () {
    final fixture = RubySegmentFixture();
    addTearDown(fixture.close);
    final metrics = fixture.compose();
    final columns = fixture.prepareColumns(metrics);
    final content = [
      for (final column in columns)
        (
          base: column.inspectMembers().base.content,
          annotations: [
            for (final member in column.inspectMembers().annotations)
              member.content,
          ],
        ),
    ];
    final spans = fixture.annotations.toList();
    final job = ForumBodyRubySegmentAssembly(
      cache: fixture.cache,
      metrics: metrics,
      columns: content,
      spans: spans,
    );
    addTearDown(job.close);
    content.first.annotations.clear();
    content.clear();
    spans.clear();
    for (final column in columns) {
      job.addColumn(column);
      while (job.hasPendingMember) {
        job.advance(maxParts: 1);
      }
    }
    for (final input in fixture.annotations) {
      job.addSpan((content: input, lease: fixture.lease(input)));
      while (job.hasPendingMember) {
        job.advance(maxParts: 1);
      }
    }
    while (!job.isReady) {
      job.advance(maxParts: 1);
    }
    final layout = job.takeLayout();
    layout.close();
    expect(fixture.cache.activeLeases, 0);
  });

  test(
    'borrowed member snapshots neither mutate the group nor extend its ownership',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final columns = fixture.prepareColumns(fixture.compose());
      try {
        final snapshot = columns.first.inspectMembers();
        expect(() => snapshot.annotations.clear(), throwsUnsupportedError);
        columns.first.close();
        expect(snapshot.base.isActive, isFalse);
        expect(() => columns.first.inspectMembers(), throwsStateError);
        expect(columns.last.isActive, isTrue);
      } finally {
        for (final column in columns) {
          column.close();
        }
      }
    },
  );

  test('reentrant assembly calls cannot consume another format unit', () {
    final fixture = RubySegmentFixture();
    addTearDown(fixture.close);
    final metrics = fixture.compose();
    final columns = fixture.prepareColumns(metrics);
    late ForumBodyRubySegmentAssembly job;
    var reenter = false;
    job = _assembly(
      fixture,
      metrics,
      columns,
      ensureOwner: () {
        if (reenter) job.advance(maxParts: 1);
      },
    );
    try {
      job.addColumn(columns.first);
      reenter = true;
      expect(() => job.advance(maxParts: 1), throwsStateError);
      expect(job.nativeLeases, isEmpty);
      expect(columns.first.isActive, isFalse);
      expect(columns.last.isActive, isTrue);
    } finally {
      for (final column in columns) {
        column.close();
      }
      job.close();
    }
  });
}
