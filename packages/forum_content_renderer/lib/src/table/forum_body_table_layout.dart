part of 'forum_body_table_preparation.dart';

/// A caption or cell of the original table with its fixed placement. Internal
/// body slices let callers materialize one visible part of a very tall cell.
/// The outer renderer still presents the entire grid in one table viewport.
final class ForumBodyTableAreaLayout {
  const ForumBodyTableAreaLayout._(
    this.element,
    this.bounds,
    this.contentBounds,
    this.background,
    this._body,
  );
  final ForumBodyElement element;
  final Rect bounds, contentBounds;
  final Color? background;
  final _MeasuredBody _body;

  ForumBodyTextPageSnapshot get snapshot => _body.session.snapshot;
  double pageTop(int page) => _body.pageTops[page];

  ForumBodyTextPagePreparation openPagePreparation(int page) =>
      _body.session.openPagePreparation(page);
}

/// One frozen layout with source-bound, lazily materialized bodies. The table
/// owns those sessions and the Host still owns the shared paragraph cache.
final class ForumBodyTableLayout {
  ForumBodyTableLayout._({
    required this.geometry,
    required this.size,
    required this.background,
    required this.gridTop,
    required List<ForumBodyTableAreaLayout> cells,
    required List<ForumBodyTableAreaLayout> captions,
    required List<Color?> rowBackgrounds,
  }) : cells = List.unmodifiable(cells),
       captions = List.unmodifiable(captions),
       rowBackgrounds = List.unmodifiable(rowBackgrounds);

  final ForumBodyTableGeometry geometry;
  final Size size;
  final double gridTop;
  final Color? background;
  final List<ForumBodyTableAreaLayout> cells, captions;
  final List<Color?> rowBackgrounds;
  bool _closed = false;
  bool get isClosed => _closed;

  void close() {
    if (_closed) return;
    _closed = true;
    for (final item in cells.followedBy(captions)) {
      item._body.session.close();
    }
  }
}
