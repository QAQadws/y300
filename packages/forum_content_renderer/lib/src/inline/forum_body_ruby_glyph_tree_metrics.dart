part of 'forum_body_ruby_tree_input.dart';

/// The existing tree engine's glyph-only numbers. This is intentionally not a
/// ForumBodyRubyTreeMetrics render input: markers, ancestor bands and the final
/// enclosing frame still require their own measured format and visible binding.
final class ForumBodyRubyGlyphTreeMetrics {
  const ForumBodyRubyGlyphTreeMetrics._(this.input, this._value);
  final ForumBodyRubyGlyphTreeInput input;
  final ForumBodyRubyTreeMetrics _value;
  List<ForumBodyRubyTreeNodeMetrics> get nodes => _value.nodes;
  ForumBodyRubyTreeContainerMetrics get root => _value.root;
  ForumBodyRubyChildMetrics get box => _value.box;
  Map<double, double> get effectiveGlyphScales => _value.effectiveScales;
  TextScaler get glyphTextScaler => _value.textScaler;
  int get glyphHandleCount => _value.nativeHandleCount;
  Iterable<ForumBodyNativeBudgetSlot> get nativeGlyphBudgetFootprint =>
      _value.nativeBudgetFootprint;
}

/// Delegates actual shaping/stacking/cancellation to the shared tree engine.
/// Only the private, explicitly derived graph reaches that engine; consumers
/// receive glyph metadata, not a source-authorized visible tree or scene.
final class ForumBodyRubyGlyphTreeMetricsPreparation {
  ForumBodyRubyGlyphTreeMetricsPreparation({
    required ForumBodyRubyGlyphTreeInput input,
    required ForumBodyParagraphCache cache,
    required void Function() ensureOwner,
    TextScaler textScaler = TextScaler.noScaling,
    Iterable<ForumBodyNativeParagraphLease> Function()? additionalOwnedLeases,
  }) : _input = input,
       _work = ForumBodyRubyTreeMetricsPreparation(
         input: input._glyphTree,
         cache: cache,
         ensureOwner: ensureOwner,
         textScaler: textScaler,
         additionalOwnedLeases: additionalOwnedLeases,
       );
  ForumBodyRubyGlyphTreeInput? _input;
  final ForumBodyRubyTreeMetricsPreparation _work;
  bool _operating = false;
  bool get isReady => _work.isReady;
  bool get cacheMiss => _work.cacheMiss;
  ForumBodyTextRequest? get failedRequest => _work.failedRequest;
  ForumBodyParagraphBudgetException? get lastBudgetRejection =>
      _work.lastBudgetRejection;
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _work.nativeLeases;
  ForumBodyRubyGroupPreparationStep advance({
    int maxParts = 32,
    bool cachedOnly = false,
  }) =>
      _operate(() => _work.advance(maxParts: maxParts, cachedOnly: cachedOnly));

  ForumBodyRubyGlyphTreeMetrics takeMetrics() => _operate(() {
    final value = _work.takeMetrics();
    final input = _input!;
    _input = null;
    return ForumBodyRubyGlyphTreeMetrics._(input, value);
  });

  T _operate<T>(T Function() action) {
    if (_operating) {
      throw StateError('Ruby glyph metrics preparation is reentrant');
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

  void close() {
    _input = null;
    _work.close();
  }
}
