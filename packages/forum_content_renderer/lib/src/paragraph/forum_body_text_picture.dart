part of 'forum_body_paragraph_cache.dart';

typedef _TextPictureDependency = ({
  Object identity,
  int? bandChildIndex,
  ForumBodyParagraphRowSelector? paragraphRow,
  ForumBodyInlinePaintRowSelector? inlineRow,
});

final class ForumBodyTextPictureCommand {
  const ForumBodyTextPictureCommand({
    required this.nativeInputIdentity,
    required this.offset,
    this.bandChildIndex,
    this.paragraphRow,
    this.physicalLine,
    this.inlineRow,
    this.fitScale = 1,
  }) : _translation = null;
  const ForumBodyTextPictureCommand._translated({
    required this.nativeInputIdentity,
    required this.offset,
    required this.fitScale,
    required this.bandChildIndex,
    required this.paragraphRow,
    required this.physicalLine,
    required this.inlineRow,
    required _TextPictureTranslation translation,
  }) : _translation = translation;
  static const maximumTranslationDepth = 8;
  final _TextPictureTranslation? _translation;

  /// Preserve the original native transform order. Adding two double offsets
  /// before Canvas records them can change float precision and shadow pixels.
  ForumBodyTextPictureCommand translated(Offset by) {
    if (by == Offset.zero) return this;
    return ForumBodyTextPictureCommand._translated(
      nativeInputIdentity: nativeInputIdentity,
      offset: offset,
      fitScale: fitScale,
      bandChildIndex: bandChildIndex,
      paragraphRow: paragraphRow,
      physicalLine: physicalLine,
      inlineRow: inlineRow,
      translation: _TextPictureTranslation(by, _translation),
    );
  }

  int get translationDepth => _translation?.depth ?? 0;
  static const translationInputEstimatedBytes = 64;
  static const translationPictureEstimatedBytes = 64;

  /// Command-only retention; the unique opaque native metadata is separate.
  int get estimatedInputBytes =>
      128 +
      (paragraphRow == null ? 0 : 64) +
      (physicalLine == null ? 0 : 192) +
      (inlineRow == null ? 0 : 128) +
      translationDepth * translationInputEstimatedBytes;
  int get estimatedPictureBytes =>
      256 + translationDepth * translationPictureEstimatedBytes;
  Offset get sceneOffset => (_translation?.total ?? Offset.zero) + offset;
  Iterable<Offset> get translations sync* {
    var current = _translation;
    while (current != null) {
      yield current.offset;
      current = current.inner;
    }
  }

  factory ForumBodyTextPictureCommand.fromText(
    ForumBodyTextLease text,
    Offset offset, {
    double fitScale = 1,
  }) => ForumBodyTextPictureCommand(
    nativeInputIdentity: text.nativeInputIdentity,
    offset: offset,
    fitScale: fitScale,
    bandChildIndex: text is ForumBodyTextBandChildLease
        ? text.childIndex
        : null,
  );
  factory ForumBodyTextPictureCommand.fromEmphasisMark(
    ForumBodyEmphasisMarkLease mark,
    Offset offset, {
    double fitScale = 1,
  }) => ForumBodyTextPictureCommand(
    nativeInputIdentity: mark.nativeInputIdentity,
    offset: offset,
    fitScale: fitScale,
  );
  factory ForumBodyTextPictureCommand.fromParagraphRow(
    ForumBodyParagraphRowView row,
    Offset offset, {
    double fitScale = 1,
  }) => ForumBodyTextPictureCommand(
    nativeInputIdentity: row.nativeInputIdentity,
    offset: offset,
    fitScale: fitScale,
    paragraphRow: row.selector,
  );
  factory ForumBodyTextPictureCommand.fromPhysicalLine(
    ForumBodyParagraphRowView group,
    ForumBodyParagraphPhysicalLineSelector line,
    Offset offset, {
    double fitScale = 1,
  }) {
    final identity = group.nativeInputIdentity;
    if (!line.matchesInput(
      nativeInputIdentity: identity,
      group: group.selector,
    )) {
      throw ArgumentError('Physical line belongs to another paragraph group');
    }
    return ForumBodyTextPictureCommand(
      nativeInputIdentity: identity,
      offset: offset,
      fitScale: fitScale,
      paragraphRow: group.selector,
      physicalLine: line,
    );
  }
  final Object nativeInputIdentity;
  final Offset offset;

  /// A uniform fitting transform around the resource's local origin. Offset
  /// stays in scene coordinates; this does not resample the font TextScaler.
  final double fitScale;
  // Several source-bound views share a band key but paint different strips.
  final int? bandChildIndex;
  final ForumBodyParagraphRowSelector? paragraphRow;
  final ForumBodyParagraphPhysicalLineSelector? physicalLine;
  final ForumBodyInlinePaintRowSelector? inlineRow;
  factory ForumBodyTextPictureCommand.fromInlineRow(
    ForumBodyInlinePaintRowView row,
    Offset offset,
  ) => ForumBodyTextPictureCommand(
    nativeInputIdentity: row.nativeInputIdentity,
    offset: offset,
    inlineRow: row.selector,
  );
  _TextPictureDependency get _dependency => (
    identity: nativeInputIdentity,
    bandChildIndex: bandChildIndex,
    paragraphRow: paragraphRow,
    inlineRow: inlineRow,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumBodyTextPictureCommand &&
          nativeInputIdentity == other.nativeInputIdentity &&
          offset == other.offset &&
          bandChildIndex == other.bandChildIndex &&
          paragraphRow == other.paragraphRow &&
          physicalLine == other.physicalLine &&
          inlineRow == other.inlineRow &&
          _translation == other._translation &&
          fitScale == other.fitScale;
  @override
  int get hashCode => Object.hash(
    nativeInputIdentity,
    offset,
    bandChildIndex,
    paragraphRow,
    physicalLine,
    inlineRow,
    fitScale,
    _translation,
  );
}

/// An owned drawing resource only. Font/source qualification stays with the
/// caller's actual text bindings, not with an equal-size or equal-text picture.
final class ForumBodyTextPictureLease extends ForumBodyNativeParagraphLease {
  ForumBodyTextPictureLease._(super.owner, super.entry, this.input) : super._();
  final ForumBodyTextPictureInput input;
  void paint(Canvas canvas, Offset offset) {
    if (!isActive) throw StateError('Text picture lease is retired');
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    final layout = _entry.layout as _TextPictureLayout;
    if (layout.isDisposed) throw StateError('Text picture is disposed');
    canvas.save();
    try {
      canvas.translate(offset.dx, offset.dy);
      canvas.drawPicture(layout.picture);
    } finally {
      canvas.restore();
    }
  }
}

enum _TextPicturePhase {
  dependencies,
  probe,
  lookup,
  record,
  ready,
  transferred,
  closed,
}

/// Records bounded commands outside visible paint. Dependencies are qualified
/// current same-owner text/mark leases; private aliases keep them pinned even if a
/// caller releases its handle. Cancellation drops aliases and unfinished work.
/// A caller-owned page prefix participates in the same probe and late-growth
/// classification without being aliased, retained by the result or released.
final class ForumBodyTextPicturePreparation {
  /// Immediately qualify and alias supplied resources. Callers may release
  /// their original handles as soon as this constructor returns.
  ForumBodyTextPicturePreparation({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextPictureInput input,
    required Iterable<ForumBodyTextLease> text,
    required void Function() ensureOwner,
    Iterable<ForumBodyEmphasisMarkLease> marks = const [],
    Iterable<ForumBodyParagraphRowView> paragraphRows = const [],
    Iterable<ForumBodyInlinePaintRowView> inlineRows = const [],
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : this._(
         cache: cache,
         input: input,
         text: text,
         ensureOwner: ensureOwner,
         marks: marks,
         paragraphRows: paragraphRows,
         inlineRows: inlineRows,
         additionalOwnedLeases: additionalOwnedLeases,
         cooperative: false,
       );

  /// Index/adopt dependencies during [advance], rather than draining the whole
  /// scene in the constructor. Keep the supplied iterables and caller leases
  /// valid until [dependenciesReady]; after that private aliases pin the inputs.
  /// This changes no native recording, ownership or budget qualification.
  ForumBodyTextPicturePreparation.cooperative({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextPictureInput input,
    required Iterable<ForumBodyTextLease> text,
    required void Function() ensureOwner,
    Iterable<ForumBodyEmphasisMarkLease> marks = const [],
    Iterable<ForumBodyParagraphRowView> paragraphRows = const [],
    Iterable<ForumBodyInlinePaintRowView> inlineRows = const [],
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : this._(
         cache: cache,
         input: input,
         text: text,
         ensureOwner: ensureOwner,
         marks: marks,
         paragraphRows: paragraphRows,
         inlineRows: inlineRows,
         additionalOwnedLeases: additionalOwnedLeases,
         cooperative: true,
       );

  ForumBodyTextPicturePreparation._({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextPictureInput input,
    required Iterable<ForumBodyTextLease> text,
    required void Function() ensureOwner,
    required Iterable<ForumBodyEmphasisMarkLease> marks,
    required Iterable<ForumBodyParagraphRowView> paragraphRows,
    required Iterable<ForumBodyInlinePaintRowView> inlineRows,
    required Iterable<ForumBodyNativeParagraphLease> Function()?
    additionalOwnedLeases,
    required bool cooperative,
  }) : _input = input,
       _cache = cache,
       _ensureOwner = ensureOwner,
       _additionalOwned = additionalOwnedLeases {
    try {
      _guard();
      _prefixStarted = additionalOwnedLeases == null;
      _assembly = _TextPictureDependencyWork(
        cache: cache,
        input: input,
        text: text,
        marks: marks,
        rows: paragraphRows,
        inlineRows: inlineRows,
        ensureOwner: _guard,
      );
      if (!cooperative) {
        final work = _assembly!;
        while (!work.isReady) {
          work.advance();
        }
        _completeDependencies();
      }
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyTextPictureInput? _input;
  ForumBodyTextPictureInput get input =>
      _input ?? (throw StateError('Text picture preparation is retired'));
  ForumBodyParagraphCache? _cache;
  void Function()? _ensureOwner;
  Iterable<ForumBodyNativeParagraphLease> Function()? _additionalOwned;
  Iterator<ForumBodyNativeParagraphLease>? _prefix;
  bool _prefixStarted = false;
  _TextPictureDependencyWork? _assembly;
  _TextPictureDependencies? _binding;
  Map<_TextPictureDependency, ForumBodyNativeParagraphLease> get _resources =>
      _binding?.resources ?? const {};
  Map<_TextPictureDependency, ForumBodyParagraphRowView> get _rowViews =>
      _binding?.rows ?? const {};
  Map<_TextPictureDependency, ForumBodyInlinePaintRowView>
  get _inlineRowViews => _binding?.inlineRows ?? const {};
  List<ForumBodyNativeParagraphLease> get _dependencies =>
      _binding?.leases ?? _assembly?.leases ?? const [];

  /// All dependency inputs have transferred to private aliases. The caller's
  /// borrowed handles may now be released; taking/closing this work retires it.
  bool get dependenciesReady => _binding != null;
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyTextPictureLease? _pending;
  ui.PictureRecorder? _recorder;
  Canvas? _canvas;
  var _phase = _TextPicturePhase.dependencies;
  var _index = 0;
  var _blockedAt = -1;
  var _operating = false;
  bool get isReady => _phase == _TextPicturePhase.ready;
  bool get cacheMiss => _miss;
  bool _miss = false;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ..._dependencies,
    ?_pending,
  ];

  ({int partsPrepared, int picturesRecorded, bool waitingForLayoutBudget})
  advance({int maxParts = 32, bool cachedOnly = false}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Text picture preparation is reentrant');
    _operating = true;
    var used = 0, recorded = 0;
    try {
      _guard();
      if (isReady) {
        return (
          partsPrepared: 0,
          picturesRecorded: 0,
          waitingForLayoutBudget: false,
        );
      }
      if (_blockedAt == _cache!.budgetRevision) {
        return (
          partsPrepared: 0,
          picturesRecorded: 0,
          waitingForLayoutBudget: true,
        );
      }
      _miss = false;
      while (used < maxParts && !isReady) {
        _guard();
        final cache = _cache!;
        final rejectedAt = cache.budgetRevision;
        try {
          switch (_phase) {
            case _TextPicturePhase.dependencies:
              final work = _assembly!;
              work.advance();
              if (work.isReady) _completeDependencies();
            case _TextPicturePhase.probe:
              if (!_prefixStarted) {
                final prefix = _additionalOwned?.call() ?? const [];
                _guard();
                _prefix = prefix.iterator;
                _prefixStarted = true;
              } else if (_prefix != null) {
                final hasNext = _prefix!.moveNext();
                _guard();
                if (hasNext) {
                  _probe!.includeLease(_prefix!.current);
                } else {
                  _prefix = null;
                }
              } else if (_index < _dependencies.length) {
                _probe!.includeLease(_dependencies[_index++]);
              } else {
                _probe!.includeTextPicture(input);
                _probe!.close();
                _probe = null;
                _index = 0;
                _phase = _TextPicturePhase.lookup;
              }
            case _TextPicturePhase.lookup:
              final found = cache.tryAcquireTextPicture(input);
              try {
                _guard();
              } catch (_) {
                found?.release();
                rethrow;
              }
              if (found != null) {
                _pending = found;
                _phase = _TextPicturePhase.ready;
              } else if (cachedOnly) {
                _miss = true;
                return (
                  partsPrepared: used + 1,
                  picturesRecorded: 0,
                  waitingForLayoutBudget: false,
                );
              } else {
                // Avoid allocating a display list when known external pins
                // already prevent the scene's minimum admission.
                cache._makeRoom(input.estimatedBytes, newEntry: true);
                _guard();
                _recorder = ui.PictureRecorder();
                _canvas = Canvas(_recorder!);
                _phase = _TextPicturePhase.record;
              }
            case _TextPicturePhase.record:
              if (cachedOnly) {
                _miss = true;
                return (
                  partsPrepared: used,
                  picturesRecorded: 0,
                  waitingForLayoutBudget: false,
                );
              }
              if (_index < input.commands.length) {
                final command = input.commands[_index++];
                final canvas = _canvas!;
                final fitted = command.fitScale != 1;
                final saved = fitted || command._translation != null;
                if (saved) {
                  canvas.save();
                }
                var translation = command._translation;
                while (translation != null) {
                  canvas.translate(
                    translation.offset.dx,
                    translation.offset.dy,
                  );
                  translation = translation.inner;
                }
                if (fitted) {
                  canvas.translate(command.offset.dx, command.offset.dy);
                  canvas.scale(command.fitScale, command.fitScale);
                }
                try {
                  final offset = fitted ? Offset.zero : command.offset;
                  final row = _rowViews[command._dependency];
                  final inlineRow = _inlineRowViews[command._dependency];
                  if (inlineRow != null) {
                    inlineRow.paint(canvas, offset);
                  } else if (row != null) {
                    final physical = command.physicalLine;
                    if (physical == null) {
                      row.paint(canvas, offset);
                    } else {
                      row.paintPhysicalLine(canvas, offset, physical);
                    }
                  } else {
                    switch (_resources[command._dependency]!) {
                      case ForumBodyTextLease resource:
                        resource.layout.paint(canvas, offset);
                      case ForumBodyEmphasisMarkLease resource:
                        resource.layout.paint(canvas, offset);
                      default:
                        throw StateError('Unsupported text picture resource');
                    }
                  }
                } finally {
                  if (saved) canvas.restore();
                }
              } else {
                final recorder = _recorder!;
                _recorder = null;
                _canvas = null;
                final ticket = _TextPictureTicket(recorder.endRecording());
                recorded++;
                try {
                  _guard();
                  final adopted = cache._adoptTextPicture(
                    input,
                    ticket,
                    () =>
                        _phase == _TextPicturePhase.record &&
                        identical(_cache, cache),
                  );
                  try {
                    _guard();
                  } catch (_) {
                    adopted.release();
                    rethrow;
                  }
                  _pending = adopted;
                } finally {
                  ticket.close();
                }
                _phase = _TextPicturePhase.ready;
              }
            case _TextPicturePhase.ready:
            case _TextPicturePhase.transferred:
            case _TextPicturePhase.closed:
              throw StateError('Text picture preparation is retired');
          }
          used++;
          _guard();
        } on ForumBodyParagraphBudgetException catch (error) {
          _guard();
          if (error.failure != ForumBodyParagraphBudgetFailure.pinned) rethrow;
          final additional = _additionalOwned?.call() ?? const [];
          _guard();
          if (!cache.isBlockedByExternalPins(error, [
            ...nativeLeases,
            ...additional,
          ])) {
            throw ForumBodyParagraphBudgetException(
              ForumBodyParagraphBudgetFailure.content,
              requiredEstimatedBytes: error.requiredEstimatedBytes,
              requiredAdditionalEntries: error.requiredAdditionalEntries,
            );
          }
          _guard();
          _discardRecording();
          _phase = _TextPicturePhase.lookup;
          _index = 0;
          _blockedAt = rejectedAt;
          return (
            partsPrepared: used + 1,
            picturesRecorded: recorded,
            waitingForLayoutBudget: cache.budgetRevision == rejectedAt,
          );
        }
      }
      return (
        partsPrepared: used,
        picturesRecorded: recorded,
        waitingForLayoutBudget: false,
      );
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyTextPictureLease takeLease() {
    if (_operating) throw StateError('Text picture preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Text picture preparation is incomplete');
      final result = _pending!;
      _pending = null;
      _phase = _TextPicturePhase.transferred;
      try {
        _dropOwner();
      } catch (_) {
        result.release();
        rethrow;
      }
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _TextPicturePhase.closed ||
        _phase == _TextPicturePhase.transferred) {
      throw StateError('Text picture preparation is retired');
    }
    _ensureOwner!();
    if (_cache == null ||
        _cache!.isClosed ||
        (_binding?.leases.any((lease) => !_cache!.ownsLease(lease)) ?? false) ||
        (_pending != null && !_cache!.ownsLease(_pending!))) {
      throw StateError('Text picture owner is retired');
    }
  }

  void _discardRecording() {
    final recorder = _recorder;
    _recorder = null;
    _canvas = null;
    if (recorder != null) recorder.endRecording().dispose();
  }

  void _completeDependencies() {
    final work = _assembly!;
    _binding = work.takeDependencies();
    _assembly = null;
    work.close();
    _probe = _cache!.createBudgetProbe();
    _phase = _TextPicturePhase.probe;
    _guard();
  }

  void _dropOwner() {
    _probe?.close();
    _probe = null;
    final assembly = _assembly, binding = _binding;
    _assembly = null;
    _binding = null;
    _ensureOwner = null;
    _additionalOwned = null;
    _prefix = null;
    _cache = null;
    _input = null;
    Object? failure;
    StackTrace? stack;
    try {
      _discardRecording();
    } catch (error, trace) {
      failure = error;
      stack = trace;
    }
    for (final close in <void Function()>[
      if (assembly != null) assembly.close,
      if (binding != null) binding.close,
    ]) {
      try {
        close();
      } catch (error, trace) {
        failure ??= error;
        stack ??= trace;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }

  void close() {
    if (_phase == _TextPicturePhase.closed ||
        _phase == _TextPicturePhase.transferred) {
      return;
    }
    _phase = _TextPicturePhase.closed;
    final pending = _pending;
    _pending = null;
    try {
      pending?.release();
    } finally {
      _dropOwner();
    }
  }
}

int _textPictureInputBytes(_NativeInputIdentity input) {
  final key = input._key;
  if (key is _EmphasisMarkKey) return key.input.estimatedInputBytes + 16;
  // Both admitted key kinds come from ParagraphContent's flat native spans.
  // Count those retained children without rescanning source text or run trees.
  int spans(TextSpan root) => 1 + (root.children?.length ?? 0);
  if (key is _LayoutKey) {
    return 4096 +
        key.projection.text.length * 96 +
        spans(key.span) * 256 +
        key.isolationBytes +
        key.scales.length * 16;
  }
  if (key is _InlineLayoutKey) {
    // Whole input metadata survives with the picture after fonts are evicted.
    // Count original display/projection plus native slot/indent/span tables;
    // selecting one physical row never reduces the retained parent metadata.
    return 4096 +
        key.projection.display.text.length * 96 +
        key.projection.engineText.length * 2 +
        spans(key.span) * 256 +
        key.projection.atoms.length * 160 +
        key.dimensions.length * 48 +
        key.scales.length * 16 +
        key.isolationBytes +
        key.indentBytes;
  }
  final band = key as ForumBodyTextBandCacheKey;
  return 4096 +
      band.projections.fold<int>(
        0,
        (sum, value) => sum + value.text.length * 96,
      ) +
      band.spans.fold<int>(0, (sum, value) => sum + spans(value) * 256) +
      band.projections.length * 256 +
      band.scales.length * 16;
}

final class _TextPictureTicket {
  _TextPictureTicket(this._picture);
  ui.Picture? _picture;
  int get bytes => _picture!.approximateBytesUsed;
  ui.Picture take() {
    final value = _picture!;
    _picture = null;
    return value;
  }

  void close() {
    _picture?.dispose();
    _picture = null;
  }
}

final class _TextPictureLayout implements ForumBodyNativeParagraphLayout {
  _TextPictureLayout(this.picture);
  final ui.Picture picture;
  @override
  int get lineCount => 0;
  @override
  bool get isDisposed => _disposed;
  bool _disposed = false;
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    picture.dispose();
  }
}
