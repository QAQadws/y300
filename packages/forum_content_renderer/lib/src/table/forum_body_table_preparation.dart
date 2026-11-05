import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';

import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import '../inline/forum_body_inline_image_input.dart';
import '../pagination/forum_body_image_frame.dart';
import '../pagination/forum_body_text_page_composer.dart';
import '../pagination/forum_body_text_page_preparation.dart';
import '../pagination/forum_body_text_page_session.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../style/forum_body_box_style.dart';
import '../style/forum_body_length.dart';
import '../style/forum_body_style_options.dart';
import '../style/forum_body_style_resolver.dart';
import '../style/forum_body_table_hints.dart';
import 'forum_body_table_geometry.dart';
import 'forum_body_table_grid.dart';

part 'forum_body_table_layout.dart';

enum _Phase { probe, columns, rows, compose, publish, ready, closed }

/// Cooperative table measurement. Only one scoped body Session runs at a time.
/// The wide probe drops its content before the next cell. The final pass keeps
/// source/numeric pages only and applies aggregate table budgets to their inputs.
final class ForumBodyTablePreparation {
  ForumBodyTablePreparation({
    required ForumBodyDocument document,
    required ForumBodyElement table,
    required ForumBodyReaderStyle reader,
    required ForumBodyParagraphCache cache,
    required this.availableWidth,
    required this.layoutId,
    required this.limits,
    this.textScaler = TextScaler.noScaling,
    ForumBodyCollapseLayout? collapses,
    ForumBodyImageResolver? imageResolver,
    ForumBodyInlineImageResolver? inlineImageResolver,
    ForumBodyTableLimits gridLimits = const ForumBodyTableLimits(),
  }) : _document = document,
       _reader = reader,
       _cache = cache,
       _collapses = collapses,
       _images = _FrozenImages(imageResolver, inlineImageResolver),
       grid = ForumBodyTableGrid.fromDocument(
         document,
         table,
         limits: gridLimits,
       ) {
    if (!availableWidth.isFinite ||
        availableWidth <= 0 ||
        layoutId.isEmpty ||
        limits.maxPages <= 0 ||
        limits.maxFragments <= 0 ||
        limits.maxParagraphs <= 0 ||
        limits.maxTextCodeUnits < 0 ||
        limits.maxRuns < 0) {
      throw ArgumentError('Invalid table preparation inputs');
    }
    _guard();
    _tableStyle = _style(table);
    if (_tableStyle.hidden || collapses?.hidesPath(table.path) == true) {
      throw ArgumentError('Cannot lay out a hidden table');
    }
    final box = _tableStyle.box;
    _rootWidth = _length(box.width, availableWidth);
    _minTableWidth = _length(box.minWidth, availableWidth) ?? 0;
    _maxTableWidth = _length(box.maxWidth, availableWidth);
    _widthReference = math.max(
      math.max(1.0, _minTableWidth),
      math.min(_rootWidth ?? availableWidth, _maxTableWidth ?? double.infinity),
    );
    _spacing = _resolveSpacing();
    _columnHints = List.filled(grid.columnCount, (minimum: 0, preferred: 0));
  }

  static const _probeWidth = 16384.0;
  static const _extentLimit = 1048576.0;
  final ForumBodyTableGrid grid;
  final double availableWidth;
  final String layoutId;
  final TextScaler textScaler;
  final ForumBodyTextPageSessionLimits limits;
  final ForumBodyDocument _document;
  final ForumBodyReaderStyle _reader;
  final ForumBodyParagraphCache _cache;
  final ForumBodyCollapseLayout? _collapses;
  final _FrozenImages _images;
  late final ForumBodyResolvedStyle _tableStyle;
  late final double? _rootWidth;
  late final double _minTableWidth;
  late final double? _maxTableWidth;
  late final double _widthReference;
  late final ({double horizontal, double vertical}) _spacing;
  late final List<ForumBodyTableWidth> _columnHints;
  final _rowHeights = <double>[];
  final _rowBackgrounds = <Color?>[];
  final _measured = <_MeasuredArea>[];
  final _bodies = <_MeasuredBody>[];
  final _fingerprint = _TableFingerprint();
  ForumBodyTableColumns? _columns;
  ForumBodyTextPageSession? _active;
  ForumBodyTableLayout? _ready;
  var _phase = _Phase.probe;
  var _index = 0;
  int _pages = 0, _fragments = 0, _paragraphs = 0, _text = 0, _runs = 0;
  bool _advancing = false;

  bool get isReady => _phase == _Phase.ready;
  int get _captionCount => grid.captions.length;
  int get _areaCount => _captionCount + grid.cells.length;

  ForumBodyElement _area(int index) => index < _captionCount
      ? grid.captions[index]
      : grid.cells[index - _captionCount].element;

  ({bool isReady, bool waitingForLayoutBudget, int layoutsBuilt}) advance({
    required int maxEvents,
    required int maxLines,
    int maxFormatParts = 32,
  }) {
    if (_advancing) throw StateError('Table preparation is reentrant');
    if (maxEvents <= 0 || maxLines <= 0 || maxFormatParts <= 0) {
      throw ArgumentError('Invalid table work budget');
    }
    _advancing = true;
    try {
      _guard();
      var built = 0;
      var waiting = false;
      switch (_phase) {
        case _Phase.probe:
        case _Phase.compose:
          final probe = _phase == _Phase.probe;
          if (_index == _areaCount) {
            _index = 0;
            _phase = probe ? _Phase.columns : _Phase.publish;
            break;
          }
          final session = _active ??= _openBody(_index, probe: probe);
          final step = session.advance(
            maxEvents: maxEvents,
            maxLines: maxLines,
            maxFormatParts: maxFormatParts,
          );
          _guard();
          built = step.layoutsBuilt;
          waiting = step.waitingForLayoutBudget;
          if (!probe && step.pagesPublished != 0) {
            _fingerprint.addPage(session.snapshot.last);
          }
          if (session.isComplete) {
            if (probe) {
              _measured.add(_measureArea(session));
              session.close();
            } else {
              _recordBody(session);
            }
            _active = null;
            _index++;
          }
        case _Phase.columns:
          if (_index < grid.columnRanges.length) {
            _readColumn(grid.columnRanges[_index++]);
          } else {
            _resolveColumns();
            _index = 0;
            _phase = _Phase.rows;
          }
        case _Phase.rows:
          if (_index < grid.rows.length) {
            final row = grid.rows[_index++];
            final style = row.element == null ? null : _style(row.element!);
            _rowHeights.add(_height(style?.box.height));
            _rowBackgrounds.add(
              style?.visibilityHidden == false ? style!.boxBackground : null,
            );
          } else {
            _index = 0;
            _phase = _Phase.compose;
          }
        case _Phase.publish:
          _ready = _buildLayout();
          _bodies.clear();
          _measured.clear();
          _images.close();
          _phase = _Phase.ready;
        case _Phase.ready:
          break;
        case _Phase.closed:
          throw StateError('Table preparation is closed');
      }
      return (
        isReady: isReady,
        waitingForLayoutBudget: waiting,
        layoutsBuilt: built,
      );
    } catch (_) {
      close();
      rethrow;
    } finally {
      _advancing = false;
    }
  }

  ForumBodyTableLayout takeLayout() {
    _guard();
    if (_advancing || !isReady) {
      throw StateError('Table preparation is incomplete');
    }
    final result = _ready!;
    _ready = null;
    close();
    return result;
  }

  ForumBodyResolvedStyle _style(ForumBodyElement element) {
    final cursor = const ForumBodyStyleResolver().open(
      _document,
      _reader,
      collapses: _collapses,
      contentRoot: element,
    );
    final result = cursor.root;
    cursor.close();
    return result;
  }

  double? _length(ForumBodyLength? value, double reference) {
    if (value == null || value.unit == ForumBodyLengthUnit.auto) return null;
    return value.resolve(
      fontSize: _tableStyle.textStyle.fontSize!,
      rootFontSize: _reader.textStyle.fontSize!,
      reference: reference,
    );
  }

  double _height(ForumBodyLength? length) {
    if (length?.unit != ForumBodyLengthUnit.percent) {
      return _length(length, 0) ?? 0;
    }
    final tableHeight = _tableStyle.box.height;
    return tableHeight?.unit == ForumBodyLengthUnit.px
        ? _length(length, tableHeight!.value) ?? 0
        : 0;
  }

  ({double horizontal, double vertical}) _resolveSpacing() {
    final table = grid.table;
    if (table.style.value('border-collapse')?.trim().toLowerCase() ==
        'collapse') {
      return (horizontal: 0, vertical: 0);
    }
    final legacy =
        forumBodyTablePixelAttribute(table.attributes['cellspacing']) ?? 2;
    final raw = table.style.value('border-spacing');
    if (raw != null) {
      final parts = raw.trim().split(RegExp(r'\s+'));
      final lengths = parts.map(ForumBodyLength.tryParse).toList();
      if (lengths.length <= 2 &&
          lengths.every(
            (length) =>
                length != null &&
                length.value >= 0 &&
                length.unit != ForumBodyLengthUnit.percent &&
                length.unit != ForumBodyLengthUnit.auto,
          )) {
        return (
          horizontal: _length(lengths.first, 0)!,
          vertical: _length(lengths.last, 0)!,
        );
      }
    }
    return (horizontal: legacy, vertical: legacy);
  }

  void _readColumn(ForumBodyTableColumnRange range) {
    final style = _style(range.element);
    final hint =
        style.box.width ??
        (range.group == null ? null : _style(range.group!).box.width);
    final width = _length(hint, _widthReference);
    if (width == null) return;
    final hard = hint!.unit == ForumBodyLengthUnit.px ? width : 0.0;
    for (var i = range.column; i < range.column + range.span; i++) {
      _columnHints[i] = (minimum: hard, preferred: width);
    }
  }

  _MeasuredArea _measureArea(ForumBodyTextPageSession session) {
    final style = session.contentRootStyle;
    final hint = style.box.width;
    final preferred = _length(hint, _widthReference);
    final insets = style.padding;
    final padding = EdgeInsets.fromLTRB(
      _length(insets.left, _widthReference)!,
      _length(insets.top, _widthReference)!,
      _length(insets.right, _widthReference)!,
      _length(insets.bottom, _widthReference)!,
    );
    final widths = session.intrinsicWidths!;
    final boxExtra = style.box.sizing == ForumBodyBoxSizing.contentBox
        ? padding.horizontal
        : 0.0;
    final authorMin =
        (_length(style.box.minWidth, _widthReference) ?? 0) + boxExtra;
    var minimum = math.max(
      math.max(1.0, widths.minimum) + padding.horizontal,
      authorMin,
    );
    if (hint?.unit == ForumBodyLengthUnit.px && preferred != null) {
      minimum = math.max(minimum, preferred + boxExtra);
    }
    final natural = preferred == null
        ? widths.preferred + padding.horizontal
        : preferred + boxExtra;
    final maximum = _length(style.box.maxWidth, _widthReference);
    return (
      widths: (
        minimum: minimum,
        preferred: math.max(
          minimum,
          maximum == null ? natural : math.min(natural, maximum + boxExtra),
        ),
      ),
      padding: padding,
      height:
          _height(style.box.height) +
          (style.box.sizing == ForumBodyBoxSizing.contentBox
              ? padding.vertical
              : 0),
      background: style.visibilityHidden ? null : style.boxBackground,
    );
  }

  void _resolveColumns() {
    var captionMin = 0.0, captionPreferred = 0.0;
    for (var i = 0; i < _captionCount; i++) {
      final width = _measured[i].widths;
      captionMin = math.max(captionMin, width.minimum);
      captionPreferred = math.max(captionPreferred, width.preferred);
    }
    _columns = ForumBodyTableColumns.resolve(
      grid: grid,
      availableWidth: availableWidth,
      specifiedWidth: _rootWidth,
      minimumWidth: _minTableWidth,
      maximumWidth: _maxTableWidth,
      cellWidths: [
        for (var i = _captionCount; i < _areaCount; i++) _measured[i].widths,
      ],
      columnWidths: _columnHints,
      captionWidth: (minimum: captionMin, preferred: captionPreferred),
      spacing: _spacing.horizontal,
    );
  }

  ForumBodyTextPageSession _openBody(int index, {required bool probe}) {
    final element = _area(index);
    final width = probe ? _probeWidth : _contentWidth(index);
    if (!width.isFinite || width <= 0 || width > _probeWidth) {
      throw ForumBodyTableException(
        ForumBodyTableFailure.extentLimit,
        element.path,
      );
    }
    return ForumBodyTextPageSession(
      document: _document,
      contentRoot: element,
      collapses: _collapses,
      reader: _reader,
      cache: _cache,
      textScaler: textScaler,
      layoutId: '$layoutId/${element.path}',
      width: width,
      height: _extentLimit,
      intrinsicAvailableWidth: probe ? _widthReference : null,
      limits: probe
          ? limits
          : ForumBodyTextPageSessionLimits(
              maxPages: math.max(1, limits.maxPages - _pages),
              maxFragments: math.max(1, limits.maxFragments - _fragments),
              maxParagraphs: math.max(1, limits.maxParagraphs - _paragraphs),
              maxTextCodeUnits: limits.maxTextCodeUnits - _text,
              maxRuns: limits.maxRuns - _runs,
              maxIssuedLeases: limits.maxIssuedLeases,
              maxIssuedImages: limits.maxIssuedImages,
              maxPagePreparations: limits.maxPagePreparations,
              maxStyleIssues: limits.maxStyleIssues,
            ),
      imageResolver: _images.block,
      inlineImageResolver: _images.inline,
    );
  }

  double _contentWidth(int index) {
    final outer = index < _captionCount
        ? _columns!.width
        : _columns!.cellWidth(index - _captionCount);
    return outer - _measured[index].padding.horizontal;
  }

  void _recordBody(ForumBodyTextPageSession session) {
    var height = 0.0;
    final tops = <double>[];
    final snapshot = session.snapshot;
    for (final page in snapshot) {
      tops.add(height);
      height += page.usedHeight;
      _fragments += page.itemCount;
    }
    _pages += snapshot.length;
    _paragraphs += session.retainedParagraphCount;
    _text += session.retainedTextCodeUnits;
    _runs += session.retainedRuns;
    if (_pages > limits.maxPages ||
        _fragments > limits.maxFragments ||
        _paragraphs > limits.maxParagraphs ||
        _text > limits.maxTextCodeUnits ||
        _runs > limits.maxRuns) {
      throw ForumBodyTableException(
        ForumBodyTableFailure.workLimit,
        _area(_index).path,
      );
    }
    _bodies.add(_MeasuredBody(session, height, List.unmodifiable(tops)));
  }

  double _areaHeight(int index) => math.max(
    _measured[index].height,
    _measured[index].padding.vertical + _bodies[index].height,
  );

  ForumBodyTableLayout _buildLayout() {
    final geometry = _columns!.resolveRows(
      cellHeights: [
        for (var i = _captionCount; i < _areaCount; i++) _areaHeight(i),
      ],
      rowMinimums: _rowHeights,
      direction: _tableStyle.textDirection,
      spacing: _spacing.vertical,
      minimumHeight: _height(_tableStyle.box.height),
    );
    final captions = <ForumBodyTableAreaLayout>[];
    final bottom = <int>[];
    var top = 0.0;
    for (var i = 0; i < _captionCount; i++) {
      final element = grid.captions[i];
      final side =
          element.style.value('caption-side') ?? element.attributes['align'];
      if (side?.trim().toLowerCase() == 'bottom') {
        bottom.add(i);
      } else {
        final height = _areaHeight(i);
        captions.add(
          _placeArea(i, Rect.fromLTWH(0, top, geometry.size.width, height)),
        );
        top += height;
      }
    }
    var end = top + geometry.size.height;
    for (final i in bottom) {
      final height = _areaHeight(i);
      captions.add(
        _placeArea(i, Rect.fromLTWH(0, end, geometry.size.width, height)),
      );
      end += height;
    }
    if (!end.isFinite || end > _extentLimit) {
      throw ForumBodyTableException(
        ForumBodyTableFailure.extentLimit,
        grid.table.path,
      );
    }
    final cells = [
      for (var i = 0; i < grid.cells.length; i++)
        _placeArea(
          i + _captionCount,
          geometry.cellBounds(i).shift(Offset(0, top)),
        ),
    ];
    final background = _tableStyle.visibilityHidden
        ? null
        : _tableStyle.boxBackground;
    return ForumBodyTableLayout._(
      geometry: geometry,
      gridTop: top,
      size: Size(geometry.size.width, end),
      background: background,
      cells: cells,
      captions: captions,
      rowBackgrounds: _rowBackgrounds,
      cache: _cache,
      fingerprint: _fingerprint.finish([
        top,
        end,
        geometry.size.width,
        _TableFingerprint.color(background),
        for (final row in _rowBackgrounds) _TableFingerprint.color(row),
        for (final area in captions.followedBy(cells))
          [
            area.element.path,
            _TableFingerprint.rect(area.bounds),
            _TableFingerprint.rect(area.contentBounds),
            _TableFingerprint.color(area.background),
          ],
      ]),
      usage: (
        pages: _pages,
        items: _fragments,
        paragraphs: _paragraphs,
        textCodeUnits: _text,
        runs: _runs,
      ),
    );
  }

  ForumBodyTableAreaLayout _placeArea(int index, Rect bounds) {
    final measure = _measured[index];
    final body = _bodies[index];
    return ForumBodyTableAreaLayout._(
      _area(index),
      bounds,
      Rect.fromLTWH(
        bounds.left + measure.padding.left,
        bounds.top + measure.padding.top,
        body.session.snapshot.width,
        body.height,
      ),
      measure.background,
      body,
    );
  }

  void _guard() {
    if (_phase == _Phase.closed) {
      throw StateError('Table preparation is closed');
    }
    if (_cache.isClosed) {
      close();
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.ownerRetired,
      );
    }
  }

  void close() {
    if (_phase == _Phase.closed) return;
    _phase = _Phase.closed;
    _active?.close();
    _active = null;
    for (final body in _bodies) {
      body.session.close();
    }
    _bodies.clear();
    _measured.clear();
    _rowHeights.clear();
    _rowBackgrounds.clear();
    _columns = null;
    _images.close();
    _ready?.close();
    _ready = null;
  }
}

/// Compare a retry's cells without holding native geometry or comparing the
/// entire table in the outer page verifier. Only one sealed body slice at a time
/// enters the digest.
final class _TableFingerprint implements Sink<Digest> {
  late final _input = sha256.startChunkedConversion(this);
  late Digest _digest;

  void addPage(ForumBodyTextPage page) => _write([
    page.index,
    page.usedHeight,
    for (final f in page.fragments)
      [
        f.path,
        f.fontRevision,
        f.styleRevision,
        f.kind.index,
        f.startLine,
        f.endLine,
        f.coverageStartUtf16,
        f.coverageEndUtf16,
        f.sourceHint?.runeStart,
        f.sourceHint?.runeEnd,
        f.left,
        f.top,
        f.width,
        f.height,
        f.imageCount,
        f.imagePaths,
        rect(f.imageFrame?.imageRect),
        f.engineRange?.startUtf16,
        f.engineRange?.endUtf16,
        f.listMarker?.baseline,
        rect(f.listMarker?.bounds),
        f.collapseHeader?.id,
        f.collapseHeader?.titlePath,
        f.collapseHeader?.expanded,
        f.collapseHeader?.direction.index,
        rect(f.collapseHeader?.bounds),
      ],
    for (final r in page.rules)
      [r.path, r.left, r.top, r.width, r.thickness, color(r.color)],
    for (final b in page.backgrounds)
      [
        b.path,
        b.left,
        b.top,
        b.width,
        b.height,
        color(b.color),
        color(b.quoteDecoration?.borderColor),
        b.startsBox,
        b.endsBox,
      ],
  ]);

  String finish(List<Object?> geometry) {
    _write(geometry);
    _input.close();
    return _digest.toString();
  }

  void _write(List<Object?> value) =>
      _input.add(utf8.encode(jsonEncode(value)));

  static List<double>? rect(Rect? rect) =>
      rect == null ? null : [rect.left, rect.top, rect.width, rect.height];

  static List<num>? color(Color? color) => color == null
      ? null
      : [color.a, color.r, color.g, color.b, color.colorSpace.index];

  @override
  void add(Digest data) => _digest = data;
  @override
  void close() {}
}

typedef _MeasuredArea = ({
  ForumBodyTableWidth widths,
  EdgeInsets padding,
  double height,
  Color? background,
});

final class _MeasuredBody {
  const _MeasuredBody(this.session, this.height, this.pageTops);
  final ForumBodyTextPageSession session;
  final double height;
  final List<double> pageTops;
}

/// The actual source captures are shared by the probe and layout passes.
final class _FrozenImages {
  _FrozenImages(this._blockResolver, this._inlineResolver);
  ForumBodyImageResolver? _blockResolver;
  ForumBodyInlineImageResolver? _inlineResolver;
  final _blocks = <ForumBodyElement, ForumBodyImageInput?>{};
  final _inlines = <ForumBodyElement, ForumBodyInlineImageInput?>{};
  bool _closed = false;

  ForumBodyImageInput? block(
    ForumBodyIdentity identity,
    ForumBodyElement image,
  ) => _capture(_blocks, image, () => _blockResolver?.call(identity, image));

  ForumBodyInlineImageInput? inline(
    ForumBodyIdentity identity,
    ForumBodyElement image,
    ForumBodyResolvedStyle style,
  ) => _capture(
    _inlines,
    image,
    () => _inlineResolver?.call(identity, image, style),
  );

  T? _capture<T>(
    Map<ForumBodyElement, T?> values,
    ForumBodyElement image,
    T? Function() read,
  ) {
    if (_closed) throw StateError('Table image inputs are retired');
    if (values.containsKey(image)) return values[image];
    final value = read();
    if (_closed) throw StateError('Table image inputs are retired');
    return values[image] = value;
  }

  void close() {
    _closed = true;
    _blockResolver = null;
    _inlineResolver = null;
    _blocks.clear();
    _inlines.clear();
  }
}
