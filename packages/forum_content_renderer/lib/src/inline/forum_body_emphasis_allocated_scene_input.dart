part of 'forum_body_emphasis_line_layout.dart';

/// Measured drawing input only. It can enter page admission without preparing
/// a picture, but never authorizes source use or skips current visible binding.
final class ForumBodyEmphasisAllocatedSceneInput {
  const ForumBodyEmphasisAllocatedSceneInput._(
    this.allocation,
    this.pictureInput,
  );
  final ForumBodyEmphasisRowAllocation allocation;
  final ForumBodyTextPictureInput pictureInput;
  void includeBudget(ForumBodyParagraphBudgetProbe probe) =>
      probe.includeTextPicture(pictureInput);
}

typedef ForumBodyEmphasisMeasuredPaintPhase = ({
  ForumBodyParagraphLease parent,
  ForumBodyParagraphLineFrames frames,
});

enum _SceneInputPhase { group, physical, verify, commands, ready, closed }

/// Borrows actual whole phase parents and their current frame tables. The host
/// can reuse these three tables across every complete group in a paragraph.
/// This worker neither acquires nor releases a caller handle, shapes or paints.
final class ForumBodyEmphasisAllocatedSceneInputPreparation {
  ForumBodyEmphasisAllocatedSceneInputPreparation({
    required ForumBodyEmphasisRowAllocation allocation,
    required ForumBodyParagraphLease source,
    required List<ForumBodyEmphasisMeasuredPaintPhase> phases,
    required void Function() ensureOwner,
  }) : _allocation = allocation,
       _source = source,
       _ensureOwner = ensureOwner {
    try {
      _guard();
      if (phases.length != 3 ||
          allocation.rows.isEmpty ||
          allocation.rows.length > 64 ||
          !identical(source.content, allocation.reference.content) ||
          source.nativeInputIdentity !=
              allocation.reference.isolatedInputIdentity) {
        ForumBodyEmphasisLinePreparation._mismatch();
      }
      _phases = List.unmodifiable(phases);
      final expected = [
        allocation.paintInput.background,
        allocation.paintInput.foreground,
        allocation.paintInput.decoration,
      ];
      for (var layer = 0; layer < 3; layer++) {
        final current = _phases[layer],
            parent = current.parent,
            frames = current.frames;
        if (!parent.matchesNativeInputs(
              content: expected[layer],
              width: allocation.width,
              textScaler: allocation.textScaler,
              rowIsolationPitch: allocation.reference.rowIsolationPitch,
            ) ||
            !identical(frames.content, parent.content) ||
            frames.nativeInputIdentity != parent.nativeInputIdentity ||
            !identical(frames.lines, parent.layout.lines) ||
            frames.nativeAlphabeticBaseline !=
                allocation.isolatedAlphabeticBaseline) {
          ForumBodyEmphasisLinePreparation._mismatch();
        }
        _verifyAllocatedParent(allocation, source, parent);
        _guard();
      }
    } catch (_) {
      close();
      rethrow;
    }
  }
  ForumBodyEmphasisRowAllocation? _allocation;
  ForumBodyParagraphLease? _source;
  List<ForumBodyEmphasisMeasuredPaintPhase> _phases = const [];
  void Function()? _ensureOwner;
  final _groups = <ForumBodyParagraphRowView>[];
  final _strips = <List<ForumBodyParagraphPhysicalLineSelector>>[];
  ForumBodyParagraphRowPreparation? _groupJob;
  ForumBodyParagraphPhysicalLinePreparation? _physicalJob;
  _AllocatedSceneCommands? _commands;
  ForumBodyEmphasisAllocatedSceneInput? _result;
  var _phase = _SceneInputPhase.group;
  int _layer = 0, _verify = 0;
  bool _operating = false;
  bool get isReady => _phase == _SceneInputPhase.ready;
  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Allocated scene input is reentrant');
    _operating = true;
    var used = 0;
    try {
      _guard();
      while (!isReady && used < maxParts) {
        final allocation = _allocation!, expected = allocation.source;
        switch (_phase) {
          case _SceneInputPhase.group:
            final current = _phases[_layer];
            _groupJob ??= ForumBodyParagraphRowPreparation(
              parent: current.parent,
              startLine: expected.selector.startLine,
              ensureOwner: _guard,
            );
            _groupJob!.advance(maxParts: 1);
            if (_groupJob!.isReady) {
              final metrics = _groupJob!.takeMetrics();
              _groupJob = null;
              if (metrics.selector != expected.selector ||
                  metrics.startUtf16 != expected.startUtf16 ||
                  metrics.endUtf16 != expected.endUtf16 ||
                  metrics.fontBounds != expected.fontBounds) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
              final group = ForumBodyParagraphRowView.bind(
                parent: current.parent,
                metrics: metrics,
                ensureOwner: _guard,
              );
              _groups.add(group);
              _physicalJob = ForumBodyParagraphPhysicalLinePreparation(
                group: group,
                frames: current.frames,
                ensureOwner: _guard,
              );
              _phase = _SceneInputPhase.physical;
            }
          case _SceneInputPhase.physical:
            _physicalJob!.advance(maxParts: 1);
            if (_physicalJob!.isReady) {
              _strips.add(_physicalJob!.takeSelectors());
              _physicalJob = null;
              if (_strips.last.length != allocation.rows.length) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
              _verify = 0;
              _phase = _SceneInputPhase.verify;
            }
          case _SceneInputPhase.verify:
            if (_verify < allocation.rows.length) {
              final index = _verify++,
                  actual = _strips.last[index],
                  wanted = allocation.rows[index].physicalLine;
              if (actual.selector != wanted.selector ||
                  actual.fontBounds != wanted.fontBounds ||
                  !_sameAllocatedPhaseLine(
                    _phases[_layer].frames.lines[actual.lineIndex],
                    allocation.reference.isolatedLines[actual.lineIndex],
                  )) {
                ForumBodyEmphasisLinePreparation._mismatch();
              }
            } else if (++_layer < 3) {
              _phase = _SceneInputPhase.group;
            } else {
              _commands = _AllocatedSceneCommands(
                allocation,
                _groups,
                _strips,
                _guard,
              );
              _phase = _SceneInputPhase.commands;
            }
          case _SceneInputPhase.commands:
            _commands!.advance();
            if (_commands!.isReady) {
              _result = ForumBodyEmphasisAllocatedSceneInput._(
                allocation,
                _commands!.takeInput(),
              );
              _commands = null;
              _phase = _SceneInputPhase.ready;
            }
          case _SceneInputPhase.ready:
          case _SceneInputPhase.closed:
            throw StateError('Allocated scene input is retired');
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

  ForumBodyEmphasisAllocatedSceneInput takeInput() {
    if (_operating) throw StateError('Allocated scene input is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Allocated scene input is incomplete');
      final result = _result!;
      close();
      return result;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _guard() {
    if (_phase == _SceneInputPhase.closed) {
      throw StateError('Allocated scene input is retired');
    }
    _ensureOwner!();
    if (_phase == _SceneInputPhase.closed ||
        _source?.isActive != true ||
        _phases.any((p) => !p.parent.hasSameActiveOwner(_source!))) {
      throw StateError('Allocated scene input owner is retired');
    }
  }

  void close() {
    _phase = _SceneInputPhase.closed;
    _groupJob?.close();
    _groupJob = null;
    _physicalJob?.close();
    _physicalJob = null;
    _commands?.close();
    _commands = null;
    _groups.clear();
    _strips.clear();
    _phases = const [];
    _allocation = null;
    _source = null;
    _ensureOwner = null;
    _result = null;
  }
}

// Shared by measured scene planning and visible scene verification.
final class _AllocatedSceneCommands {
  _AllocatedSceneCommands(
    this._allocation,
    this._groups,
    this._strips,
    this._guard,
  );
  ForumBodyEmphasisRowAllocation? _allocation;
  List<ForumBodyParagraphRowView>? _groups;
  List<List<ForumBodyParagraphPhysicalLineSelector>>? _strips;
  void Function()? _guard;
  List<ForumBodyTextPictureCommand> _commands = [];
  ForumBodyTextPictureInput? _input;
  int _row = 0, _layer = 0;
  bool get isReady => _input != null;
  void advance() {
    _guard!();
    final plan = _allocation!;
    if (_row < plan.rows.length) {
      final row = plan.rows[_row];
      if (_layer < 3) {
        final layer = _layer++, strip = _strips![layer][_row];
        _commands.add(
          ForumBodyTextPictureCommand.fromPhysicalLine(
            _groups![layer],
            strip,
            (layer == 1 ? row.glyphOffset : row.logicalOffset) +
                Offset(0, strip.selector.originY),
          ),
        );
      } else {
        _row++;
        _layer = 0;
      }
    } else {
      _input = ForumBodyTextPictureInput(commands: _commands, maxCommands: 192);
    }
    _guard!();
  }

  ForumBodyTextPictureInput takeInput() {
    _guard!();
    final result =
        _input ?? (throw StateError('Allocated commands are incomplete'));
    close();
    return result;
  }

  void close() {
    _allocation = null;
    _groups = null;
    _strips = null;
    _guard = null;
    _commands = [];
    _input = null;
  }
}

bool _sameAllocatedPhaseLine(
  ForumBodyParagraphLine a,
  ForumBodyParagraphLine b,
) =>
    a.startUtf16 == b.startUtf16 &&
    a.endUtf16 == b.endUtf16 &&
    a.coverageStartUtf16 == b.coverageStartUtf16 &&
    a.coverageEndUtf16 == b.coverageEndUtf16 &&
    a.engineStartUtf16 == b.engineStartUtf16 &&
    a.engineEndUtf16 == b.engineEndUtf16 &&
    a.engineCoverageStartUtf16 == b.engineCoverageStartUtf16 &&
    a.engineCoverageEndUtf16 == b.engineCoverageEndUtf16 &&
    a.unpaintedTrailingSpaceStartUtf16 == b.unpaintedTrailingSpaceStartUtf16 &&
    a.engineUnpaintedTrailingSpaceStartUtf16 ==
        b.engineUnpaintedTrailingSpaceStartUtf16 &&
    a.canBreakBefore == b.canBreakBefore &&
    a.canBreakAfter == b.canBreakAfter &&
    a.top == b.top &&
    a.bottom == b.bottom &&
    a.baseline == b.baseline &&
    a.left == b.left &&
    a.width == b.width;

void _verifyAllocatedParent(
  ForumBodyEmphasisRowAllocation plan,
  ForumBodyParagraphLease source,
  ForumBodyParagraphLease parent,
) {
  final layout = parent.layout, expected = plan.reference;
  if (!parent.hasSameActiveOwner(source) ||
      layout.lineCount != expected.lineCount ||
      layout.width != expected.width ||
      layout.height != expected.isolatedHeight ||
      layout.rowIsolationPitch != expected.rowIsolationPitch ||
      layout.nativeAlphabeticBaseline != plan.isolatedAlphabeticBaseline ||
      layout.firstLineIndent.requestedAdvance !=
          expected.firstLineIndent.requestedAdvance ||
      layout.firstLineIndent.appliedAdvance !=
          expected.firstLineIndent.appliedAdvance) {
    ForumBodyEmphasisLinePreparation._mismatch();
  }
}
