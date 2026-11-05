import '../flow/forum_body_inline_flow_content.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_ruby_content.dart';
import 'forum_body_ruby_tree_input.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';

part 'forum_body_ruby_source_inspection.dart';

/// Cooperative structural preparation before native planning. Each nested tree
/// builder spends the same caller's work allowance; it is never synchronously
/// drained as one nominal formatting unit inside InlinePlanInput.
final class ForumBodyInlineSourcePreparation {
  ForumBodyInlineSourcePreparation({
    required ForumBodyInlineFlowContent input,
    required this.width,
    required void Function() ensureOwner,
    ForumBodyInlinePlanInput? prefix,
    this.keepTrailingSpace = false,
  }) : _input = input,
       _prefix = prefix,
       _ensureOwner = ensureOwner;
  ForumBodyInlineFlowContent? _input;
  ForumBodyInlinePlanInput? _prefix;
  void Function()? _ensureOwner;
  final double width;
  final bool keepTrailingSpace;
  Map<ForumBodyRubyGroupContent, ForumBodyRubyTreeInput> _trees =
      Map.identity();
  ForumBodyRubyTreeInputPreparation? _tree;
  ForumBodyRubyGlyphTreeInputPreparation? _glyph;
  final Map<ForumBodyRubyGroupContent, ForumBodyRubyGlyphTreeInput>
  _emphasisTrees = Map.identity();
  _RubySourceInspection? _inspection;
  Iterator<bool>? _flags;
  bool _knownEmphasis = false;
  ForumBodyRubyGroupContent? _group;
  ForumBodyInlinePlanInput? _result;
  int _index = 0;
  bool _closed = false;
  bool _operating = false;
  bool get isReady => _result != null;

  int advance({required int maxParts}) {
    if (maxParts <= 0) throw ArgumentError.value(maxParts);
    if (_operating) throw StateError('Inline source preparation is reentrant');
    _operating = true;
    try {
      _guard();
      var units = 0;
      while (!isReady && units < maxParts) {
        final tree = _tree, glyph = _glyph, inspection = _inspection;
        if (glyph != null) {
          units += glyph.advance(maxParts: maxParts - units);
          _guard();
          if (glyph.isReady) {
            final value = glyph.takeInput();
            _guard();
            _emphasisTrees[_group!] = value;
            glyph.close();
            _glyph = null;
            _group = null;
          }
        } else if (_flags != null) {
          if (!_flags!.moveNext()) {
            _flags = null;
            _group = null;
          } else if (_flags!.current) {
            _projectGlyphs();
          }
          units++;
        } else if (tree != null) {
          units += tree.advance(maxParts: maxParts - units);
          _guard();
          if (tree.isReady) {
            _trees[_group!] = tree.takeInput();
            tree.close();
            _tree = null;
            if (_knownEmphasis) {
              _projectGlyphs();
            } else {
              _flags = _rubyTreeEmphasisFlags(_trees[_group!]!).iterator;
            }
          }
        } else if (inspection != null) {
          units += inspection.isComplete
              ? 1
              : inspection.advance(maxParts: maxParts - units);
          _guard();
          if (inspection.isComplete) {
            _knownEmphasis = inspection.emphasisKnown;
            if (inspection.needsTree) {
              _tree = ForumBodyRubyTreeInputPreparation(
                group: _group!,
                maxWidth: width,
              );
            } else {
              _group = null;
            }
            _inspection = null;
          }
        } else if (_index < _input!.parts.length) {
          final part = _input!.parts[_index++];
          if (part is ForumBodyInlineFlowRuby) {
            _group = part.group;
            _inspection = _RubySourceInspection(part.group);
          }
          units++;
        } else {
          final result = ForumBodyInlinePlanInput(
            _input!,
            width,
            trees: _trees,
            emphasisTrees: _emphasisTrees,
            prefix: _prefix,
            keepTrailingSpace: keepTrailingSpace,
          );
          _guard();
          _result = result;
          units++;
        }
        _guard();
      }
      return units;
    } catch (_) {
      close();
      rethrow;
    } finally {
      _operating = false;
    }
  }

  void _projectGlyphs() {
    _flags = null;
    _glyph = ForumBodyRubyGlyphTreeInputPreparation.fromTree(
      sourceTree: _trees[_group!]!,
      ensureOwner: _guard,
    );
  }

  ForumBodyInlinePlanInput takeInput() {
    if (_operating) throw StateError('Inline source preparation is reentrant');
    _operating = true;
    try {
      _guard();
      if (!isReady) throw StateError('Inline source input is incomplete');
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
    if (_closed) throw StateError('Inline source input is retired');
    _ensureOwner!();
    if (_closed) throw StateError('Inline source owner is retired');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _tree?.close();
    _tree = null;
    _glyph?.close();
    _glyph = null;
    _flags = null;
    _inspection = null;
    _emphasisTrees.clear();
    _input = null;
    _prefix = null;
    _group = null;
    _result = null;
    _trees = Map.identity();
    _ensureOwner = null;
  }
}
