import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import '../flow/forum_body_inline_flow_content.dart';
import '../inline/forum_body_inline_image_input.dart';
import '../inline/forum_body_ruby_content.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_box_style.dart';
import '../style/forum_body_length.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_frozen_images.dart';
import 'forum_body_image_frame.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_text_page_preparation.dart';
import 'forum_body_text_page_session.dart';

enum ForumBodyFloatBodyFailure { structure, geometry, extentLimit }

final class ForumBodyFloatBodyException implements Exception {
  const ForumBodyFloatBodyException(this.failure, this.path);

  final ForumBodyFloatBodyFailure failure;
  final String path;

  @override
  String toString() => 'ForumBodyFloatBodyException(${failure.name})';
}

/// A measured source subtree. The float owns the child pages and their future
/// preparations. Its placement and the surrounding lines belong to the parent.
final class ForumBodyFloatBodyLayout {
  ForumBodyFloatBodyLayout._(
    this.source,
    this.margin,
    this.borderBoxSize,
    this.contentBounds,
    this._body,
    List<double> pageTops,
  ) : _pageTops = List.unmodifiable(pageTops);

  final ForumBodyInlineFlowFloat source;
  final EdgeInsets margin;
  final Size borderBoxSize;
  final Rect contentBounds;
  final ForumBodyTextPageSession _body;
  final List<double> _pageTops;

  Size get occupiedSize => Size(
    borderBoxSize.width + margin.horizontal,
    borderBoxSize.height + margin.vertical,
  );
  ForumBodyTextPageSnapshot get snapshot => _body.snapshot;
  bool get isClosed => _body.isClosed || _body.isLayoutOwnerRetired;
  double pageTop(int index) => _pageTops[index];
  ForumBodyTextPagePreparation openPagePreparation(int index) =>
      _body.openPagePreparation(index);

  void close() => _body.close();
}

/// Cooperatively measure a floated text container from its actual IR node.
/// Auto width uses the native min/preferred metrics, followed by one fixed
/// pass. Only that fixed pass is retained for delivery.
final class ForumBodyFloatBodyPreparation {
  ForumBodyFloatBodyPreparation({
    required ForumBodyDocument document,
    required this.source,
    required ForumBodyReaderStyle reader,
    required ForumBodyParagraphCache cache,
    required this.containingWidth,
    required this.layoutId,
    required this.limits,
    this.textScaler = TextScaler.noScaling,
    ForumBodyCollapseLayout? collapses,
    ForumBodyImageResolver? imageResolver,
    ForumBodyInlineImageResolver? inlineImageResolver,
    this.paragraphBuilder = const ForumBodyParagraphContentBuilder(),
    this.rubyLimits = const ForumBodyRubyContentLimits(),
  }) : _document = document,
       _reader = reader,
       _cache = cache,
       _collapses = collapses,
       _images = ForumBodyFrozenImages(imageResolver, inlineImageResolver) {
    if (!containingWidth.isFinite || containingWidth <= 0 || layoutId.isEmpty) {
      throw ArgumentError('Invalid float preparation inputs');
    }
    _guard();
    final element = source.element;
    final side = _style.floatSide;
    if (!identical(document.nodeAtPath(element.path), element) ||
        _style.hidden ||
        collapses?.hidesPath(element.path) == true ||
        (side != ForumBodyFloatSide.left && side != ForumBodyFloatSide.right) ||
        !const {
          ForumBodyElementKind.inline,
          ForumBodyElementKind.container,
          ForumBodyElementKind.paragraph,
          ForumBodyElementKind.heading,
        }.contains(element.kind)) {
      _fail(ForumBodyFloatBodyFailure.structure);
    }
    _margin = _insets(_style.margin);
    _padding = _insets(_style.padding);
    final specified = _contentLength(_style.box.width);
    if (specified != null) _setWidth(specified);
  }

  static const _maxWidth = 16384.0;
  static const _maxHeight = 1048576.0;
  final ForumBodyInlineFlowFloat source;
  final double containingWidth;
  final String layoutId;
  final ForumBodyTextPageSessionLimits limits;
  final TextScaler textScaler;
  final ForumBodyParagraphContentBuilder paragraphBuilder;
  final ForumBodyRubyContentLimits rubyLimits;
  final ForumBodyDocument _document;
  final ForumBodyReaderStyle _reader;
  final ForumBodyParagraphCache _cache;
  final ForumBodyCollapseLayout? _collapses;
  final ForumBodyFrozenImages _images;
  late final EdgeInsets _margin, _padding;
  final _pageTops = <double>[];
  double? _width;
  double _height = 0;
  ForumBodyTextPageSession? _active;
  ForumBodyFloatBodyLayout? _ready;
  bool _closed = false;
  bool _advancing = false;

  ForumBodyResolvedStyle get _style => source.event.style;
  bool get isReady => _ready != null;
  bool get isClosed => _closed;

  ({bool isReady, bool waitingForLayoutBudget, int layoutsBuilt}) advance({
    required int maxEvents,
    required int maxLines,
    int maxFormatParts = 32,
  }) {
    if (_advancing) throw StateError('Float preparation is reentrant');
    if (maxEvents <= 0 || maxLines <= 0 || maxFormatParts <= 0) {
      throw ArgumentError('Invalid float work budget');
    }
    _advancing = true;
    try {
      _guard();
      if (isReady) {
        return (isReady: true, waitingForLayoutBudget: false, layoutsBuilt: 0);
      }
      final probe = _width == null;
      final session = _active ??= _openBody(probe: probe);
      final step = session.advance(
        maxEvents: maxEvents,
        maxLines: maxLines,
        maxFormatParts: maxFormatParts,
      );
      _guard();
      if (!probe && step.pagesPublished != 0) {
        final snapshot = session.snapshot;
        while (_pageTops.length < snapshot.length) {
          final page = snapshot[_pageTops.length];
          _pageTops.add(_height);
          _height += page.usedHeight;
        }
        if (_height > _maxHeight) _fail(ForumBodyFloatBodyFailure.extentLimit);
      }
      if (session.isComplete) {
        if (probe) {
          final widths = session.intrinsicWidths!;
          final available =
              containingWidth - _margin.horizontal - _padding.horizontal;
          _setWidth(
            math.min(widths.preferred, math.max(widths.minimum, available)),
          );
          session.close();
        } else {
          _finish(session);
        }
        _active = null;
      }
      return (
        isReady: isReady,
        waitingForLayoutBudget: step.waitingForLayoutBudget,
        layoutsBuilt: step.layoutsBuilt,
      );
    } catch (_) {
      close();
      rethrow;
    } finally {
      _advancing = false;
    }
  }

  ForumBodyTextPageSession _openBody({required bool probe}) =>
      ForumBodyTextPageSession(
        document: _document,
        reader: _reader,
        cache: _cache,
        limits: limits,
        layoutId: '$layoutId/${source.element.path}',
        width: probe ? _maxWidth : (_width == 0 ? 1 : _width!),
        height: _maxHeight,
        textScaler: textScaler,
        paragraphBuilder: paragraphBuilder,
        rubyLimits: rubyLimits,
        collapses: _collapses,
        contentRoot: source.element,
        intrinsicAvailableWidth: probe ? containingWidth : null,
        imageResolver: _images.block,
        inlineImageResolver: _images.inline,
        tableExtent: ForumBodyTableExtent.natural,
      );

  void _setWidth(double width) {
    final box = _style.box;
    _width = math.max(
      _contentLength(box.minWidth) ?? 0,
      math.min(_contentLength(box.maxWidth) ?? double.infinity, width),
    );
    if (!_width!.isFinite ||
        _width! < 0 ||
        _width! + _padding.horizontal + _margin.horizontal > _maxWidth) {
      _fail(ForumBodyFloatBodyFailure.extentLimit);
    }
  }

  void _finish(ForumBodyTextPageSession session) {
    final width = _width!;
    if (width == 0 && _height != 0) _fail(ForumBodyFloatBodyFailure.geometry);
    final authorHeight = _style.box.height;
    // A float in this flow has no definite containing height. Keep overflow
    // inside the exclusion even when a fixed author height is smaller.
    final resolvedHeight = authorHeight?.unit == ForumBodyLengthUnit.percent
        ? 0.0
        : (_length(authorHeight) ?? 0.0);
    final height = math.max(
      _height + _padding.vertical,
      _style.box.sizing == ForumBodyBoxSizing.borderBox
          ? resolvedHeight
          : resolvedHeight + _padding.vertical,
    );
    if (!height.isFinite || height + _margin.vertical > _maxHeight) {
      _fail(ForumBodyFloatBodyFailure.extentLimit);
    }
    _ready = ForumBodyFloatBodyLayout._(
      source,
      _margin,
      Size(width + _padding.horizontal, height),
      Rect.fromLTWH(_padding.left, _padding.top, width, _height),
      session,
      _pageTops,
    );
    _images.close();
  }

  double? _length(ForumBodyLength? length) =>
      length == null || length.unit == ForumBodyLengthUnit.auto
      ? null
      : length.resolve(
          fontSize: _style.textStyle.fontSize!,
          rootFontSize: _reader.textStyle.fontSize!,
          reference: containingWidth,
        );

  double? _contentLength(ForumBodyLength? length) {
    final pixels = _length(length);
    if (pixels == null) return null;
    return _style.box.sizing == ForumBodyBoxSizing.borderBox
        ? math.max(0, pixels - _padding.horizontal)
        : pixels;
  }

  EdgeInsets _insets(ForumBodyInsets value) {
    final insets = EdgeInsets.fromLTRB(
      _length(value.left) ?? 0,
      _length(value.top) ?? 0,
      _length(value.right) ?? 0,
      _length(value.bottom) ?? 0,
    );
    if (!insets.isNonNegative ||
        !insets.horizontal.isFinite ||
        !insets.vertical.isFinite) {
      _fail(ForumBodyFloatBodyFailure.geometry);
    }
    return insets;
  }

  ForumBodyFloatBodyLayout takeLayout() {
    _guard();
    if (_advancing || !isReady) {
      throw StateError('Float preparation is incomplete');
    }
    final layout = _ready!;
    _ready = null;
    close();
    return layout;
  }

  void _guard() {
    if (_closed) throw StateError('Float preparation is closed');
    if (_cache.isClosed) {
      close();
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.ownerRetired,
      );
    }
  }

  Never _fail(ForumBodyFloatBodyFailure failure) =>
      throw ForumBodyFloatBodyException(failure, source.element.path);

  void close() {
    if (_closed) return;
    _closed = true;
    _active?.close();
    _active = null;
    _ready?.close();
    _ready = null;
    _pageTops.clear();
    _images.close();
  }
}
