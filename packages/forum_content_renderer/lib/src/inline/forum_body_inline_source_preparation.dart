import '../flow/forum_body_inline_flow_content.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_ruby_content.dart';
import 'forum_body_ruby_tree_input.dart';

/// Cooperative structural preparation before native planning. Each nested tree
/// builder spends the same caller's work allowance; it is never synchronously
/// drained as one nominal formatting unit inside InlinePlanInput.
final class ForumBodyInlineSourcePreparation {
  ForumBodyInlineSourcePreparation({
    required ForumBodyInlineFlowContent input,
    required this.width,
    required void Function() ensureOwner,
  }) : _input = input,
       _ensureOwner = ensureOwner;
  ForumBodyInlineFlowContent? _input;
  void Function()? _ensureOwner;
  final double width;
  Map<ForumBodyRubyGroupContent, ForumBodyRubyTreeInput> _trees =
      Map.identity();
  ForumBodyRubyTreeInputPreparation? _tree;
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
        final tree = _tree;
        if (tree != null) {
          units += tree.advance(maxParts: maxParts - units);
          _guard();
          if (tree.isReady) {
            _trees[_group!] = tree.takeInput();
            tree.close();
            _tree = null;
            _group = null;
          }
        } else if (_index < _input!.parts.length) {
          final part = _input!.parts[_index++];
          if (part is ForumBodyInlineFlowRuby && _hasNested(part.group)) {
            _group = part.group;
            _tree = ForumBodyRubyTreeInputPreparation(
              group: part.group,
              maxWidth: width,
            );
          }
          units++;
        } else {
          final result = ForumBodyInlinePlanInput(
            _input!,
            width,
            trees: _trees,
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

  ForumBodyInlinePlanInput takeInput() {
    _guard();
    if (!isReady) throw StateError('Inline source input is incomplete');
    final result = _result!;
    close();
    return result;
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
    _input = null;
    _group = null;
    _result = null;
    _trees = Map.identity();
    _ensureOwner = null;
  }
}

bool _hasNested(ForumBodyRubyGroupContent group) {
  final pending = <ForumBodyRubyInlineContent>[
    ...group.base,
    ...group.annotations,
  ];
  while (pending.isNotEmpty) {
    switch (pending.removeLast()) {
      case ForumBodyRubyNestedContent():
        return true;
      case ForumBodyRubyBaseContent(:final parts) ||
          ForumBodyRubyAnnotationContent(:final parts):
        pending.addAll(parts);
      case ForumBodyRubyTextContent():
        break;
    }
  }
  return false;
}
