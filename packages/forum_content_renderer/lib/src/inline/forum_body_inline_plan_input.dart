import '../flow/forum_body_inline_flow_content.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../paragraph/forum_body_text_request.dart';
import '../pagination/forum_body_text_page_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_inline_span_content.dart';
import 'forum_body_ruby_base_input.dart';
import 'forum_body_ruby_content.dart';
import 'forum_body_text_band_content.dart';

/// Pure source-bound parent input and child requests for the session's pending
/// format. No native resource, owner or scheduler is retained here.
final class ForumBodyInlinePlanInput {
  ForumBodyInlinePlanInput._(
    this.content,
    this.groups,
    this.width,
    List<int> levelIds,
  ) : rubyLevelIds = List.unmodifiable(levelIds),
      atomEngineOffsets = List.unmodifiable(
        content.projection.atoms.map((atom) => atom.engineUtf16),
      );
  static const revision = 8;

  factory ForumBodyInlinePlanInput(
    ForumBodyInlineFlowContent input,
    double width,
  ) {
    if (input.layoutMode != ForumBodyParagraphLayoutMode.wrap) {
      _unsupported(input.path);
    }
    final contexts = <ForumBodyParagraphContent>[];
    final sourceOrder = <int>[];
    final pairs =
        <
          ({
            ForumBodyParagraphContent base,
            ForumBodyParagraphContent annotation,
          })
        >[];
    final atoms = <({int startUtf16, int endUtf16})>[];
    final levelIds = <int>[];
    final roots = <String, int>{};
    var offset = 0;
    var previousCollapsibleSpace = false;
    var atLineStart = true;
    int? lastPlain;
    int append(ForumBodyParagraphContent context) {
      final index = contexts.length;
      contexts.add(context);
      offset += context.projection.text.length;
      return index;
    }

    void trimTrailingPlain() {
      final index = lastPlain;
      if (index == null) return;
      final old = contexts[index];
      final trimmed = _plainContext(old, leading: false, trailing: true);
      contexts[index] = trimmed;
      offset -= old.projection.text.length - trimmed.projection.text.length;
      previousCollapsibleSpace = false;
    }

    int appendPlain(ForumBodyParagraphContent context) {
      if (previousCollapsibleSpace &&
          context.projection.text.isNotEmpty &&
          forumBodyIsDisplayLineBreak(context.projection.text.codeUnitAt(0))) {
        trimTrailingPlain();
      }
      final plain = _plainContext(
        context,
        leading: atLineStart || previousCollapsibleSpace,
        trailing: false,
      );
      final index = append(plain);
      if (plain.projection.text.isNotEmpty) {
        lastPlain = index;
        previousCollapsibleSpace = _collapsibleEdge(plain, leading: false);
        atLineStart = forumBodyIsDisplayLineBreak(
          plain.projection.text.codeUnitAt(plain.projection.text.length - 1),
        );
      }
      return index;
    }

    void appendColumn(
      ForumBodyParagraphContent base,
      ForumBodyParagraphContent annotation,
      List<int> baseIndices,
      List<int> annotationIndices,
      int levelId,
    ) {
      if (base.projection.text.isEmpty && annotation.projection.text.isEmpty) {
        _unsupported(base.path ?? annotation.path);
      }
      final start = offset;
      if (!base.isSourceFree) baseIndices.add(append(base));
      if (!annotation.isSourceFree) annotationIndices.add(append(annotation));
      atoms.add((startUtf16: start, endUtf16: offset));
      pairs.add((base: base, annotation: annotation));
      levelIds.add(levelId);
      previousCollapsibleSpace = false;
      atLineStart = false;
      lastPlain = null;
    }

    for (final part in input.parts) {
      switch (part) {
        case ForumBodyInlineFlowText():
          sourceOrder.add(appendPlain(part.content));
        case ForumBodyInlineFlowRuby():
          final group = part.group;
          final levelId = roots.putIfAbsent(group.rootPath, () => roots.length);
          if (group.identity != input.identity ||
              group.fontRevision != input.fontRevision ||
              group.styleRevision != input.styleRevision) {
            throw ForumBodyParagraphInputException(
              ForumBodyParagraphInputFailure.identity,
              group.rootPath,
            );
          }
          final bases = resolveForumBodyRubyBaseInputs(group);
          if (bases.isEmpty && group.annotations.isEmpty) {
            _unsupported(group.rootPath);
          }
          final annotations = [
            for (final annotation in group.annotations)
              _annotationInput(annotation),
          ];
          final baseSources = [for (final _ in bases) <int>[]];
          final annotationIndices = <int>[];
          final unitCount = bases
              .where((base) => base.kind != ForumBodyRubyBaseInputKind.gap)
              .length;
          var column = 0;
          ForumBodyParagraphContent? anonymous;
          ({ForumBodyParagraphContent content, List<int> source})? deferredTail;
          for (final (index, unit) in bases.indexed) {
            final sources = baseSources[index];
            var base = unit.content;
            if (unit.kind == ForumBodyRubyBaseInputKind.gap) {
              // Structural edge indentation is omitted; inter-base whitespace
              // uses the actual parent's text layout, without consuming an RT.
              final end = base.projection.text.length;
              sources.add(
                column == 0 || column == unitCount
                    ? append(_window(base, end, end))
                    : appendPlain(base),
              );
              continue;
            }
            if (column >= annotations.length &&
                unit.kind == ForumBodyRubyBaseInputKind.implicit) {
              sources.add(appendPlain(base));
              column++;
              continue;
            }
            ForumBodyParagraphContent? trailing;
            if (unit.kind == ForumBodyRubyBaseInputKind.implicit) {
              if (base.projection.text == ' ' &&
                  _collapsibleEdge(base, leading: false)) {
                _unsupported(group.rootPath);
              }
              if (_collapsibleEdge(base, leading: true)) {
                sources.add(appendPlain(_window(base, 0, 1)));
                base = _window(base, 1, base.projection.text.length);
              }
              if (_collapsibleEdge(base, leading: false)) {
                final end = base.projection.text.length;
                trailing = _window(base, end - 1, end);
                base = _window(base, 0, end - 1);
              }
            }
            appendColumn(
              base,
              column < annotations.length
                  ? annotations[column]
                  : (anonymous ??= _anonymousBase(group)),
              sources,
              annotationIndices,
              levelId,
            );
            column++;
            if (trailing != null) {
              if (column == unitCount) {
                deferredTail = (content: trailing, source: sources);
              } else {
                sources.add(appendPlain(trailing));
              }
            }
          }
          for (; column < annotations.length; column++) {
            appendColumn(
              anonymous ??= _anonymousBase(group),
              annotations[column],
              const [],
              annotationIndices,
              levelId,
            );
          }
          if (deferredTail != null) {
            deferredTail.source.add(appendPlain(deferredTail.content));
          }
          // Columns display base/RT pairs, but original bases (and gaps) all
          // precede RTs. Preserve that explicit order without rewriting source.
          sourceOrder.addAll(baseSources.expand((sources) => sources));
          sourceOrder.addAll(annotationIndices);
      }
    }
    // Empty trailing source contexts must not keep a previous collapsed space
    // alive. Only a final ordinary context is eligible; atomic children are not.
    trimTrailingPlain();
    final content = ForumBodyInlineSpanContent.compose(
      identity: input.identity,
      path: input.path,
      fontRevision: input.fontRevision,
      styleRevision: input.styleRevision,
      style: input.style,
      contexts: contexts,
      atomicRanges: atoms,
      sourceOrder: sourceOrder,
    );
    final glyphContexts = Set<ForumBodyParagraphContent>.identity();
    for (final pair in pairs) {
      glyphContexts.add(pair.base);
      if (pair.annotation.projection.text.isNotEmpty) {
        glyphContexts.add(pair.annotation);
      }
    }
    final requests = _requests([
      // Batch children in the same explicit ORIGINAL source order as the parent
      // projection, not their reordered display columns. Never sort or rebase.
      for (final index in sourceOrder)
        if (glyphContexts.contains(contexts[index])) contexts[index],
      for (final pair in pairs)
        if (pair.base.isSourceFree) pair.base,
    ]);
    return ForumBodyInlinePlanInput._(
      content,
      [
        for (final pair in pairs)
          ForumBodyRubyPairRequest(
            base: requests[pair.base]!,
            annotation:
                requests[pair.annotation] ??
                ForumBodyTextRequest.paragraph(pair.annotation),
            maxWidth: width,
          ),
      ],
      width,
      levelIds,
    );
  }

  final ForumBodyInlineSpanContent content;
  final double width;
  final List<int> rubyLevelIds;
  final List<int> atomEngineOffsets;
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

ForumBodyParagraphContent _anonymousBase(ForumBodyRubyGroupContent group) =>
    ForumBodyParagraphContent.anonymousInline(
      identity: group.identity,
      fontRevision: group.fontRevision,
      styleRevision: group.styleRevision,
      style: group.style,
    );

ForumBodyParagraphContent _annotationInput(
  ForumBodyRubyAnnotationContent annotation,
) {
  final parts = annotation.parts;
  if (parts.length != 1 || parts.single is! ForumBodyRubyTextContent) {
    _unsupported(annotation.path);
  }
  return _plainContext(
    (parts.single as ForumBodyRubyTextContent).content,
    leading: true,
    trailing: true,
  );
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
  return _window(context, start, end);
}

ForumBodyParagraphContent _window(
  ForumBodyParagraphContent context,
  int start,
  int end,
) {
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
    if (context.isSourceFree) {
      // Empty font struts use a shared ordinary cached layout. They carry no
      // displayed source and must not split the surrounding annotation bands.
      result[context] = ForumBodyTextRequest.paragraph(context);
      continue;
    }
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
