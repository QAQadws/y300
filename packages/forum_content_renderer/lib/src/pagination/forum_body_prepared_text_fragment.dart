import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../inline/forum_body_inline_paragraph_view.dart';
import '../inline/forum_body_emphasis_line_layout.dart';
import '../inline/forum_body_fitted_emphasis_plan.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_geometry.dart'
    show forumBodyPaintedTextRanges;
import 'forum_body_list_marker_plan.dart';
import 'forum_body_text_page_composer.dart';

/// One complete prepared fragment. Each concurrently mounted view must own
/// distinct handles even when they share the same cache entry. These values
/// are transient delivery handles, never published snapshot metadata.
sealed class ForumBodyPreparedTextFragment {
  const ForumBodyPreparedTextFragment._();
  factory ForumBodyPreparedTextFragment.paragraph({
    required ForumBodyParagraphLease lease,
    required int startLine,
    required int endLine,
  }) = ForumBodyPreparedParagraphFragment;
  factory ForumBodyPreparedTextFragment.inline(
    ForumBodyInlineParagraphView view,
  ) = ForumBodyPreparedInlineFragment;
  factory ForumBodyPreparedTextFragment.emphasis(
    ForumBodyEmphasisFragmentLayout view,
  ) = ForumBodyPreparedEmphasisFragment;
  factory ForumBodyPreparedTextFragment.fittedEmphasis({
    required ForumBodyEmphasisLineLayout view,
    required ForumBodyFittedEmphasisPlan plan,
  }) = ForumBodyPreparedFittedEmphasisFragment;
  bool get isActive;
  Iterable<Rect> get decorationBounds => const [];

  /// Borrowed for the same owner's page-budget checks and lifecycle counts.
  /// Reading this list never acquires aliases or transfers the handles.
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases;

  HtmlDisplayTextProjection get projection;
  List<ForumBodyParagraphRun> get runs;

  /// Current native rows, with physical coordinates relative to this fragment.
  /// Logical display/source offsets are unchanged by the window translation.
  Iterable<ForumBodyParagraphLine> get lines;

  /// Real native glyph boxes in fragment-local coordinates, bounded to this
  /// fragment's display range but deliberately NOT clipped to its frame. A
  /// coverage checker must reject a partly hidden glyph, not prove its clipped
  /// rectangle. Mixed atoms resolve through their actual prepared child glyphs.
  /// Confirmed unpainted parent-row SPACE suffixes supply no glyph or anchor
  /// evidence; ordinary UI selections still retain their native boxes.
  List<TextBox> glyphBoxes(int startUtf16, int endUtf16);
  void close();
}

/// The body keeps its original source/geometry. The picture owns no source.
final class ForumBodyPreparedListItemFragment
    extends ForumBodyPreparedTextFragment {
  const ForumBodyPreparedListItemFragment(
    this.body,
    this.plan,
    this.placement,
    this.picture,
  ) : super._();
  final ForumBodyPreparedTextFragment body;
  final ForumBodyListMarkerPlan plan;
  final ForumBodyTextPageListMarker placement;
  final ForumBodyTextPictureLease picture;
  @override
  bool get isActive => body.isActive && picture.isActive;
  @override
  Iterable<Rect> get decorationBounds => [placement.bounds];
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    ...body.nativeLeases,
    picture,
  ];
  @override
  HtmlDisplayTextProjection get projection => body.projection;
  @override
  List<ForumBodyParagraphRun> get runs => body.runs;
  @override
  Iterable<ForumBodyParagraphLine> get lines => body.lines;
  @override
  List<TextBox> glyphBoxes(int startUtf16, int endUtf16) =>
      body.glyphBoxes(startUtf16, endUtf16);
  @override
  void close() {
    try {
      body.close();
    } finally {
      picture.release();
    }
  }
}

final class ForumBodyPreparedEmphasisFragment
    extends ForumBodyPreparedTextFragment {
  const ForumBodyPreparedEmphasisFragment(this.view) : super._();
  final ForumBodyEmphasisFragmentLayout view;
  @override
  bool get isActive => !view.isDisposed;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => view.nativeLeases;
  @override
  HtmlDisplayTextProjection get projection => view.projection;
  @override
  List<ForumBodyParagraphRun> get runs => view.input.paragraph.content.runs;
  @override
  Iterable<ForumBodyParagraphLine> get lines => view.lines;
  @override
  List<TextBox> glyphBoxes(int startUtf16, int endUtf16) =>
      view.glyphBoxes(startUtf16, endUtf16);
  @override
  void close() => view.close();
}

final class ForumBodyPreparedFittedEmphasisFragment
    extends ForumBodyPreparedTextFragment {
  ForumBodyPreparedFittedEmphasisFragment({
    required this.view,
    required this.plan,
  }) : super._() {
    if (!identical(view.metrics, plan.metrics)) {
      throw ArgumentError('Fitted source and numeric plan differ');
    }
  }
  final ForumBodyEmphasisLineLayout view;
  final ForumBodyFittedEmphasisPlan plan;
  @override
  bool get isActive => !view.isDisposed;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => view.nativeLeases;
  @override
  HtmlDisplayTextProjection get projection => view.projection;
  @override
  List<ForumBodyParagraphRun> get runs => plan.content.runs;
  @override
  Iterable<ForumBodyParagraphLine> get lines => plan.lines;
  @override
  List<TextBox> glyphBoxes(int startUtf16, int endUtf16) {
    view.ensureActive();
    // Native tail SPACE is omitted from paint, while selection and copying
    // retain it. Keep every actual glyph box, including any out-of-frame box.
    return List.unmodifiable([
      for (final range in forumBodyPaintedTextRanges(
        plan.lines,
        startUtf16,
        endUtf16,
      ))
        ...view.selectionBoxes(range.start, range.end),
    ]);
  }

  @override
  void close() => view.close();
}

final class ForumBodyPreparedParagraphFragment
    extends ForumBodyPreparedTextFragment {
  ForumBodyPreparedParagraphFragment({
    required this.lease,
    required this.startLine,
    required this.endLine,
  }) : super._() {
    try {
      if (!lease.isActive || lease.layout.isDisposed) {
        throw StateError('Prepared paragraph is retired');
      }
      if (lease.layout.lines.isEmpty) {
        if (startLine != 0 || endLine != 0) {
          throw RangeError('Empty paragraph window');
        }
      } else {
        lease.layout.fragment(startLine, endLine);
      }
    } catch (_) {
      lease.release();
      rethrow;
    }
  }
  final ForumBodyParagraphLease lease;
  final int startLine;
  final int endLine;
  ForumBodyParagraphFragment? get view => lease.layout.lines.isEmpty
      ? null
      : lease.layout.fragment(startLine, endLine);
  @override
  bool get isActive => lease.isActive && !lease.layout.isDisposed;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [lease];
  @override
  HtmlDisplayTextProjection get projection => lease.content.projection;
  @override
  List<ForumBodyParagraphRun> get runs => lease.content.runs;
  @override
  Iterable<ForumBodyParagraphLine> get lines {
    final window = view;
    if (window == null) return const [];
    final top = window.top;
    return lease.layout.lines
        .getRange(startLine, endLine)
        .map((line) => line.shift(Offset(0, -top)));
  }

  @override
  List<TextBox> glyphBoxes(int startUtf16, int endUtf16) {
    RangeError.checkValidRange(startUtf16, endUtf16, projection.text.length);
    final window = view;
    if (window == null) return const [];
    final start = startUtf16.clamp(
      window.coverageStartUtf16,
      window.coverageEndUtf16,
    );
    final end = endUtf16.clamp(
      window.coverageStartUtf16,
      window.coverageEndUtf16,
    );
    if (start >= end) return const [];
    return List.unmodifiable([
      for (final range in forumBodyPaintedTextRanges(
        lease.layout.lines,
        start,
        end,
      ))
        for (final box in lease.layout.selectionBoxes(range.start, range.end))
          TextBox.fromLTRBD(
            box.left,
            box.top - window.top,
            box.right,
            box.bottom - window.top,
            box.direction,
          ),
    ]);
  }

  @override
  void close() => lease.release();
}

final class ForumBodyPreparedInlineFragment
    extends ForumBodyPreparedTextFragment {
  const ForumBodyPreparedInlineFragment(this.view) : super._();
  final ForumBodyInlineParagraphView view;
  @override
  bool get isActive => view.isActive;
  @override
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => view.nativeLeases;
  @override
  HtmlDisplayTextProjection get projection => view.content.projection.display;
  @override
  List<ForumBodyParagraphRun> get runs => view.content.runs;
  @override
  Iterable<ForumBodyParagraphLine> get lines => view.lines;
  @override
  List<TextBox> glyphBoxes(int startUtf16, int endUtf16) =>
      view.glyphBoxes(startUtf16, endUtf16);
  @override
  void close() => view.close();
}
