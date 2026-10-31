import '../flow/forum_body_inline_flow_content.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import '../pagination/forum_body_text_page_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_inline_span_content.dart';
import 'forum_body_ruby_content.dart';
import 'forum_body_text_band_content.dart';

/// Pure source-bound parent input and child requests for the session's pending
/// format. No native resource, owner or scheduler is retained here.
final class ForumBodyInlinePlanInput {
  ForumBodyInlinePlanInput._(this.content, this.groups, this.width);
  static const revision = 2;

  factory ForumBodyInlinePlanInput(
    ForumBodyInlineFlowContent input,
    double width,
  ) {
    if (input.layoutMode != ForumBodyParagraphLayoutMode.wrap) {
      _unsupported(input.path);
    }
    final contexts = <ForumBodyParagraphContent>[];
    final pairs =
        <
          ({
            ForumBodyParagraphContent base,
            ForumBodyParagraphContent annotation,
          })
        >[];
    final atoms = <({int startUtf16, int endUtf16})>[];
    var offset = 0;
    void append(ForumBodyParagraphContent context) {
      contexts.add(context);
      offset += context.projection.text.length;
    }

    for (final (index, part) in input.parts.indexed) {
      switch (part) {
        case ForumBodyInlineFlowText():
          append(
            _plainContext(
              part.content,
              leading: index == 0,
              trailing: index == input.parts.length - 1,
            ),
          );
        case ForumBodyInlineFlowRuby():
          final group = part.group;
          if (group.identity != input.identity ||
              group.fontRevision != input.fontRevision ||
              group.styleRevision != input.styleRevision) {
            throw ForumBodyParagraphInputException(
              ForumBodyParagraphInputFailure.identity,
              group.rootPath,
            );
          }
          if (group.base.length != 1 ||
              group.base.single is! ForumBodyRubyTextContent ||
              group.annotations.length > 1) {
            _unsupported(group.rootPath);
          }
          final base = (group.base.single as ForumBodyRubyTextContent).content;
          final ForumBodyParagraphContent annotation;
          if (group.annotations.isEmpty) {
            append(
              _plainContext(
                base,
                leading: index == 0,
                trailing: index == input.parts.length - 1,
              ),
            );
            continue;
          } else {
            final parts = group.annotations.single.parts;
            if (parts.length != 1 ||
                parts.single is! ForumBodyRubyTextContent) {
              _unsupported(group.rootPath);
            }
            // An annotation is its own native line. Trim its collapsible line
            // edges through source-bound windows, never into the base context.
            annotation = _plainContext(
              (parts.single as ForumBodyRubyTextContent).content,
              leading: true,
              trailing: true,
            );
          }
          // These edges need base-level whitespace planning across atoms. Do
          // not pin a collapsed space inside a box or discard it silently.
          if (_collapsibleEdge(base, leading: true) ||
              _collapsibleEdge(base, leading: false)) {
            _unsupported(group.rootPath);
          }
          final start = offset;
          append(base);
          append(annotation);
          atoms.add((startUtf16: start, endUtf16: offset));
          pairs.add((base: base, annotation: annotation));
      }
    }
    final content = ForumBodyInlineSpanContent.compose(
      identity: input.identity,
      path: input.path,
      fontRevision: input.fontRevision,
      styleRevision: input.styleRevision,
      style: input.style,
      contexts: contexts,
      atomicRanges: atoms,
    );
    final requests = _requests([
      for (final pair in pairs) ...[
        pair.base,
        if (pair.annotation.projection.text.isNotEmpty) pair.annotation,
      ],
    ]);
    return ForumBodyInlinePlanInput._(content, [
      for (final pair in pairs)
        ForumBodyRubyPairRequest(
          base: requests[pair.base]!,
          annotation:
              requests[pair.annotation] ??
              ForumBodyTextRequest.paragraph(pair.annotation),
          maxWidth: width,
        ),
    ], width);
  }

  final ForumBodyInlineSpanContent content;
  final double width;
  // Rebound only before publication when native isolation supplies a new
  // request. Published PageContent freezes its own copy of this pure list.
  final List<ForumBodyRubyPairRequest> groups;

  void replaceBand(ForumBodyTextBandContent band, double? gutter) {
    ForumBodyTextRequest replace(ForumBodyTextRequest request) {
      if (request is! ForumBodyTextBandChildRequest ||
          !identical(request.band, band)) {
        return request;
      }
      return gutter == null
          ? ForumBodyTextRequest.paragraph(request.content)
          : ForumBodyTextRequest.bandChild(
              band: band,
              childIndex: request.childIndex,
              gutter: gutter,
            );
    }

    for (var i = 0; i < groups.length; i++) {
      final pair = groups[i];
      groups[i] = ForumBodyRubyPairRequest(
        base: replace(pair.base),
        annotation: replace(pair.annotation),
        gap: pair.gap,
        maxWidth: pair.maxWidth,
      );
    }
  }
}

ForumBodyParagraphContent _plainContext(
  ForumBodyParagraphContent context, {
  required bool leading,
  required bool trailing,
}) {
  var start = 0;
  var end = context.projection.text.length;
  if (leading && _collapsibleEdge(context, leading: true)) start++;
  if (trailing && end > start && _collapsibleEdge(context, leading: false)) {
    end--;
  }
  if (start == 0 && end == context.projection.text.length) return context;
  // Preserve complete graphemes and actual source affinity. A raw whitespace
  // normalizer must resolve a space joined to a combining mark, not split it.
  if (context.projection.sourceAtUtf16(start).displayUtf16 != start ||
      context.projection.sourceAtUtf16(end).displayUtf16 != end) {
    _unsupported(context.path);
  }
  return context.displayWindow(startUtf16: start, endUtf16: end);
}

bool _collapsibleEdge(
  ForumBodyParagraphContent context, {
  required bool leading,
}) {
  final projection = context.projection;
  if (projection.text.isEmpty) return false;
  final part = leading ? projection.parts.first : projection.parts.last;
  final index = leading ? 0 : projection.text.length - 1;
  final mode = context.runs[part.runIndex].style.whiteSpace;
  return projection.text.codeUnitAt(index) == 32 &&
      (mode == ForumBodyWhiteSpace.normal ||
          mode == ForumBodyWhiteSpace.preLine);
}

Never _unsupported(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.structure,
  path,
);

Map<ForumBodyParagraphContent, ForumBodyTextRequest> _requests(
  List<ForumBodyParagraphContent> contexts,
) {
  final result =
      Map<ForumBodyParagraphContent, ForumBodyTextRequest>.identity();
  var pending = <ForumBodyParagraphContent>[];
  var length = 0;
  var runs = 0;
  void flush() {
    if (pending.isEmpty) return;
    final band = ForumBodyTextBandContent(contexts: pending);
    for (final (index, context) in pending.indexed) {
      result[context] = ForumBodyTextRequest.bandChild(
        band: band,
        childIndex: index,
      );
    }
    pending = [];
    length = 0;
    runs = 0;
  }

  for (final context in contexts) {
    if (!ForumBodyTextBandContent.supportsContext(context)) {
      flush();
      result[context] = ForumBodyTextRequest.paragraph(context);
      continue;
    }
    final first = pending.firstOrNull;
    if (pending.length == 64 ||
        length + context.projection.text.length > 16384 ||
        runs + context.runs.length > 512 ||
        (first != null &&
            (first.style.textDirection != context.style.textDirection ||
                first.style.textAlign != context.style.textAlign ||
                first.style.textStyle.locale !=
                    context.style.textStyle.locale))) {
      flush();
    }
    pending.add(context);
    length += context.projection.text.length;
    runs += context.runs.length;
  }
  flush();
  return result;
}
