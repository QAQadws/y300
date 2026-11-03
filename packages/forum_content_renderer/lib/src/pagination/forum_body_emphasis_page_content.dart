part of 'forum_body_text_page_content.dart';

/// Whole-paragraph pure input. Final scene composition is a bounded page-job
/// task, never a synchronous getter or a retained native-resource cache.
final class ForumBodyEmphasisPageContent extends ForumBodyTextPageContent {
  ForumBodyEmphasisPageContent(this.paragraph) : super._() {
    if (paragraph.groups.isEmpty || paragraph.content.isSourceFree) {
      throw ArgumentError('Emphasis page content needs complete source groups');
    }
  }
  final ForumBodyEmphasisParagraphMetrics paragraph;
  ForumBodyParagraphContent get content => paragraph.content;
  @override
  ForumBodyIdentity get identity => content.identity;
  @override
  int get textCodeUnits => content.projection.text.length;
  @override
  int get runCount => content.runs.length;
  @override
  int get retainedTextCodeUnits => paragraph.retainedTextCodeUnits;
  @override
  int get retainedRuns => paragraph.retainedRuns;
  @override
  double requestWidthFor(ForumBodyTextPageFragment fragment) {
    nativeHandleCountFor(fragment);
    return paragraph.width;
  }

  @override
  int nativeHandleCountFor(ForumBodyTextPageFragment fragment) {
    if (fragment.kind != ForumBodyTextPageFragmentKind.emphasis ||
        fragment.path != content.path ||
        fragment.fontRevision != content.fontRevision ||
        fragment.styleRevision != content.styleRevision) {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.identity,
      );
    }
    ForumBodyEmphasisParagraphFragment selected;
    try {
      selected = paragraph.fragment(fragment.startLine, fragment.endLine);
    } on RangeError {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    } on ForumBodyParagraphLayoutException {
      throw const ForumBodyTextPageSurfaceException(
        ForumBodyTextPageSurfaceFailure.geometry,
      );
    }
    if (fragment.width != paragraph.width ||
        fragment.height != selected.height ||
        fragment.coverageStartUtf16 != selected.coverageStartUtf16 ||
        fragment.coverageEndUtf16 != selected.coverageEndUtf16 ||
        fragment.sourceHint !=
            forumBodySourceHint(
              content.projection,
              selected.coverageStartUtf16,
              selected.coverageEndUtf16,
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
    yield* paragraph.nativeFootprintFor(fragment.startLine, fragment.endLine);
  }

  ForumBodyEmphasisFragmentInputPreparation openFragmentInput({
    required ForumBodyTextPageFragment fragment,
    required void Function() ensureOwner,
  }) {
    nativeHandleCountFor(fragment);
    return ForumBodyEmphasisFragmentInputPreparation(
      paragraph: paragraph,
      startLine: fragment.startLine,
      endLine: fragment.endLine,
      ensureOwner: ensureOwner,
    );
  }
}
