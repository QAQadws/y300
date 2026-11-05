import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _html =
    '<div width="199"><table width="98%" height="180" bgcolor="#f0e4d0" '
    'cellpadding="5"><caption>Caption</caption>'
    '<colgroup><col width="44"><col width="50.5%"></colgroup>'
    '<tbody height="20%" bgcolor="#eef"><tr height="36" '
    'bgcolor="#e0e0e0" style="height:40px;background-color:transparent">'
    '<th width="30%" height="0" bgcolor="#ccc" style="padding-left:8px">Head</th>'
    '<td width="120" height="45" bgcolor="#dd0" '
    'style="width:auto;background-color:var(--unknown)">'
    '<table cellpadding="0"><tr><td width="0">Nested</td></tr></table>'
    '</td></tr></tbody></table></div>';

ForumBodyReaderStyle _reader({ForumBodyStylePolicy? policy}) =>
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontSize: 16),
      fontRevision: 'table-hints',
      linkColor: const Color(0xff003399),
      policy: policy,
    );

ForumBodyDocument _parse(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'table-hints',
  conversionIdentity: 'none',
);

void main() {
  test('Discuz attributes feed shared cell geometry and color precedence', () {
    final document = _parse(_html);
    final outer = document.tableElements.singleWhere(
      (node) => node.attributes.containsKey('bgcolor'),
    );
    final grid = ForumBodyTableGrid.fromDocument(document, outer);
    final styles = const ForumBodyStyleResolver().resolve(document, _reader());
    ForumBodyResolvedStyle of(ForumBodyElement node) =>
        styles.byPath[node.path]!;
    final table = of(outer);
    final row = of(grid.rows.single.element!);
    final rowGroup = of(grid.rows.single.group!);
    final head = of(grid.cells[0].element);
    final cell = of(grid.cells[1].element);
    expect(of(document.nodes.single as ForumBodyElement).box.width, isNull);
    expect(
      table.box.width,
      const ForumBodyLength(98, ForumBodyLengthUnit.percent),
    );
    expect(table.box.height, const ForumBodyLength(180));
    expect(table.box.sizing, ForumBodyBoxSizing.borderBox);
    expect(table.boxBackground, const Color(0xfff0e4d0));
    expect(
      of(grid.columnRanges.first.element).box.width,
      const ForumBodyLength(44),
    );
    expect(
      of(grid.columnRanges.last.element).box.width,
      const ForumBodyLength(50.5, ForumBodyLengthUnit.percent),
    );
    expect(
      rowGroup.box.height,
      const ForumBodyLength(20, ForumBodyLengthUnit.percent),
    );
    expect(row.box.height, const ForumBodyLength(40));
    expect(row.boxBackground, const Color(0x00000000));
    expect(
      head.box.width,
      const ForumBodyLength(30, ForumBodyLengthUnit.percent),
    );
    expect(head.box.height, isNull);
    expect(head.padding.left, const ForumBodyLength(8));
    expect(head.padding.top, const ForumBodyLength(5));
    expect(head.textStyle.fontWeight, FontWeight.w700);
    expect(head.boxBackground, const Color(0xffcccccc));
    expect(cell.box.width, isNull);
    expect(cell.box.height, const ForumBodyLength(45));
    expect(cell.boxBackground, const Color(0xffdddd00));
    expect(of(grid.captions.single).padding.top, ForumBodyLength.zero);

    final inner = document.tableElements.singleWhere((node) => node != outer);
    final innerCell = ForumBodyTableGrid.fromDocument(
      document,
      inner,
    ).cells.single.element;
    final scoped = const ForumBodyStyleResolver().open(
      document,
      _reader(),
      contentRoot: innerCell,
    );
    addTearDown(scoped.close);
    expect(of(innerCell).padding.top, ForumBodyLength.zero);
    expect(of(innerCell).box.width, isNull);
    expect(scoped.root.padding.left, ForumBodyLength.zero);
    expect(scoped.root.textStyle, of(innerCell).textStyle);
  });

  test('a nested table resets the inherited cellpadding default', () {
    final document = _parse(
      '<table cellpadding="7"><tr><td><table><tr><td>'
      'Inner</td></tr></table></td></tr></table>',
    );
    final styles = const ForumBodyStyleResolver().resolve(document, _reader());
    final byDepth = document.tableElements.toList()
      ..sort((a, b) => a.path.length.compareTo(b.path.length));
    final pads = byDepth.map((table) {
      final cell = ForumBodyTableGrid.fromDocument(
        document,
        table,
      ).cells.single;
      return styles.byPath[cell.element.path]!.padding.top.value;
    });
    expect(pads, [7, 1]);
  });

  test('reader background override still owns table colors', () {
    final document = _parse(_html);
    final styles = const ForumBodyStyleResolver().resolve(
      document,
      _reader(
        policy: ForumBodyStylePolicy({
          ForumBodyStyleProperty.background: ForumBodyStyleScope.forceAll,
        }),
      ),
    );
    for (final element in document.descendants.whereType<ForumBodyElement>()) {
      expect(styles.byPath[element.path]!.boxBackground, isNull);
    }
  });
}
