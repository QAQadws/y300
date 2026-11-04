part of 'forum_body_ruby_tree_input.dart';

/// An original/current source associated with an actual adopted glyph member.
/// The native key is metadata, not a resource or complete decorated-tree proof.
final class ForumBodyRubyGlyphTreeBoundSource {
  const ForumBodyRubyGlyphTreeBoundSource._(
    this.position,
    this.glyphNativeInputIdentity,
  );
  final ForumBodyRubyGlyphTreeSourcePosition position;
  ForumBodyRubyGlyphTreeSource get source => position.source;
  final Object? glyphNativeInputIdentity;
  bool get usesInlineParent => position.usesInlineParent;
}

/// Actual glyph-plane ownership with explicit original source associations.
/// Markers and their scene must still bind separately before a decorated format
/// can claim complete paint/coverage. The private glyph TreeLayout is never
/// exposed as an original-source-ready undecorated tree.
final class ForumBodyRubyGlyphTreeBinding {
  ForumBodyRubyGlyphTreeBinding._(
    this.geometry,
    this._tree,
    List<ForumBodyRubyGlyphTreeBoundSource> sources,
    Map<int, ForumBodyRubyGlyphTreeBoundSource> bySource,
    this._ensureOwner,
  ) : sources = UnmodifiableListView(sources),
      _bySource = UnmodifiableMapView(bySource);
  final ForumBodyRubyGlyphTreeGeometry geometry;
  ForumBodyRubyTreeLayout? _tree;
  final List<ForumBodyRubyGlyphTreeBoundSource> sources;
  final Map<int, ForumBodyRubyGlyphTreeBoundSource> _bySource;
  void Function()? _ensureOwner;
  bool get isActive => _tree?.isActive == true;
  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      _tree?.isOwnedBy(cache) == true;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _tree?.nativeLeases ?? const [];
  ForumBodyRubyGlyphTreeBoundSource sourceForId(int id) =>
      _bySource[id] ?? (throw ArgumentError.value(id, 'id'));
  List<({Rect rect, ForumBodyRubyContainerFontBox font})> get backgrounds {
    ensureActive();
    return _tree!.backgrounds;
  }

  void ensureActive() {
    if (!isActive) throw StateError('Ruby glyph binding is retired');
    _ensureOwner!();
    if (!isActive) throw StateError('Ruby glyph owner is retired');
  }

  void paintGlyphs(Canvas canvas, Offset offset) {
    ensureActive();
    _tree!.paint(canvas, offset);
  }

  Iterable<ForumBodyInlinePaintCommand?> paintCommands(Offset offset) sync* {
    final tree = _tree;
    if (tree == null) throw StateError('Ruby glyph binding is retired');
    void check() {
      _ensureOwner?.call();
      if (!identical(_tree, tree)) {
        throw StateError('Ruby glyph owner is retired');
      }
    }

    check();
    for (final step in tree.paintCommands(offset)) {
      check();
      yield step;
    }
    check();
  }

  void paintBackgrounds(Canvas canvas, Offset offset, {required Rect clip}) {
    ensureActive();
    _tree!.paintBackgrounds(canvas, offset, clip: clip);
  }

  /// Returns the original current display window, never the suppressed glyph
  /// style table. Original author context remains in the bound source record.
  ForumBodyRubyTreeHit sourceAtGlyph(Offset offset) {
    ensureActive();
    final hit = _tree!.sourceAt(offset),
        source = sourceForId(hit.nodeIndex).source;
    if (!identical(hit.content, source.glyphs)) {
      throw const ForumBodyEmphasisLineException(
        ForumBodyEmphasisLineFailure.source,
      );
    }
    final projected = source.content.projection.sourceAtUtf16(
      hit.position.displayUtf16,
    );
    return (
      nodeIndex: hit.nodeIndex,
      content: source.content,
      position: HtmlProjectedSourcePosition(
        sourceRune: projected.sourceRune,
        displayUtf16: projected.displayUtf16,
        isExact:
            !source.content.isSourceFree &&
            hit.position.isExact &&
            projected.isExact &&
            projected.sourceRune == hit.position.sourceRune,
      ),
    );
  }

  List<TextBox> glyphSelectionBoxes({
    required int sourceId,
    required int startUtf16,
    required int endUtf16,
    bool paintedOnly = false,
  }) {
    ensureActive();
    final source = sourceForId(sourceId).source;
    RangeError.checkValidRange(
      startUtf16,
      endUtf16,
      source.content.projection.text.length,
    );
    return _tree!.selectionBoxes(
      nodeIndex: sourceId,
      startUtf16: startUtf16,
      endUtf16: endUtf16,
      paintedOnly: paintedOnly,
    );
  }

  void close() {
    final tree = _tree;
    _tree = null;
    _ensureOwner = null;
    tree?.close();
  }
}

enum _GlyphBindingPhase { native, sources, publish, ready, transferred, closed }

/// Reuse actual tree preparation, including opaque inline parents, then qualify
/// one original source/member per part. No text equality or numeric box equality
/// can substitute another derivation, request mapping or measured graph.
final class ForumBodyRubyGlyphTreeBindingPreparation {
  ForumBodyRubyGlyphTreeBindingPreparation({
    required ForumBodyRubyGlyphTreeGeometry geometry,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    required TextScaler expectedTextScaler,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _geometry = geometry,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner ?? ensureOwner {
    _worker = ForumBodyRubyTreePreparation(
      input: geometry.metrics.input._glyphTree,
      metrics: geometry.metrics._value,
      cache: cache,
      ensureOwner: _guard,
      expectedTextScaler: expectedTextScaler,
      additionalOwnedLeases: additionalOwnedLeases,
    );
  }
  ForumBodyRubyGlyphTreeGeometry? _geometry;
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  ForumBodyRubyTreePreparation? _worker;
  ForumBodyRubyTreeLayout? _tree;
  List<ForumBodyRubyGlyphTreeBoundSource> _sources = [];
  Map<int, ForumBodyRubyGlyphTreeBoundSource> _bySource = {};
  ForumBodyRubyGlyphTreeBinding? _result;
  var _phase = _GlyphBindingPhase.native;
  int _index = 0;
  bool _operating = false, _cacheMiss = false, _waiting = false;
  bool get isReady => _phase == _GlyphBindingPhase.ready;
  bool get cacheMiss => _cacheMiss;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _worker?.lastBudgetRejection;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _result?.nativeLeases ??
      _tree?.nativeLeases ??
      _worker?.nativeLeases ??
      const [];

  ForumBodyRubyGroupPreparationStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      final cache = _cache!,
          builds = cache.layoutBuildCount,
          pictures = cache.pictureBuildCount;
      final before = _index;
      var parts = 0;
      _cacheMiss = _waiting = false;
      while (!isReady && parts < maxParts) {
        switch (_phase) {
          case _GlyphBindingPhase.native:
            final work = _worker!,
                step = work.advance(maxParts: 1, cachedOnly: cachedOnly);
            parts += step.formatUnitsPrepared;
            _cacheMiss = work.cacheMiss;
            _waiting = step.waitingForLayoutBudget;
            _guard();
            if (work.isReady) {
              _tree = work.takeLayout();
              _worker = null;
              work.close();
              if (_tree!.members.length !=
                  _geometry!.metrics.input.sources.length) {
                _mismatch();
              }
              _phase = _GlyphBindingPhase.sources;
            }
            if (step.formatUnitsPrepared == 0 || _cacheMiss || _waiting) {
              return _step(parts, before, builds, pictures);
            }
          case _GlyphBindingPhase.sources:
            if (_index < _geometry!.sources.length) {
              _qualify(_geometry!.sources[_index], _tree!.members[_index]);
              _index++;
            } else {
              _phase = _GlyphBindingPhase.publish;
            }
            parts++;
          case _GlyphBindingPhase.publish:
            _checkVisibleOwner();
            _result = ForumBodyRubyGlyphTreeBinding._(
              _geometry!,
              _tree!,
              _sources,
              _bySource,
              _ensureVisibleOwner!,
            );
            _sources = [];
            _bySource = {};
            _phase = _GlyphBindingPhase.ready;
            parts++;
          case _GlyphBindingPhase.ready:
          case _GlyphBindingPhase.transferred:
          case _GlyphBindingPhase.closed:
            throw StateError('Ruby glyph binding preparation is retired');
        }
        _guard();
        if (cache.layoutBuildCount != builds ||
            cache.pictureBuildCount != pictures) {
          break;
        }
      }
      return _step(parts, before, builds, pictures);
    });
  }

  ForumBodyRubyGroupPreparationStep _step(
    int parts,
    int before,
    int builds,
    int pictures,
  ) => ForumBodyRubyGroupPreparationStep(
    partsPrepared: _index - before,
    layoutsBuilt: _cache!.layoutBuildCount - builds,
    picturesBuilt: _cache!.pictureBuildCount - pictures,
    partsInspected: 0,
    formatUnitsPrepared: parts,
    isReady: isReady,
    waitingForLayoutBudget: _waiting,
  );

  void _qualify(
    ForumBodyRubyGlyphTreeSourcePosition position,
    ForumBodyRubyTreeMember member,
  ) {
    final source = position.source,
        original = _geometry!.metrics.input.sourceTree.sources[_index];
    if (original.id != source.id ||
        !identical(original.content, source.content) ||
        member.nodeIndex != source.id ||
        !identical(member.content, source.glyphs) ||
        member.offset != position.contextOrigin ||
        (!identical(source.content.projection, source.glyphs.projection) &&
            !(source.content.isSourceFree && source.glyphs.isSourceFree))) {
      _mismatch();
    }
    final emphasis = source.emphasis;
    if (emphasis != null &&
        (!identical(emphasis.content, source.content) ||
            !identical(emphasis.glyphInput.glyphs, source.glyphs))) {
      _mismatch();
    }
    if (source.id < 0) {
      if (member.lease != null ||
          member.inlineView == null ||
          member.inlineWindow == null ||
          !identical(member.inlineWindow!.content, source.glyphs) ||
          !identical(source.content, source.glyphs) ||
          source.needsNative) {
        _mismatch();
      }
    } else if (source.needsNative) {
      final lease = member.lease;
      if (lease == null ||
          !_cache!.ownsLease(lease) ||
          member.inlineView != null ||
          !identical(lease.content, source.glyphs) ||
          !identical(
            _geometry!.metrics.input.requestForSource(source.id).content,
            source.glyphs,
          )) {
        _mismatch();
      }
    } else if (member.lease != null || member.inlineView != null) {
      _mismatch();
    }
    final bound = ForumBodyRubyGlyphTreeBoundSource._(
      position,
      member.lease?.nativeInputIdentity,
    );
    _sources.add(bound);
    _bySource[source.id] = bound;
  }

  static Never _mismatch() => throw const ForumBodyEmphasisLineException(
    ForumBodyEmphasisLineFailure.source,
  );

  ForumBodyRubyGlyphTreeBinding takeBinding() => _operate(() {
    _guard();
    if (!isReady) {
      throw StateError('Ruby glyph binding preparation is incomplete');
    }
    _checkVisibleOwner();
    final result = _result!;
    _result = null;
    _tree = null;
    _phase = _GlyphBindingPhase.transferred;
    _drop();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Ruby glyph binding preparation is reentrant');
    }
    _operating = true;
    try {
      return action();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _GlyphBindingPhase.closed ||
        _phase == _GlyphBindingPhase.transferred) {
      throw StateError('Ruby glyph binding preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _GlyphBindingPhase.closed || _cache!.isClosed) {
      throw StateError('Ruby glyph binding owner is retired');
    }
  }

  void _checkVisibleOwner() {
    _ensureVisibleOwner!();
    _guard();
  }

  void _drop() {
    _worker?.close();
    _worker = null;
    _tree?.close();
    _tree = null;
    _geometry = null;
    _cache = null;
    _ensureOwner = null;
    _ensureVisibleOwner = null;
    _sources = [];
    _bySource = {};
  }

  void close() {
    if (_phase == _GlyphBindingPhase.closed ||
        _phase == _GlyphBindingPhase.transferred) {
      return;
    }
    _phase = _GlyphBindingPhase.closed;
    _result?.close();
    _result = null;
    _drop();
  }
}
