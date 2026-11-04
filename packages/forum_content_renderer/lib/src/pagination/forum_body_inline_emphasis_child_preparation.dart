part of 'forum_body_inline_page_preparation.dart';

/// Actual visible children in one legal source window, moved to the allocated
/// parent rows. Owns the existing source-bound view, including its natural
/// parent alias, child glyphs and child marker scenes. Parent glyphs/markers
/// are composed separately; this value does not publish a readable page.
final class ForumBodyInlineEmphasisChildView {
  ForumBodyInlineEmphasisChildView._(
    this.allocation,
    this.startLine,
    this.endLine,
    this.top,
    this.height,
    ForumBodyInlineParagraphView children,
    Map<int, Offset> origins,
    List<({Rect rect, ForumBodyRubyContainerFontBox font})> backgrounds,
    this._ensureOwner,
  ) : _children = children,
      _origins = UnmodifiableMapView(origins),
      backgroundSurfaces = UnmodifiableListView(backgrounds);
  final ForumBodyInlineEmphasisRowAllocation allocation;
  final int startLine, endLine;
  final double top, height;
  final Map<int, Offset> _origins;
  final List<({Rect rect, ForumBodyRubyContainerFontBox font})>
  backgroundSurfaces;
  final void Function() _ensureOwner;
  ForumBodyInlineParagraphView? _children;
  bool get isActive => _children?.isActive == true;
  Iterable<int> get atomIndices {
    _guard();
    return _origins.keys;
  }

  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _children?.nativeLeases ?? const [];
  Offset originForAtom(int atom) {
    _guard();
    final origin = _origins[atom];
    if (origin == null) {
      throw const ForumBodyInlineViewException(
        ForumBodyInlineViewFailure.coverage,
      );
    }
    return origin;
  }

  void paintAtom(Canvas canvas, Offset offset, int atom) {
    _guard();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    _children!.paintBoundAtomAt(canvas, offset + originForAtom(atom), atom);
    _guard();
  }

  void paintContainerBackgrounds(Canvas canvas, Offset offset) {
    _guard();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    for (final surface in backgroundSurfaces) {
      canvas.drawRect(
        surface.rect.shift(offset),
        Paint()..color = surface.font.background.color,
      );
    }
    _guard();
  }

  /// Uses this binding's actual allocated origins and already-merged surfaces.
  /// Parent text/markers remain separate; this is not readable-page admission.
  Iterable<ForumBodyInlinePaintCommand?> paintCommands(
    Offset offset, {
    bool paintBackgrounds = true,
  }) sync* {
    void check() {
      _ensureOwner();
      if (_children == null) throw StateError('Allocated children are retired');
      if (!offset.dx.isFinite || !offset.dy.isFinite) {
        throw ArgumentError.value(offset);
      }
    }

    check();
    if (paintBackgrounds) {
      for (final surface in backgroundSurfaces) {
        check();
        yield ForumBodyInlinePaintCommand.fill(
          surface.rect,
          surface.font.background.color,
          offset,
        );
      }
    }
    for (final entry in _origins.entries) {
      yield null;
      check();
      for (final step in _children!.boundAtomPaintCommandsAt(
        offset + entry.value,
        entry.key,
      )) {
        check();
        yield step;
      }
    }
    check();
  }

  void _guard() {
    _ensureOwner();
    if (!isActive) throw StateError('Allocated children are retired');
  }

  void close() {
    final children = _children;
    _children = null;
    children?.close();
  }

  /// Transfers the already qualified natural source/child binding. Its caller
  /// supplies the allocated parent paint and keeps the allocation's geometry;
  /// this view returns to its original natural coordinates after transfer.
  ForumBodyInlineParagraphView takeSourceView() {
    _guard();
    final result = _children!;
    _children = null;
    return result;
  }
}

enum _EmphasisChildPhase {
  scales,
  atoms,
  prefix,
  probe,
  alias,
  children,
  origins,
  backgrounds,
  publish,
  ready,
  transferred,
  closed,
}

/// Source qualification and aggregate preflight surround the EXISTING inline
/// page/child transaction. No second child renderer, source lookup or cache is
/// introduced. Only a current natural parent's real legal fragment enters the
/// private current-parent path; paint layers cannot stand in for this source.
final class ForumBodyInlineEmphasisChildPreparation {
  ForumBodyInlineEmphasisChildPreparation({
    required ForumBodyInlineEmphasisRowAllocation allocation,
    required ForumBodyInlineParagraphLease natural,
    required ForumBodyParagraphCache cache,
    required TextScaler expectedTextScaler,
    required void Function() ensureOwner,
    void Function()? ensureVisibleOwner,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
    this.startLine = 0,
    int? endLine,
    this.maxAtoms = 512,
    this.maxBackgrounds = 32768,
    this.maxPrefixLeases = 32768,
  }) : _allocation = allocation,
       _natural = natural,
       _cache = cache,
       _callerScaler = expectedTextScaler,
       _ensureOwner = ensureOwner,
       _ensureVisibleOwner = ensureVisibleOwner ?? ensureOwner,
       _additionalOwned = additionalOwnedLeases,
       endLine = endLine ?? allocation.rows.length {
    if (maxAtoms < 0 || maxBackgrounds < 0 || maxPrefixLeases <= 0) {
      throw ArgumentError('Invalid child binding budget');
    }
    try {
      _guard();
      final input = allocation.input,
          metrics = input.natural,
          page = metrics.page;
      if (natural.nativeInputIdentity != input.reference.naturalInputIdentity ||
          !identical(natural.layout.lines, input.reference.naturalLines) ||
          !identical(natural.content, metrics.text.glyphInput.glyphs) ||
          !identical(page.content, metrics.text.glyphInput.original) ||
          natural.layout.rowIsolationPitch != null) {
        _identity();
      }
      if (page.rubyAtoms.length > maxAtoms) _limit();
      _window = natural.layout.fragment(startLine, this.endLine);
      _top = allocation.rows[startLine].line.top;
      _height = allocation.rows[this.endLine - 1].line.bottom - _top;
      _page = ForumBodyInlinePageContent.atoms(
        content: natural.content,
        dimensions: page.dimensions,
        rubyAtoms: page.rubyAtoms,
        trimmedAtomIndices: page.trimmedAtomIndices,
        containerBackgrounds: page.containerBackgrounds,
        rootFonts: page.rootFonts,
        layoutMode: page.layoutMode,
      );
      _scales = metrics.effectiveScales.entries.iterator;
      _atoms = _window!.atomIndices.iterator;
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  final int startLine, endLine, maxAtoms, maxBackgrounds;

  /// Bounds enumeration of the borrowed natural parent and caller prefix. The
  /// existing page transaction owns total transient/retained child handle caps;
  /// this worker's complete native-footprint probe bounds cache admission.
  final int maxPrefixLeases;
  ForumBodyInlineEmphasisRowAllocation? _allocation;
  ForumBodyInlineParagraphLease? _natural, _pending;
  ForumBodyParagraphCache? _cache;
  TextScaler? _callerScaler;
  Iterator<MapEntry<double, double>>? _scales;
  void Function()? _ensureOwner, _ensureVisibleOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  ForumBodyInlineParagraphFragment? _window;
  ForumBodyInlinePageContent? _page;
  Iterator<int>? _atoms, _boundAtoms;
  List<int> _indices = [];
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  ForumBodyParagraphBudgetProbe? _probe;
  Iterator<ForumBodyNativeBudgetSlot>? _slots;
  ForumBodyInlinePagePreparation? _childJob;
  ForumBodyInlineParagraphView? _children;
  Map<int, Offset> _origins = {};
  List<({Rect rect, ForumBodyRubyContainerFontBox font})> _backgrounds = [];
  List<({int lineIndex, Rect rect, ForumBodyRubyContainerFontBox font})>?
  _regions;
  ForumBodyInlineEmphasisChildView? _result;
  var _phase = _EmphasisChildPhase.scales;
  int _prefixCount = 1, _atom = 0, _background = 0, _blockedAt = -1;
  double _top = 0, _height = 0;
  bool _operating = false, _miss = false;
  bool get isReady => _phase == _EmphasisChildPhase.ready;
  bool get cacheMiss => _miss;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ?_pending,
    if (_childJob != null) ..._childJob!.nativeLeases,
    if (_children != null) ..._children!.nativeLeases,
    if (_result != null) ..._result!.nativeLeases,
  ];
  Iterable<ForumBodyNativeParagraphLease> _owned() sync* {
    final extra =
        _additionalOwned?.call() ?? const <ForumBodyNativeParagraphLease>[];
    _guard();
    yield _natural!;
    yield* extra;
    yield* nativeLeases;
  }

  ForumBodyEmphasisLineStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) {
      throw StateError('Allocated child preparation is reentrant');
    }
    _operating = true;
    final cache = _cache,
        builds = cache?.layoutBuildCount ?? 0,
        pictures = cache?.pictureBuildCount ?? 0;
    var used = 0;
    ForumBodyEmphasisLineStep step([bool wait = false]) => (
      partsPrepared: used,
      nativeLayoutsBuilt: cache!.layoutBuildCount - builds,
      picturesRecorded: cache.pictureBuildCount - pictures,
      waitingForLayoutBudget: wait,
    );
    try {
      _guard();
      _miss = false;
      if (_blockedAt == cache!.budgetRevision) return step(true);
      while (!isReady &&
          used < maxParts &&
          cache.layoutBuildCount == builds &&
          cache.pictureBuildCount == pictures) {
        final metrics = _allocation!.input.natural;
        switch (_phase) {
          case _EmphasisChildPhase.scales:
            if (_scales!.moveNext()) {
              final sample = _scales!.current,
                  actual = _callerScaler!.scale(sample.key);
              _guard();
              if (!actual.isFinite ||
                  actual <= 0 ||
                  actual > 4096 ||
                  actual != sample.value) {
                _identity();
              }
            } else {
              _callerScaler = null;
              _scales = null;
              _phase = _EmphasisChildPhase.atoms;
            }
          case _EmphasisChildPhase.atoms:
            if (_atoms!.moveNext()) {
              _guard();
              _indices.add(_atoms!.current);
            } else {
              _atoms = null;
              _probe = cache.createBudgetProbe();
              _probe!.includeLease(_natural!);
              final extra =
                  _additionalOwned?.call() ??
                  const <ForumBodyNativeParagraphLease>[];
              _guard();
              final iterator = extra.iterator;
              _guard();
              _prefix = iterator;
              _phase = _EmphasisChildPhase.prefix;
            }
          case _EmphasisChildPhase.prefix:
            final more = _prefix!.moveNext();
            _guard();
            if (more) {
              if (_prefixCount++ >= maxPrefixLeases) _limit();
              final parent = _prefix!.current;
              _guard();
              _probe!.includeLease(parent);
            } else {
              _prefix = null;
              _phase = _EmphasisChildPhase.probe;
            }
          case _EmphasisChildPhase.probe:
            if (_slots == null && _atom < _indices.length) {
              _slots = _page!
                  .rubyAtoms[_indices[_atom++]]
                  .nativeBudgetFootprint
                  .iterator;
            } else if (_slots != null) {
              final more = _slots!.moveNext();
              _guard();
              if (more) {
                final s = _slots!.current;
                _guard();
                s.request.includeBudget(
                  _probe!,
                  width: s.width,
                  textScaler: metrics.textScaler,
                  minimumLineCount: s.minimumLineCount,
                );
              } else {
                _slots = null;
              }
            } else {
              _probe!.close();
              _probe = null;
              _phase = _EmphasisChildPhase.alias;
            }
          case _EmphasisChildPhase.alias:
            _pending = metrics.parentRequest.acquire(
              cache,
              width: metrics.requestWidth,
              textScaler: metrics.textScaler,
              cachedOnly: true,
            );
            _guard();
            if (_pending == null) {
              throw StateError('Current natural parent disappeared');
            }
            _childJob = ForumBodyInlinePagePreparation._current(
              input: _page!,
              parent: _pending!,
              window: _window!,
              identity: _page!.identity,
              cache: cache,
              textScaler: metrics.textScaler,
              ensureOwner: _guard,
              ensureVisibleOwner: _ensureVisibleOwner!,
              ownedPageLeases: _owned,
            );
            _pending = null;
            _phase = _EmphasisChildPhase.children;
          case _EmphasisChildPhase.children:
            final rejectedAt = cache.budgetRevision,
                job = _childJob!,
                before = job.workCount;
            try {
              final value = job.advance(
                cachedOnly: cachedOnly,
                maxParts: maxParts - used,
              );
              used += job.workCount == before ? 1 : job.workCount - before;
              try {
                _guard();
              } catch (_) {
                value.view?.close();
                rethrow;
              }
              _miss = value.cacheMiss;
              if (value.view case final view?) {
                try {
                  _guard();
                } catch (_) {
                  view.close();
                  rethrow;
                }
                _children = view;
                _childJob = null;
                if (!view.matchesCurrentParent(_natural!)) _identity();
                _boundAtoms = view.atomIndices.iterator;
                _phase = _EmphasisChildPhase.origins;
              }
              if (_miss || job.waitingForLayoutBudget) {
                if (job.waitingForLayoutBudget) {
                  _blockedAt = cache.budgetRevision;
                }
                return step(job.waitingForLayoutBudget);
              }
            } on ForumBodyParagraphBudgetException catch (error) {
              _guard();
              if (error.failure != ForumBodyParagraphBudgetFailure.pinned) {
                rethrow;
              }
              used = maxParts;
              _blockedAt = rejectedAt;
              return step(cache.budgetRevision == rejectedAt);
            }
            continue;
          case _EmphasisChildPhase.origins:
            final more = _boundAtoms!.moveNext();
            _guard();
            if (more) {
              final atom = _boundAtoms!.current,
                  child = _allocation!.children[atom];
              if (child == null ||
                  child.lineIndex < startLine ||
                  child.lineIndex >= endLine ||
                  !_indices.contains(atom)) {
                _identity();
              }
              _origins[atom] = child.offset - Offset(0, _top);
            } else {
              _boundAtoms = null;
              if (_origins.length != _indices.length) _identity();
              _regions = _children!.backgroundRows;
              _phase = _EmphasisChildPhase.backgrounds;
            }
          case _EmphasisChildPhase.backgrounds:
            if (_background < _regions!.length) {
              if (_background >= maxBackgrounds) _limit();
              final r = _regions![_background++];
              if (r.lineIndex < startLine || r.lineIndex >= endLine) {
                _identity();
              }
              _backgrounds.add((
                rect: r.rect.shift(
                  Offset(0, _window!.top - _top) +
                      _allocation!.rows[r.lineIndex].naturalOffset,
                ),
                font: r.font,
              ));
            } else {
              _regions = null;
              _phase = _EmphasisChildPhase.publish;
            }
          case _EmphasisChildPhase.publish:
            final visible = _ensureVisibleOwner!;
            visible();
            _guard();
            _result = ForumBodyInlineEmphasisChildView._(
              _allocation!,
              startLine,
              endLine,
              _top,
              _height,
              _children!,
              _origins,
              _backgrounds,
              visible,
            );
            _children = null;
            _origins = {};
            _backgrounds = [];
            _phase = _EmphasisChildPhase.ready;
          case _EmphasisChildPhase.ready:
          case _EmphasisChildPhase.transferred:
          case _EmphasisChildPhase.closed:
            throw StateError('Allocated child preparation is retired');
        }
        used++;
        _guard();
      }
      return step();
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyInlineEmphasisChildView takeView() {
    if (_operating) {
      throw StateError('Allocated child preparation is reentrant');
    }
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Allocated children are incomplete');
      _ensureVisibleOwner!();
      _guard();
      final result = _result!;
      _result = null;
      _phase = _EmphasisChildPhase.transferred;
      _drop();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _EmphasisChildPhase.closed ||
        _phase == _EmphasisChildPhase.transferred) {
      throw StateError('Allocated child preparation is retired');
    }
    _ensureOwner!();
    if (_phase == _EmphasisChildPhase.closed ||
        _phase == _EmphasisChildPhase.transferred ||
        _cache!.isClosed ||
        !_cache!.ownsLease(_natural!)) {
      throw StateError('Allocated child owner is retired');
    }
  }

  void close() {
    if (_phase == _EmphasisChildPhase.closed ||
        _phase == _EmphasisChildPhase.transferred) {
      return;
    }
    _phase = _EmphasisChildPhase.closed;
    try {
      _pending?.release();
      _childJob?.close();
      _children?.close();
      _result?.close();
    } finally {
      _pending = null;
      _childJob = null;
      _children = null;
      _result = null;
      _drop();
    }
  }

  void _drop() {
    _probe?.close();
    _probe = null;
    _slots = null;
    _prefix = null;
    _scales = null;
    _callerScaler = null;
    _window = null;
    _page = null;
    _allocation = null;
    _natural = null;
    _cache = null;
    _ensureOwner = _ensureVisibleOwner = null;
    _additionalOwned = null;
    _atoms = _boundAtoms = null;
    _indices = [];
    _origins = {};
    _backgrounds = [];
    _regions = null;
  }

  static Never _identity() => throw const ForumBodyInlineViewException(
    ForumBodyInlineViewFailure.identity,
  );
  static Never _limit() => throw const ForumBodyEmphasisAllocationException(
    ForumBodyEmphasisAllocationFailure.limit,
  );
}
