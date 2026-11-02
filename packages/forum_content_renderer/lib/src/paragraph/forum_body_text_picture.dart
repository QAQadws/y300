part of 'forum_body_paragraph_cache.dart';

typedef _TextPictureDependency = ({Object identity, int? bandChildIndex});

final class ForumBodyTextPictureCommand {
  const ForumBodyTextPictureCommand({
    required this.nativeInputIdentity,
    required this.offset,
    this.bandChildIndex,
  });
  factory ForumBodyTextPictureCommand.fromText(
    ForumBodyTextLease text,
    Offset offset,
  ) => ForumBodyTextPictureCommand(
    nativeInputIdentity: text.nativeInputIdentity,
    offset: offset,
    bandChildIndex: text is ForumBodyTextBandChildLease
        ? text.childIndex
        : null,
  );
  final Object nativeInputIdentity;
  final Offset offset;
  // Several source-bound views share a band key but paint different strips.
  final int? bandChildIndex;
  _TextPictureDependency get _dependency =>
      (identity: nativeInputIdentity, bandChildIndex: bandChildIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumBodyTextPictureCommand &&
          nativeInputIdentity == other.nativeInputIdentity &&
          offset == other.offset &&
          bandChildIndex == other.bandChildIndex;
  @override
  int get hashCode => Object.hash(nativeInputIdentity, offset, bandChildIndex);
}

/// A finite draw list over actual opaque native inputs. No source authority,
/// lease, painter, owner or callback is retained by this immutable cache key.
final class ForumBodyTextPictureInput {
  ForumBodyTextPictureInput._(this.commands, this.estimatedInputBytes);
  factory ForumBodyTextPictureInput({
    required List<ForumBodyTextPictureCommand> commands,
    int maxCommands = 512,
  }) {
    if (maxCommands <= 0 || commands.isEmpty || commands.length > maxCommands) {
      throw ArgumentError('Invalid text picture command budget');
    }
    final frozen = List<ForumBodyTextPictureCommand>.unmodifiable(commands);
    final inputs = <_NativeInputIdentity>{};
    for (final command in frozen) {
      final identity = command.nativeInputIdentity;
      if (identity is! _NativeInputIdentity ||
          !command.offset.dx.isFinite ||
          !command.offset.dy.isFinite ||
          command.offset.dx.abs() > 32768 ||
          command.offset.dy.abs() > 32768) {
        throw ArgumentError('Invalid native text picture command');
      }
      final key = identity._key;
      if (key is ForumBodyTextBandCacheKey) {
        final child = command.bandChildIndex;
        if (child == null || child < 0 || child >= key.projections.length) {
          throw ArgumentError('Invalid native band picture selector');
        }
      } else if (key is! _LayoutKey || command.bandChildIndex != null) {
        throw ArgumentError('Text picture requires an actual text input');
      }
      inputs.add(identity);
    }
    return ForumBodyTextPictureInput._(
      frozen,
      4096 +
          frozen.length * 128 +
          inputs.fold(0, (sum, value) => sum + _textPictureInputBytes(value)),
    );
  }
  final List<ForumBodyTextPictureCommand> commands;
  static const revision = 1;

  /// Conservative display-list admission, not font/native/GPU memory. Actual
  /// engine picture bytes can grow this cost before the owner publishes it.
  final int estimatedInputBytes;
  int get estimatedPictureBytes => 4096 + commands.length * 256;
  // The pure key keeps text/projection metadata after font entries are evicted.
  // Charge that retention too, once per resource (not once per band child).
  int get estimatedBytes => estimatedInputBytes + estimatedPictureBytes;
  late final int _hash = Object.hash(revision, Object.hashAll(commands));
  @override
  int get hashCode => _hash;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumBodyTextPictureInput &&
          listEquals(commands, other.commands);
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

enum _TextPicturePhase { probe, lookup, record, ready, transferred, closed }

/// Records bounded commands outside visible paint. Dependencies are qualified
/// current same-owner text leases; private aliases keep them pinned even if a
/// caller releases its handle. Cancellation drops aliases and unfinished work.
final class ForumBodyTextPicturePreparation {
  ForumBodyTextPicturePreparation({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextPictureInput input,
    required Iterable<ForumBodyTextLease> text,
    required void Function() ensureOwner,
  }) : _input = input,
       _cache = cache,
       _ensureOwner = ensureOwner {
    try {
      _guard();
      final wanted = {
        for (final command in input.commands) command._dependency,
      };
      // Caller input is bounded by the scene, including otherwise unused text.
      var inspected = 0;
      for (final lease in text) {
        if (++inspected > input.commands.length) {
          throw ArgumentError('Excess text picture dependencies');
        }
        _guard();
        if (!cache.ownsLease(lease)) {
          throw StateError('Foreign text picture dependency');
        }
        final key = (
          identity: lease.nativeInputIdentity,
          bandChildIndex: lease is ForumBodyTextBandChildLease
              ? lease.childIndex
              : null,
        );
        if (!wanted.contains(key)) {
          throw ArgumentError('Unrequested text picture dependency');
        }
        if (!_text.containsKey(key)) _text[key] = cache._aliasTextLease(lease);
      }
      if (_text.length != wanted.length) {
        throw ArgumentError('Missing text picture dependency');
      }
      _dependencies = _text.values.toList(growable: false);
      _probe = cache.createBudgetProbe();
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
  final _text = <_TextPictureDependency, ForumBodyTextLease>{};
  List<ForumBodyTextLease> _dependencies = const [];
  ForumBodyParagraphBudgetProbe? _probe;
  ForumBodyTextPictureLease? _pending;
  ui.PictureRecorder? _recorder;
  Canvas? _canvas;
  var _phase = _TextPicturePhase.probe;
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
            case _TextPicturePhase.probe:
              if (_index < _dependencies.length) {
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
                _text[command._dependency]!.layout.paint(
                  _canvas!,
                  command.offset,
                );
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
          if (error.failure != ForumBodyParagraphBudgetFailure.pinned ||
              !cache.isBlockedByExternalPins(error, nativeLeases)) {
            throw ForumBodyParagraphBudgetException(
              ForumBodyParagraphBudgetFailure.content,
              requiredEstimatedBytes: error.requiredEstimatedBytes,
              requiredAdditionalEntries: error.requiredAdditionalEntries,
            );
          }
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
        _dependencies.any((lease) => !_cache!.ownsLease(lease)) ||
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

  void _dropOwner() {
    _probe?.close();
    _probe = null;
    final text = _text.values.toList(growable: false);
    _text.clear();
    _dependencies = const [];
    _ensureOwner = null;
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
    for (final lease in text) {
      try {
        lease.release();
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
  // Both admitted key kinds come from ParagraphContent's flat native spans.
  // Count those retained children without rescanning source text or run trees.
  int spans(TextSpan root) => 1 + (root.children?.length ?? 0);
  if (key is _LayoutKey) {
    return 4096 +
        key.projection.text.length * 96 +
        spans(key.span) * 256 +
        key.scales.length * 16;
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
