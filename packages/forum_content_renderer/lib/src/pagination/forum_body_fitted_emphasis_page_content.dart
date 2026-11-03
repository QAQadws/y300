part of 'forum_body_text_page_content.dart';

final class ForumBodyFittedEmphasisPageContent
    extends ForumBodyTextPageContent {
  ForumBodyFittedEmphasisPageContent(this.plan) : super._();
  final ForumBodyFittedEmphasisPlan plan;
  ForumBodyParagraphContent get content => plan.content;
  @override
  ForumBodyIdentity get identity => content.identity;
  @override
  int get textCodeUnits => content.projection.text.length;
  @override
  int get runCount => content.runs.length;
  @override
  int get retainedRuns =>
      runCount +
      (identical(content.runs, plan.metrics.input.glyphInput.glyphs.runs)
          ? 0
          : plan.metrics.input.glyphInput.glyphs.runs.length);
  @override
  double requestWidthFor(ForumBodyTextPageFragment fragment) {
    nativeHandleCountFor(fragment);
    return plan.metrics.requestWidth;
  }

  @override
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment) {
    if (fragment.kind != ForumBodyTextPageFragmentKind.fittedEmphasis ||
        fragment.path != content.path ||
        fragment.fontRevision != content.fontRevision ||
        fragment.styleRevision != content.styleRevision) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.identity,
      );
    }
    final line = plan.lines.single;
    if (fragment.startLine != 0 ||
        fragment.endLine != 1 ||
        fragment.width != plan.metrics.width ||
        fragment.height != plan.metrics.height ||
        fragment.coverageStartUtf16 != line.coverageStartUtf16 ||
        fragment.coverageEndUtf16 != line.coverageEndUtf16 ||
        fragment.sourceHint !=
            forumBodySourceHint(
              content.projection,
              line.coverageStartUtf16,
              line.coverageEndUtf16,
            )) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
    return 2;
  }

  @override
  Iterable<ForumBodyNativeRequestSlot> nativeFootprintFor(
    ForumBodyTextPageFragment fragment,
  ) sync* {
    nativeHandleCountFor(fragment);
    yield* plan.metrics.nativeFootprint;
  }
}
