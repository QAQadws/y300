import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _merged =
    '<table><tr><td rowspan="2">A</td><td>B</td></tr>'
    '<tr><td>C</td></tr></table>';

ForumBodyDocument _parse(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'table-geometry',
  conversionIdentity: 'none',
);

ForumBodyTableGrid _grid(ForumBodyDocument document) =>
    ForumBodyTableGrid.fromDocument(document, document.tableElements.single);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overlapping width requirements can share a middle track', () {
    final grid = _grid(
      _parse(
        '<table><tr><td colspan="2">AB</td><td>C</td></tr>'
        '<tr><td>A</td><td colspan="2">BC</td></tr></table>',
      ),
    );
    const widths = [
      (minimum: 100.0, preferred: 140.0),
      (minimum: 10.0, preferred: 20.0),
      (minimum: 10.0, preferred: 20.0),
      (minimum: 100.0, preferred: 120.0),
    ];
    for (final (available, used) in [(115.0, 115.0), (80.0, 110.0)]) {
      final columns = ForumBodyTableColumns.resolve(
        grid: grid,
        availableWidth: available,
        cellWidths: widths,
      );
      expect(columns.width, closeTo(used, 0.0001));
      for (final (index, measure) in widths.indexed) {
        expect(
          columns.cellWidth(index),
          greaterThanOrEqualTo(measure.minimum - 0.0001),
        );
      }
    }
  });

  test('author width, track gaps and merged bounds survive RTL', () {
    final grid = _grid(_parse(_merged));
    final columns = ForumBodyTableColumns.resolve(
      grid: grid,
      availableWidth: 96,
      specifiedWidth: 200,
      spacing: 4,
      columnWidths: const [
        (minimum: 60, preferred: 80),
        (minimum: 45, preferred: 100),
      ],
      cellWidths: List.filled(3, (minimum: 10, preferred: 20)),
    );
    final ltr = columns.resolveRows(cellHeights: [120, 24, 70], spacing: 6);
    final rtl = columns.resolveRows(
      cellHeights: [120, 24, 70],
      rowMinimums: [10, 20],
      spacing: 6,
      direction: TextDirection.rtl,
    );
    expect(ltr.size, const Size(200, 120));
    expect(ltr.rowHeights, [24, 90]);
    expect(ltr.cellBounds(0), const Rect.fromLTWH(0, 0, 88, 120));
    expect(ltr.cellBounds(2), const Rect.fromLTWH(92, 30, 108, 90));
    expect(rtl.cellBounds(0), const Rect.fromLTWH(112, 0, 88, 120));
    expect(rtl.cellBounds(2), const Rect.fromLTWH(0, 30, 108, 90));
    expect(rtl.rowBounds(1), const Rect.fromLTWH(0, 30, 200, 90));
    expect(rtl.rowHeights.clear, throwsUnsupportedError);
  });

  test(
    'real cell glyph measurements keep their font and grow rows to wrap',
    () {
      final document = _parse(
        '<table><tr><td rowspan="2"><strong>one two three four</strong></td>'
        '<td>right</td></tr><tr><td>five six seven</td></tr></table>',
      );
      final grid = _grid(document);
      final styles = const ForumBodyStyleResolver().resolve(
        document,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 10,
            height: 1,
          ),
          fontRevision: 'table-geometry',
          linkColor: const Color(0xff0000ff),
        ),
      );
      InlineSpan span(ForumBodyNode node) => TextSpan(
        style: styles.byPath[node.path]!.textStyle,
        text: node is ForumBodyText ? node.text : null,
        children: node is ForumBodyElement
            ? node.children.map(span).toList()
            : null,
      );
      final painters = [
        for (final cell in grid.cells)
          TextPainter(
            text: span(cell.element),
            textDirection: TextDirection.ltr,
            textScaler: const TextScaler.linear(1.2),
          )..layout(),
      ];
      addTearDown(() {
        for (final painter in painters) {
          painter.dispose();
        }
      });
      final widths = [
        for (final painter in painters)
          (
            minimum: painter.minIntrinsicWidth,
            preferred: painter.maxIntrinsicWidth,
          ),
      ];
      final columns = ForumBodyTableColumns.resolve(
        grid: grid,
        availableWidth: 140,
        cellWidths: widths,
      );
      final heights = [
        for (final (index, painter) in painters.indexed)
          (painter..layout(maxWidth: columns.cellWidth(index) + 0.0001)).height,
      ];
      final table = columns.resolveRows(cellHeights: heights);
      expect(table.size.width, closeTo(140, 0.0001));
      expect(painters.first.computeLineMetrics().length, greaterThan(1));
      for (final (index, height) in heights.indexed) {
        final bounds = table.cellBounds(index);
        expect(bounds.height, greaterThanOrEqualTo(height - 0.0001));
        expect(bounds.right, lessThanOrEqualTo(table.size.width + 0.0001));
      }
      expect(table.cellBounds(0).overlaps(table.cellBounds(1)), isFalse);
      expect(table.cellBounds(0).overlaps(table.cellBounds(2)), isFalse);
    },
  );

  test('caption and box budgets do not silently squeeze cell content', () {
    final grid = _grid(_parse(_merged));
    final columns = ForumBodyTableColumns.resolve(
      grid: grid,
      availableWidth: 80,
      captionWidth: (minimum: 120, preferred: 160),
      cellWidths: List.filled(3, (minimum: 12, preferred: 18)),
    );
    expect(columns.width, 120);
    expect(
      () => columns.resolveRows(cellHeights: [20, 600000, 600000]),
      throwsA(
        isA<ForumBodyTableException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyTableFailure.extentLimit,
        ),
      ),
    );
    expect(
      () => columns.resolveRows(cellHeights: [20, 40, double.infinity]),
      throwsA(
        isA<ForumBodyTableException>()
            .having(
              (error) => error.failure,
              'failure',
              ForumBodyTableFailure.invalidGeometry,
            )
            .having(
              (error) => error.path,
              'path',
              grid.cells.last.element.path,
            ),
      ),
    );
  });
}
