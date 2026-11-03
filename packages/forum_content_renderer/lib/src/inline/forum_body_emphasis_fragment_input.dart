part of 'forum_body_emphasis_paragraph_metrics.dart';

/// One selected paragraph fragment's SINGLE drawing input. Original source
/// coordinates remain paragraph-local, and groups retain their local views.
/// This is a pure plan, not current source/font or readable-page authority.
final class ForumBodyEmphasisFragmentInput {
  const ForumBodyEmphasisFragmentInput._(
    this.paragraph,
    this.startLine,
    this.endLine,
    this.selection,
    this.pictureInput,
  );
  static const revision = 1;
  final ForumBodyEmphasisParagraphMetrics paragraph;
  final int startLine, endLine;
  final ForumBodyEmphasisParagraphFragment selection;
  final ForumBodyTextPictureInput pictureInput;
  double get width => paragraph.width;
  double get height => selection.height;
  int get coverageStartUtf16 => selection.coverageStartUtf16;
  int get coverageEndUtf16 => selection.coverageEndUtf16;
  Iterable<ForumBodyEmphasisParagraphGroup> get groups =>
      paragraph.groups.getRange(selection.startGroup, selection.endGroup);

  /// Actual final retention: one shared full-source handle plus one picture.
  int get visibleHandleCount => 2;
  Iterable<ForumBodyNativeRequestSlot> get nativeFootprint =>
      paragraph.nativeFootprintFor(startLine, endLine);
}

/// Combines selected COMPLETE groups using their measured scene inputs. No
/// per-group picture is acquired/recorded and whole native inputs deduplicate
/// in the existing picture accounting. Each command is translated once.
final class ForumBodyEmphasisFragmentInputPreparation {
  ForumBodyEmphasisFragmentInputPreparation({
    required ForumBodyEmphasisParagraphMetrics paragraph,
    required this.startLine,
    required this.endLine,
    required void Function() ensureOwner,
    this.maxGroups = defaultMaxGroups,
    int maxCommands = defaultMaxCommands,
    double maxHeight = defaultMaxHeight,
  }) : _paragraph = paragraph,
       _ensureOwner = ensureOwner {
    try {
      _guard();
      if (maxGroups <= 0 || !maxHeight.isFinite || maxHeight <= 0) {
        throw ArgumentError('Invalid emphasis fragment budget');
      }
      _selection = paragraph.fragment(startLine, endLine);
      final selected = _selection!;
      if (selected.endGroup - selected.startGroup > maxGroups ||
          selected.height > maxHeight) {
        throw const ForumBodyEmphasisParagraphException(
          ForumBodyEmphasisParagraphFailure.limit,
        );
      }
      _composition = ForumBodyTextPictureInputComposition(
        inputs: _parts(),
        ensureOwner: _guard,
        maxInputs: maxGroups,
        maxCommands: maxCommands,
      );
      _guard();
    } catch (_) {
      close();
      rethrow;
    }
  }
  static const defaultMaxGroups = 512;
  static const defaultMaxCommands = 8192;
  static const defaultMaxHeight = 32768.0;
  final int startLine, endLine, maxGroups;
  ForumBodyEmphasisParagraphMetrics? _paragraph;
  ForumBodyEmphasisParagraphFragment? _selection;
  void Function()? _ensureOwner;
  ForumBodyTextPictureInputComposition? _composition;
  ForumBodyEmphasisFragmentInput? _result;
  bool _closed = false, _operating = false;
  bool get isReady => !_closed && _result != null;
  Iterable<ForumBodyPositionedTextPictureInput> _parts() sync* {
    final selected = _selection!;
    for (var index = selected.startGroup; index < selected.endGroup; index++) {
      final group = _paragraph!.groups[index];
      yield (
        input: group.sceneInput.pictureInput,
        offset: Offset(0, group.top - selected.top),
      );
    }
  }

  int advance({int maxParts = 32}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Emphasis fragment input is reentrant');
    _operating = true;
    try {
      _guard();
      if (isReady) return 0;
      final used = _composition!.advance(maxParts: maxParts);
      if (_composition!.isReady) {
        final input = _composition!.takeInput();
        _composition = null;
        _result = ForumBodyEmphasisFragmentInput._(
          _paragraph!,
          startLine,
          endLine,
          _selection!,
          input,
        );
      }
      _guard();
      return used;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  ForumBodyEmphasisFragmentInput takeInput() {
    if (_operating) throw StateError('Emphasis fragment input is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Emphasis fragment input is incomplete');
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
    if (_closed) throw StateError('Emphasis fragment input is retired');
    _ensureOwner!();
    if (_closed) throw StateError('Emphasis fragment input owner is retired');
  }

  void close() {
    _closed = true;
    _composition?.close();
    _composition = null;
    _paragraph = null;
    _selection = null;
    _ensureOwner = null;
    _result = null;
  }
}
