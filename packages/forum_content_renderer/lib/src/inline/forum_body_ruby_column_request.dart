import '../paragraph/forum_body_text_request.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
import 'forum_body_ruby_group_contract.dart';
import 'forum_body_ruby_container_background.dart';

/// Pure source-bound child requests. Dimensions belong to the measured parent
/// plan, not these requests; visible preparation rechecks actual child metrics.
final class ForumBodyRubyColumnRequest {
  ForumBodyRubyColumnRequest({
    required ForumBodyTextRequest base,
    required ForumBodyTextRequest annotation,
    double gap = 0,
    double maxWidth = 16384,
    ForumBodyRubySide side = ForumBodyRubySide.over,
    ForumBodyRubyContainerBackground? background,
  }) : this.layers(
         base: base,
         annotations: [(request: annotation, gap: gap, side: side)],
         maxWidth: maxWidth,
         background: background,
       );

  ForumBodyRubyColumnRequest.layers({
    required this.base,
    required List<
      ({ForumBodyTextRequest request, double gap, ForumBodyRubySide side})
    >
    annotations,
    this.maxWidth = 16384,
    this.background,
  }) : annotations = List.unmodifiable(annotations),
       nativeRequests = List.unmodifiable([
         base,
         for (final item in annotations)
           if (item.request.content.projection.text.isNotEmpty) item.request,
       ]) {
    background?.validateScope(base.content);
    validateForumBodyRubyColumnInputs(
      base: base.content,
      annotations: [
        for (final item in this.annotations)
          (content: item.request.content, gap: item.gap),
      ],
      maxWidth: maxWidth,
    );
  }
  final ForumBodyTextRequest base;
  final ForumBodyRubyContainerBackground? background;
  final List<
    ({ForumBodyTextRequest request, double gap, ForumBodyRubySide side})
  >
  annotations;

  /// Actual native positions in base/rank order, omitting missing glyph ranks.
  /// The base is always present, including its source-free native font strut.
  final List<ForumBodyTextRequest> nativeRequests;
  final double maxWidth;
  ForumBodyTextRequest get annotation => annotations.single.request;
  double get gap => annotations.single.gap;
  ForumBodyRubySide get side => annotations.single.side;
  bool get hasAnnotation => nativeRequests.length > 1;
  int get nativeHandleCount => nativeRequests.length;
}

/// Existing single-level callers construct the same column value. There is no
/// second pair implementation or implicit first-annotation view of many ranks.
typedef ForumBodyRubyPairRequest = ForumBodyRubyColumnRequest;
