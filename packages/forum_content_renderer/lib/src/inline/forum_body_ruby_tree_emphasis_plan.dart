part of 'forum_body_emphasis_line_layout.dart';

/// Glyphs retain their actual tree/opaque-parent paint path; all real emphasis
/// markers share this one scene. Neither a scene key nor an equal numeric frame
/// qualifies the original source or acquires a visible resource.
final class ForumBodyRubyTreeEmphasisPlan {
  ForumBodyRubyTreeEmphasisPlan._(this.placement, this.markerPictureInput)
    : frame = placement.input.input.geometry.metrics.root.font.encloseBounds(
        childBounds: placement.bounds,
        childBaseline:
            placement.input.input.geometry.metrics.box.alphabeticBaseline,
      );
  final ForumBodyRubyTreeEmphasisPlacement placement;

  /// Null for a real zero-target tree: no placeholder marker/source is invented.
  final ForumBodyTextPictureInput? markerPictureInput;
  final ForumBodyRubyAtomFrame frame;

  /// Actual retained handles, distinct from deduplicated native budget keys.
  /// Marker font leases are temporary; the glyph binding and one scene remain.
  int get retainedHandleCount =>
      placement.input.input.geometry.metrics.glyphHandleCount +
      (markerPictureInput == null ? 0 : 1);

  /// The complete native acquisition/scene prefix. Shared band/base keys dedup
  /// in the existing probe; old isolated line scenes and transient empty-RT font
  /// measurements are excluded. Opaque inline dependencies remain in the glyph
  /// tree's actual footprint, not reconstructed from its source metadata.
  Iterable<ForumBodyNativeBudgetSlot> get nativeBudgetFootprint sync* {
    final metrics = placement.input.input;
    yield* metrics.geometry.metrics.nativeGlyphBudgetFootprint;
    for (final source in metrics.sources) {
      yield* source.line.nativeFootprint;
    }
    if (markerPictureInput case final input?) {
      yield (
        request: ForumBodyTextPictureBudgetInput(input),
        width: metrics.geometry.metrics.input.maxWidth,
        minimumLineCount: 0,
      );
    }
  }
}

enum _TreeEmphasisPlanPhase { commands, publish, ready, transferred, closed }

/// Compose one actual native marker command per original unit, preserving its
/// independent baseline translation and local fitted font transform. Uses the
/// existing bounded command writer and performs no native/cache work.
final class ForumBodyRubyTreeEmphasisPlanPreparation {
  ForumBodyRubyTreeEmphasisPlanPreparation({
    required ForumBodyRubyTreeEmphasisPlacement placement,
    required void Function() ensureOwner,
    int maxCommands = ForumBodyTextPictureInput.maximumCommands,
  }) : _placement = placement,
       _ensureOwner = ensureOwner {
    if (maxCommands <= 0 ||
        maxCommands > ForumBodyTextPictureInput.maximumCommands) {
      throw ArgumentError.value(maxCommands, 'maxCommands');
    }
    if (placement.marks.isNotEmpty) {
      _composition = ForumBodyTextPictureInputComposition(
        inputs: _inputs(placement),
        ensureOwner: _guard,
        maxInputs: maxCommands,
        maxCommands: maxCommands,
      );
    }
  }
  ForumBodyRubyTreeEmphasisPlacement? _placement;
  void Function()? _ensureOwner;
  ForumBodyTextPictureInputComposition? _composition;
  ForumBodyTextPictureInput? _picture;
  ForumBodyRubyTreeEmphasisPlan? _result;
  var _phase = _TreeEmphasisPlanPhase.commands;
  bool _operating = false;
  bool get isReady => _phase == _TreeEmphasisPlanPhase.ready;

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    return _operate(() {
      _guard();
      var parts = 0;
      while (!isReady && parts < maxParts) {
        switch (_phase) {
          case _TreeEmphasisPlanPhase.commands:
            final work = _composition;
            if (work == null) {
              parts++;
              _phase = _TreeEmphasisPlanPhase.publish;
            } else {
              parts += work.advance(maxParts: maxParts - parts);
              _guard();
              if (work.isReady) {
                _picture = work.takeInput();
                _composition = null;
                work.close();
                _phase = _TreeEmphasisPlanPhase.publish;
              }
            }
          case _TreeEmphasisPlanPhase.publish:
            _result = ForumBodyRubyTreeEmphasisPlan._(_placement!, _picture);
            _picture = null;
            _phase = _TreeEmphasisPlanPhase.ready;
            parts++;
          case _TreeEmphasisPlanPhase.ready:
          case _TreeEmphasisPlanPhase.transferred:
          case _TreeEmphasisPlanPhase.closed:
            throw StateError('Ruby tree emphasis plan is retired');
        }
        _guard();
      }
      return parts;
    });
  }

  ForumBodyRubyTreeEmphasisPlan takePlan() => _operate(() {
    _guard();
    if (!isReady) {
      throw StateError('Ruby tree emphasis plan is incomplete');
    }
    final result = _result!;
    _result = null;
    _phase = _TreeEmphasisPlanPhase.transferred;
    _drop();
    return result;
  });
  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Ruby tree emphasis plan is reentrant');
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
    if (_phase == _TreeEmphasisPlanPhase.closed ||
        _phase == _TreeEmphasisPlanPhase.transferred) {
      throw StateError('Ruby tree emphasis plan is retired');
    }
    _ensureOwner!();
    if (_phase == _TreeEmphasisPlanPhase.closed) {
      throw StateError('Ruby tree emphasis plan owner is retired');
    }
  }

  void _drop() {
    _composition?.close();
    _composition = null;
    _placement = null;
    _ensureOwner = null;
    _picture = null;
  }

  void close() {
    if (_phase == _TreeEmphasisPlanPhase.closed ||
        _phase == _TreeEmphasisPlanPhase.transferred) {
      return;
    }
    _phase = _TreeEmphasisPlanPhase.closed;
    _result = null;
    _drop();
  }

  static Iterable<ForumBodyPositionedTextPictureInput> _inputs(
    ForumBodyRubyTreeEmphasisPlacement placement,
  ) sync* {
    for (final placed in placement.marks) {
      final line = placed.source.line, mark = placed.mark;
      yield (
        input: ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity:
                  line._markKeys[line._unitMarks[mark.unitIndex]],
              offset: placed.fontOffset,
              fitScale: mark.fitScale,
            ).translated(placed.baselineOrigin),
          ],
        ),
        offset: Offset.zero,
      );
    }
  }
}
