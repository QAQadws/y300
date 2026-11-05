import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyDocument _parse(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'table-fixture',
  conversionIdentity: 'none',
);

void main() {
  test('Discuz rowspan and colspan retain the actual rich cells', () {
    final document = _parse(
      '<p>before</p>'
      '<table cellspacing="0" class="t_table" style="width:98%" bgcolor="#ccc">'
      '<tr style="background-color:#eee">'
      '<td rowspan="2" width="30%"><strong>左</strong></td>'
      '<td colspan="2"><a href="/thread">链接</a><img src="/same.png"></td>'
      '</tr><tr>'
      '<td><ruby>字<rt>じ</rt></ruby></td>'
      '<td><img src="/same.png"><p>右</p></td>'
      '</tr></table><p>after</p>',
    );
    final table = document.tableElements.single;
    final grid = ForumBodyTableGrid.fromDocument(document, table);
    expect(grid.table, same(table));
    expect(grid.identity, document.identity);
    expect(grid.columnCount, 3);
    expect(grid.rows.map((row) => row.group?.tag), ['tbody', 'tbody']);
    expect(
      grid.cells.map(
        (cell) => (cell.row, cell.column, cell.rowSpan, cell.columnSpan),
      ),
      [(0, 0, 2, 1), (0, 1, 1, 2), (1, 1, 1, 1), (1, 2, 1, 1)],
    );
    expect(grid.cells.map((cell) => cell.element.path), [
      '1/0/0/0',
      '1/0/0/1',
      '1/0/1/0',
      '1/0/1/1',
    ]);
    final rich = grid.cells[1].element;
    expect(rich, same(document.nodeAtPath(rich.path)));
    expect(rich.children.first, same(document.nodeAtPath('1/0/0/1/0')));
    expect(rich.children.last, same(document.imageElements.first));
    expect(
      grid.cells.last.element.children.first,
      same(document.imageElements.last),
    );
    expect(grid.cells.first.element.attributes['width'], '30%');
    expect(grid.rows.first.element!.style.value('background-color'), '#eee');
    expect(grid.cells.clear, throwsUnsupportedError);
  });

  test('zero spans end in their own group and include implied rows', () {
    final document = _parse(
      '<table><caption>标题</caption>'
      '<colgroup span="2" width="10%"></colgroup>'
      '<colgroup><col style="width:48px"></colgroup>'
      '<tfoot><tr><td colspan="3">footer</td></tr></tfoot>'
      '<tbody><tr><th rowspan="0">A</th><td rowspan="3">B</td></tr>'
      '<tr><td>C</td></tr></tbody>'
      '<tbody><tr><td colspan="3">D</td></tr></tbody></table>',
    );
    final grid = ForumBodyTableGrid.fromDocument(
      document,
      document.tableElements.single,
    );
    expect(grid.captions.single.kind, ForumBodyElementKind.tableCaption);
    expect(grid.columnCount, 3);
    expect(
      grid.columnRanges.map(
        (range) =>
            (range.element.tag, range.column, range.span, range.group?.tag),
      ),
      [('colgroup', 0, 2, null), ('col', 2, 1, 'colgroup')],
    );
    expect(grid.rows.map((row) => row.group?.tag), [
      'tbody',
      'tbody',
      'tbody',
      'tbody',
      'tfoot',
    ]);
    expect(grid.rows[2].element, isNull);
    expect(grid.rows[2].group, same(grid.rows.first.group));
    expect(grid.cells.first.rowSpan, 3);
    expect(grid.cells[2].column, 2);
    expect(grid.cells[3].column, 0);
    expect(grid.cells.last.row, 4);
    expect(grid.cells.last.element.path, '0/3/0/0');
  });

  test('nested tables own separate grids and reject foreign sources', () {
    const html =
        '<table><tr><td><table><tr><td>inner</td><td>two</td></tr>'
        '</table></td><td>outer</td></tr></table>';
    final document = _parse(html);
    final outer = document.nodes.single as ForumBodyElement;
    final grid = ForumBodyTableGrid.fromDocument(document, outer);
    expect(grid.cells, hasLength(2));
    final inner = grid.cells.first.element.children.single as ForumBodyElement;
    expect(document.tableElements, unorderedEquals([outer, inner]));
    expect(
      ForumBodyTableGrid.fromDocument(document, inner).cells,
      hasLength(2),
    );
    expect(
      () => ForumBodyTableGrid.fromDocument(_parse(html), outer),
      throwsArgumentError,
    );
  });

  test('span values follow bounded HTML integer interpretation', () {
    final document = _parse(
      '<table><tr><td colspan="0" rowspan="-3">A</td>'
      '<td colspan=" +0003tail">B</td>'
      '<td colspan="9999999999999999999999" rowspan="invalid">C</td>'
      '</tr></table>',
    );
    final grid = ForumBodyTableGrid.fromDocument(
      document,
      document.tableElements.single,
    );
    expect(grid.cells.map((cell) => cell.columnSpan), [1, 3, 1000]);
    expect(grid.cells.map((cell) => cell.rowSpan), [1, 1, 1]);
    expect(grid.columnCount, 1004);
  });

  test('limits and overlapping slots fail at the actual offending cell', () {
    void check(
      String html,
      ForumBodyTableLimits limits,
      ForumBodyTableFailure failure,
      String path,
    ) {
      final document = _parse(html);
      expect(
        () => ForumBodyTableGrid.fromDocument(
          document,
          document.tableElements.single,
          limits: limits,
        ),
        throwsA(
          isA<ForumBodyTableException>()
              .having((error) => error.failure, 'failure', failure)
              .having((error) => error.path, 'source', path),
        ),
      );
    }

    check(
      '<table><tr><td rowspan="99">a</td></tr></table>',
      const ForumBodyTableLimits(maxRows: 2),
      ForumBodyTableFailure.rowLimit,
      '0/0/0/0',
    );
    check(
      '<table><tr><td colspan="3">a</td></tr></table>',
      const ForumBodyTableLimits(maxColumns: 2),
      ForumBodyTableFailure.columnLimit,
      '0/0/0/0',
    );
    check(
      '<table><tr><td>a</td><td>b</td></tr></table>',
      const ForumBodyTableLimits(maxCells: 1),
      ForumBodyTableFailure.cellLimit,
      '0/0/0/1',
    );
    check(
      '<table><tr><td colspan="3">a</td></tr></table>',
      const ForumBodyTableLimits(maxSlotChecks: 2),
      ForumBodyTableFailure.workLimit,
      '0/0/0/0',
    );
    check(
      '<table><tr><td>a</td><td rowspan="2">b</td></tr>'
          '<tr><td colspan="2">c</td></tr></table>',
      const ForumBodyTableLimits(),
      ForumBodyTableFailure.overlap,
      '0/0/1/0',
    );
  });
}
