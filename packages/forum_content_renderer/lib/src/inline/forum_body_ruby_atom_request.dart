import '../paragraph/forum_body_text_request.dart';
import 'forum_body_ruby_column_request.dart';
import 'forum_body_ruby_segment_request.dart';
import 'forum_body_ruby_soft_space_request.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_root_box.dart';
import 'forum_body_ruby_tree_input.dart';
import '../style/forum_body_baseline_shift.dart';
import 'forum_body_inline_plan_input.dart';
import 'forum_body_inline_image_input.dart';

/// A resource consumes a parent placeholder and no child font requests.
final class ForumBodyInlineImageAtomRequest extends ForumBodyRubyAtomRequest {
  const ForumBodyInlineImageAtomRequest(this.input);
  final ForumBodyInlineImageInput input;
  @override
  List<ForumBodyTextRequest> get nativeRequests => const [];
  @override
  int get extraTextCodeUnits => input.retainedCodeUnits;
  @override
  ForumBodyRubyContainerBackground? get background => null;
  @override
  ForumBodyRubyRootBoxInput? get rootBox => null;
  @override
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => this;
}

/// A bounded intrinsic text group has its own original parent and leaf plan.
/// Its leaves are not rebound into an outer text band.
final class ForumBodyIntrinsicInlineAtomRequest
    extends ForumBodyRubyAtomRequest {
  const ForumBodyIntrinsicInlineAtomRequest(this.input);
  final ForumBodyInlinePlanInput input;
  @override
  List<ForumBodyTextRequest> get nativeRequests => const [];
  @override
  int get extraTextCodeUnits => input.retainedTextCodeUnits;
  @override
  int get extraRuns => input.retainedRuns;
  @override
  ForumBodyRubyContainerBackground? get background => null;
  @override
  ForumBodyRubyRootBoxInput? get rootBox => null;
  @override
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => this;
}

/// Internal pre-measurement variant of an actual parent atom. It borrows the
/// existing immutable requests; numeric targets only enter the later AtomPlan.
sealed class ForumBodyRubyAtomRequest {
  const ForumBodyRubyAtomRequest();
  const factory ForumBodyRubyAtomRequest.column(
    ForumBodyRubyColumnRequest value,
  ) = ForumBodyRubyColumnAtomRequest;
  const factory ForumBodyRubyAtomRequest.segment(
    ForumBodyRubySegmentRequest value,
  ) = ForumBodyRubySegmentAtomRequest;
  const factory ForumBodyRubyAtomRequest.softSpace(
    ForumBodyRubySoftSpaceRequest value,
  ) = ForumBodyRubySoftSpaceAtomRequest;
  const factory ForumBodyRubyAtomRequest.tree(ForumBodyRubyTreeInput value) =
      ForumBodyRubyTreeAtomRequest;
  List<ForumBodyTextRequest> get nativeRequests;
  ForumBodyRubyContainerBackground? get background;
  ForumBodyRubyRootBoxInput? get rootBox;
  int get extraTextCodeUnits => 0;
  int get extraRuns => 0;
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  );
}

final class ForumBodyTextBaselineAtomRequest extends ForumBodyRubyAtomRequest {
  const ForumBodyTextBaselineAtomRequest(this.text, this.shift, this.maxWidth);
  final ForumBodyTextRequest text;
  final ForumBodyBaselineShift shift;
  final double maxWidth;
  @override
  List<ForumBodyTextRequest> get nativeRequests => [text];
  @override
  ForumBodyRubyContainerBackground? get background => null;
  @override
  ForumBodyRubyRootBoxInput? get rootBox => null;
  @override
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyTextBaselineAtomRequest(map(text), shift, maxWidth);
}

final class ForumBodyRubyTreeAtomRequest extends ForumBodyRubyAtomRequest {
  const ForumBodyRubyTreeAtomRequest(this.value);
  final ForumBodyRubyTreeInput value;
  @override
  int get extraTextCodeUnits => value.extraTextCodeUnits;
  @override
  int get extraRuns => value.extraRuns;
  @override
  List<ForumBodyTextRequest> get nativeRequests => value.nativeRequests;
  // Every tree surface, including the root, enters the shared page plane.
  @override
  ForumBodyRubyContainerBackground? get background => null;
  @override
  ForumBodyRubyRootBoxInput get rootBox => value.rootGroup.font;
  @override
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyRubyTreeAtomRequest(value.mapRequests(map));
}

final class ForumBodyRubySoftSpaceAtomRequest extends ForumBodyRubyAtomRequest {
  const ForumBodyRubySoftSpaceAtomRequest(this.value);
  final ForumBodyRubySoftSpaceRequest value;
  @override
  List<ForumBodyTextRequest> get nativeRequests => value.nativeRequests;
  @override
  ForumBodyRubyContainerBackground? get background => value.background;
  @override
  ForumBodyRubyRootBoxInput? get rootBox => value.rootBox;
  @override
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyRubySoftSpaceAtomRequest(value.mapRequests(map));
}

final class ForumBodyRubyColumnAtomRequest extends ForumBodyRubyAtomRequest {
  const ForumBodyRubyColumnAtomRequest(this.value);
  final ForumBodyRubyColumnRequest value;
  @override
  List<ForumBodyTextRequest> get nativeRequests => value.nativeRequests;
  @override
  ForumBodyRubyContainerBackground? get background => value.background;
  @override
  ForumBodyRubyRootBoxInput? get rootBox => value.rootBox;
  @override
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyRubyColumnAtomRequest(
    ForumBodyRubyColumnRequest.layers(
      base: map(value.base),
      annotations: [
        for (final a in value.annotations)
          (request: map(a.request), gap: a.gap, side: a.side),
      ],
      maxWidth: value.maxWidth,
      background: value.background,
      rootBox: value.rootBox,
    ),
  );
}

final class ForumBodyRubySegmentAtomRequest extends ForumBodyRubyAtomRequest {
  const ForumBodyRubySegmentAtomRequest(this.value);
  final ForumBodyRubySegmentRequest value;
  @override
  List<ForumBodyTextRequest> get nativeRequests => value.nativeRequests;
  @override
  ForumBodyRubyContainerBackground? get background => value.background;
  @override
  ForumBodyRubyRootBoxInput? get rootBox => value.rootBox;
  @override
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyRubySegmentAtomRequest(value.mapRequests(map));
}
