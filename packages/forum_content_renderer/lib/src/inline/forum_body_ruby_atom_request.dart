import '../paragraph/forum_body_text_request.dart';
import 'forum_body_ruby_column_request.dart';
import 'forum_body_ruby_segment_request.dart';
import 'forum_body_ruby_soft_space_request.dart';

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
  List<ForumBodyTextRequest> get nativeRequests;
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  );
}

final class ForumBodyRubySoftSpaceAtomRequest extends ForumBodyRubyAtomRequest {
  const ForumBodyRubySoftSpaceAtomRequest(this.value);
  final ForumBodyRubySoftSpaceRequest value;
  @override
  List<ForumBodyTextRequest> get nativeRequests => value.nativeRequests;
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
    ),
  );
}

final class ForumBodyRubySegmentAtomRequest extends ForumBodyRubyAtomRequest {
  const ForumBodyRubySegmentAtomRequest(this.value);
  final ForumBodyRubySegmentRequest value;
  @override
  List<ForumBodyTextRequest> get nativeRequests => value.nativeRequests;
  @override
  ForumBodyRubyAtomRequest mapRequests(
    ForumBodyTextRequest Function(ForumBodyTextRequest) map,
  ) => ForumBodyRubySegmentAtomRequest(value.mapRequests(map));
}
