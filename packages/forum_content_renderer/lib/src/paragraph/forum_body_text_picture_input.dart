part of 'forum_body_paragraph_cache.dart';

/// A finite draw list over actual opaque native inputs. No source authority,
/// lease, painter, owner or callback is retained by this immutable cache key.
final class ForumBodyTextPictureInput {
  ForumBodyTextPictureInput._(
    this.commands,
    this.estimatedInputBytes,
    this.estimatedPictureBytes,
    this._hash,
  ) : _keyRevision = revision;
  factory ForumBodyTextPictureInput({
    required List<ForumBodyTextPictureCommand> commands,
    int maxCommands = 512,
  }) {
    final writer = _TextPictureInputWriter(maxCommands);
    try {
      for (final command in commands) {
        writer.add(command);
      }
      return writer.takeInput();
    } finally {
      writer.close();
    }
  }
  static const revision = 8;
  static const maximumCommands = 32768;
  final List<ForumBodyTextPictureCommand> commands;
  final int _keyRevision, _hash;

  /// Conservative display-list admission, not native/GPU memory. Recording
  /// still rechecks actual engine picture growth before publication.
  final int estimatedInputBytes;
  final int estimatedPictureBytes;
  int get estimatedBytes => estimatedInputBytes + estimatedPictureBytes;
  @override
  int get hashCode => _hash;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumBodyTextPictureInput &&
          _keyRevision == other._keyRevision &&
          listEquals(commands, other.commands);
}

typedef ForumBodyPositionedTextPictureInput = ({
  ForumBodyTextPictureInput input,
  Offset offset,
});

enum _InputCompositionState { active, ready, transferred, closed }

/// Pure composition of existing command inputs. One part reads one source,
/// copies/translates one command, crosses a source boundary, or publishes.
/// Metadata accounting and hashing accumulate with the copies; finalization
/// never clones or hashes the entire combined list in a single work unit.
final class ForumBodyTextPictureInputComposition {
  ForumBodyTextPictureInputComposition({
    required Iterable<ForumBodyPositionedTextPictureInput> inputs,
    required void Function() ensureOwner,
    this.maxInputs = 512,
    int maxCommands = 8192,
  }) : _inputs = inputs,
       _ensureOwner = ensureOwner {
    if (maxInputs <= 0) throw ArgumentError.value(maxInputs);
    _writer = _TextPictureInputWriter(maxCommands);
  }
  final int maxInputs;
  Iterable<ForumBodyPositionedTextPictureInput>? _inputs;
  Iterator<ForumBodyPositionedTextPictureInput>? _iterator;
  ForumBodyPositionedTextPictureInput? _current;
  void Function()? _ensureOwner;
  _TextPictureInputWriter? _writer;
  ForumBodyTextPictureInput? _result;
  var _state = _InputCompositionState.active;
  int _source = 0, _command = 0;
  bool _operating = false;
  bool get isReady => _state == _InputCompositionState.ready;
  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Picture input composition is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final current = _current;
        if (current == null) {
          if (_iterator == null) {
            _iterator = _inputs!.iterator;
            _inputs = null;
            _guard();
          } else {
            final next = _iterator!.moveNext();
            _guard();
            if (next) {
              if (_source++ >= maxInputs) {
                throw ArgumentError('Excess picture inputs');
              }
              final item = _iterator!.current;
              _guard();
              if (!item.offset.dx.isFinite || !item.offset.dy.isFinite) {
                throw ArgumentError.value(item.offset);
              }
              _current = item;
              _command = 0;
            } else {
              _result = _writer!.takeInput();
              _writer = null;
              _iterator = null;
              _state = _InputCompositionState.ready;
            }
          }
        } else if (_command < current.input.commands.length) {
          final original = current.input.commands[_command++];
          _writer!.add(original.translated(current.offset));
        } else {
          _current = null;
        }
        used++;
        _guard();
      }
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyTextPictureInput takeInput() {
    if (_operating) throw StateError('Picture input composition is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Picture input composition is incomplete');
      final result = _result!;
      _state = _InputCompositionState.transferred;
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
    if (_state == _InputCompositionState.closed ||
        _state == _InputCompositionState.transferred) {
      throw StateError('Picture input composition is retired');
    }
    _ensureOwner!();
    if (_state == _InputCompositionState.closed) {
      throw StateError('Picture input owner is retired');
    }
  }

  void _drop() {
    _inputs = null;
    _iterator = null;
    _current = null;
    _ensureOwner = null;
    _writer?.close();
    _writer = null;
    _result = null;
  }

  void close() {
    if (_state == _InputCompositionState.closed ||
        _state == _InputCompositionState.transferred) {
      return;
    }
    _state = _InputCompositionState.closed;
    _drop();
  }
}

final class _TextPictureInputWriter {
  _TextPictureInputWriter(this.maxCommands) {
    if (maxCommands <= 0 ||
        maxCommands > ForumBodyTextPictureInput.maximumCommands) {
      throw ArgumentError.value(maxCommands, 'maxCommands');
    }
  }
  final int maxCommands;
  List<ForumBodyTextPictureCommand>? _commands = [];
  final _inputs = <_NativeInputIdentity>{};
  final _hash = _TextPictureCommandHash();
  int _inputBytes = 4096;
  int _pictureBytes = 4096;
  void add(ForumBodyTextPictureCommand command) {
    final commands =
        _commands ?? (throw StateError('Picture input writer is retired'));
    if (commands.length >= maxCommands) {
      throw ArgumentError('Excess picture commands');
    }
    _validateTextPictureCommand(command);
    final identity = command.nativeInputIdentity as _NativeInputIdentity;
    commands.add(command);
    _inputBytes +=
        128 +
        (command.paragraphRow == null ? 0 : 64) +
        (command.physicalLine == null ? 0 : 192) +
        command.translationDepth * 64;
    _pictureBytes += 256 + command.translationDepth * 64;
    if (_inputs.add(identity)) _inputBytes += _textPictureInputBytes(identity);
    _hash.add(command);
  }

  ForumBodyTextPictureInput takeInput() {
    final commands =
        _commands ?? (throw StateError('Picture input writer is retired'));
    if (commands.isEmpty) throw ArgumentError('A text picture needs commands');
    final result = ForumBodyTextPictureInput._(
      UnmodifiableListView(commands),
      _inputBytes,
      _pictureBytes,
      _hash.finish(),
    );
    close();
    return result;
  }

  void close() {
    _commands = null;
    _inputs.clear();
    _hash.close();
  }
}

// Fixed chunks keep hashing cooperative without copying Dart's private hash
// implementation. Both direct construction and composition use this contract.
final class _TextPictureCommandHash {
  List<ForumBodyTextPictureCommand> _chunk = [];
  final _chunks = <int>[];
  void add(ForumBodyTextPictureCommand command) {
    _chunk.add(command);
    if (_chunk.length == 128) {
      _chunks.add(Object.hashAll(_chunk));
      _chunk = [];
    }
  }

  int finish() {
    if (_chunk.isNotEmpty) _chunks.add(Object.hashAll(_chunk));
    return Object.hash(
      ForumBodyTextPictureInput.revision,
      Object.hashAll(_chunks),
    );
  }

  void close() {
    _chunk = [];
    _chunks.clear();
  }
}

void _validateTextPictureCommand(ForumBodyTextPictureCommand command) {
  final identity = command.nativeInputIdentity;
  if (identity is! _NativeInputIdentity ||
      !command.offset.dx.isFinite ||
      !command.offset.dy.isFinite ||
      command.offset.dx.abs() > 32768 ||
      command.offset.dy.abs() > 32768 ||
      command.sceneOffset.dx.abs() > 32768 ||
      command.sceneOffset.dy.abs() > 32768) {
    throw ArgumentError('Invalid native text picture command');
  }
  if (!command.fitScale.isFinite ||
      command.fitScale <= 0 ||
      command.fitScale > 1) {
    throw ArgumentError('Invalid native text picture fitting scale');
  }
  final key = identity._key;
  if (key is ForumBodyTextBandCacheKey) {
    final child = command.bandChildIndex;
    if (child == null ||
        child < 0 ||
        child >= key.projections.length ||
        command.paragraphRow != null) {
      throw ArgumentError('Invalid native band picture selector');
    }
  } else if ((key is! _LayoutKey && key is! _EmphasisMarkKey) ||
      command.bandChildIndex != null) {
    throw ArgumentError('Text picture requires an actual text input');
  }
  final row = command.paragraphRow, physical = command.physicalLine;
  if (physical != null &&
      (row == null ||
          !physical.matchesInput(nativeInputIdentity: identity, group: row))) {
    throw ArgumentError('Invalid physical line input');
  }
  for (final selected in [?row, ?physical?.selector]) {
    if (key is! _LayoutKey ||
        key.rowIsolationPitch == null ||
        selected.startLine < 0 ||
        selected.endLine <= selected.startLine ||
        !selected.originY.isFinite ||
        !selected.clipTop.isFinite ||
        !selected.clipBottom.isFinite ||
        selected.clipBottom <= selected.clipTop ||
        selected.originY.abs() > 1048576 ||
        selected.clipTop.abs() > 1114112 ||
        selected.clipBottom.abs() > 1114112) {
      throw ArgumentError('Invalid native paragraph row selector');
    }
  }
}

// An immutable bounded transform chain keeps Canvas's actual nested float
// operations in the key. Equal sums alone do not prove identical native pixels.
final class _TextPictureTranslation {
  _TextPictureTranslation(this.offset, this.inner)
    : depth = (inner?.depth ?? 0) + 1,
      total = offset + (inner?.total ?? Offset.zero),
      _hash = Object.hash(offset, inner) {
    if (depth > ForumBodyTextPictureCommand.maximumTranslationDepth ||
        !offset.dx.isFinite ||
        !offset.dy.isFinite ||
        offset.dx.abs() > 32768 ||
        offset.dy.abs() > 32768 ||
        !total.dx.isFinite ||
        !total.dy.isFinite ||
        total.dx.abs() > 32768 ||
        total.dy.abs() > 32768) {
      throw ArgumentError('Invalid text picture translation');
    }
  }
  final Offset offset, total;
  final _TextPictureTranslation? inner;
  final int depth, _hash;
  @override
  int get hashCode => _hash;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TextPictureTranslation &&
          offset == other.offset &&
          inner == other.inner;
}
