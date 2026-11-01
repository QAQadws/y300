import '../flow/forum_body_inline_flow_content.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_ruby_column_request.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_atom_request.dart';
import 'forum_body_ruby_segment_request.dart';
import 'forum_body_ruby_soft_space_request.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_inline_span_content.dart';
import 'forum_body_ruby_annotation_input.dart';
import 'forum_body_ruby_annotation_pairing.dart';
import 'forum_body_ruby_base_input.dart';
import 'forum_body_ruby_content.dart';
import 'forum_body_ruby_whitespace.dart';
import 'forum_body_text_band_content.dart';

/// Pure source-bound parent input and child requests for the session's pending
/// format. No native resource, owner or scheduler is retained here.
final class ForumBodyInlinePlanInput {
  ForumBodyInlinePlanInput._(
    this.content,
    this.atoms,
    this.width,
    List<int> levelIds,
  ) : rubyLevelIds = List.unmodifiable(levelIds),
      atomEngineOffsets = List.unmodifiable(
        content
            .projectionForLayout(ForumBodyParagraphLayoutMode.wrap)
            .atoms
            .map((atom) => atom.engineUtf16),
      );
  static const revision = 20;

  factory ForumBodyInlinePlanInput(
    ForumBodyInlineFlowContent input,
    double width,
  ) {
    if (input.layoutMode != ForumBodyParagraphLayoutMode.wrap) {
      _unsupported(input.path);
    }
    final contexts = <ForumBodyParagraphContent>[];
    final sourceOrder = <int>[];
    final requestsByAtom = <ForumBodyRubyAtomRequest>[];
    final atoms = <({int startUtf16, int endUtf16})>[];
    Set<int>? softSpaceAtoms;
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
      List<({ForumBodyParagraphContent content, ForumBodyRubySide side})>
      annotations,
      List<int> baseIndices,
      List<List<int>> annotationIndices,
      int levelId, {
      int columnIndex = 0,
      Map<(int, int), List<ForumBodyParagraphContent>>? gapFences,
      ForumBodyRubyContainerBackground? background,
    }) {
      if (base.projection.text.isEmpty &&
          annotations.every((item) => item.content.projection.text.isEmpty)) {
        _unsupported(base.path);
      }
      final start = offset;
      if (!base.isSourceFree) baseIndices.add(append(base));
      for (final (rank, annotation) in annotations.indexed) {
        for (final fence
            in gapFences?[(rank, columnIndex)] ??
                const <ForumBodyParagraphContent>[]) {
          annotationIndices[rank].add(append(fence));
        }
        if (!annotation.content.isSourceFree) {
          annotationIndices[rank].add(append(annotation.content));
        }
      }
      atoms.add((startUtf16: start, endUtf16: offset));
      requestsByAtom.add(
        ForumBodyRubyAtomRequest.column(
          ForumBodyRubyColumnRequest.layers(
            base: ForumBodyTextRequest.paragraph(base),
            annotations: [
              for (final a in annotations)
                (
                  request: ForumBodyTextRequest.paragraph(a.content),
                  gap: 0.0,
                  side: a.side,
                ),
            ],
            maxWidth: width,
            background: background,
          ),
        ),
      );
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
          final background = ForumBodyRubyContainerBackground.fromGroup(group);
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
          final unitCount = bases
              .where((base) => base.kind != ForumBodyRubyBaseInputKind.gap)
              .length;
          final pairing = ForumBodyRubyAnnotationPairing(
            group: group,
            baseColumnCount: unitCount,
          );
          Map<ForumBodyParagraphContent, ForumBodyParagraphContent>?
          resolvedGaps;
          for (final level in pairing.levels) {
            for (final gap in level.gaps) {
              if (!gap.content.projection.hasCollapsibleSegmentBreaks) continue;
              final resolved = resolveForumBodyRubyGapWhitespace(
                gap: gap.content,
                previous: _annotationInput(group, gap.previous.box),
                next: _annotationInput(group, gap.next.box),
              );
              if (!identical(resolved, gap.content)) {
                (resolvedGaps ??= Map.identity())[gap.content] = resolved;
              }
            }
          }
          ForumBodyParagraphContent gapContent(
            ForumBodyRubyPairedAnnotationGap gap,
          ) => resolvedGaps?[gap.content] ?? gap.content;
          // Only a real visible spanning annotation already closes all current
          // columns. A whitespace edge by itself must remain breakable; its
          // parent trimming/break protocol is not implied by segment geometry.
          final hasUnbrokenAnnotation =
              pairing.hasMultiColumnSpans &&
              pairing.levels.any(
                (l) => l.spans.any(
                  (span) =>
                      span.isMultiColumn &&
                      _annotationInput(
                        group,
                        span.box,
                      ).projection.text.isNotEmpty,
                ),
              );
          if (hasUnbrokenAnnotation) {
            // Current anonymous-box pairing spans the complete original group.
            // Its interior column edges cannot become independent parent atoms.
            final segmentBases = <ForumBodyParagraphContent>[];
            final baseSources = [for (final _ in bases) <int>[]];
            final annotationSources = <int>[];
            final gaps = <ForumBodyRubyGapRequest>[];
            final annotationGaps = <ForumBodyRubyAnnotationGapRequest>[];
            ForumBodyParagraphContent? tail;
            List<int>? tailSource;
            var column = 0;
            for (final (index, unit) in bases.indexed) {
              final sources = baseSources[index];
              var base = unit.content;
              if (unit.kind == ForumBodyRubyBaseInputKind.gap) {
                // Internal source windows are appended with their neighbouring
                // bases below; edge indentation remains a structural omission.
                if (column != 0 && column != unitCount) continue;
                final end = base.projection.text.length;
                sources.add(append(_window(base, end, end)));
                continue;
              }
              if (unit.kind == ForumBodyRubyBaseInputKind.implicit) {
                if (_collapsibleEdge(base, leading: true)) {
                  if (column != 0) _unsupported(group.rootPath);
                  sources.add(appendPlain(_window(base, 0, 1)));
                  base = _window(base, 1, base.projection.text.length);
                }
                if (_collapsibleEdge(base, leading: false)) {
                  if (column + 1 != unitCount) _unsupported(group.rootPath);
                  final end = base.projection.text.length;
                  tail = _window(base, end - 1, end);
                  tailSource = sources;
                  base = _window(base, 0, end - 1);
                }
              }
              segmentBases.add(base);
              column++;
            }
            while (segmentBases.length < pairing.columnCount) {
              segmentBases.add(_anonymousBase(group));
            }
            final start = offset;
            var sourceColumn = 0;
            for (final (index, unit) in bases.indexed) {
              if (unit.kind == ForumBodyRubyBaseInputKind.gap) {
                if (sourceColumn > 0 &&
                    sourceColumn < unitCount &&
                    unit.content.projection.text.isNotEmpty) {
                  baseSources[index].add(append(unit.content));
                  gaps.add((
                    beforeColumn: sourceColumn,
                    request: ForumBodyTextRequest.paragraph(unit.content),
                  ));
                }
                continue;
              }
              final base = segmentBases[sourceColumn++];
              if (!base.isSourceFree) baseSources[index].add(append(base));
            }
            final spans = <ForumBodyRubySpanRequest>[];
            for (final (rank, level) in pairing.levels.indexed) {
              var gapIndex = 0;
              for (final span in level.spans) {
                while (gapIndex < level.gaps.length &&
                    identical(level.gaps[gapIndex].next, span)) {
                  final gap = level.gaps[gapIndex++];
                  final content = gapContent(gap);
                  annotationSources.add(append(content));
                  if (content.projection.text.isNotEmpty) {
                    annotationGaps.add((
                      beforeSpanIndex: spans.length,
                      request: ForumBodyTextRequest.paragraph(content),
                      gap: 0.0,
                    ));
                  }
                }
                if (span.isMultiColumn &&
                    (span.startColumn != 0 ||
                        span.endColumn != pairing.columnCount)) {
                  _unsupported(group.rootPath);
                }
                final annotation = _annotationInput(group, span.box);
                if (!annotation.isSourceFree) {
                  annotationSources.add(append(annotation));
                }
                spans.add((
                  request: ForumBodyTextRequest.paragraph(annotation),
                  startColumn: span.startColumn,
                  endColumn: span.endColumn,
                  annotationIndex: rank,
                  gap: 0.0,
                ));
              }
            }
            atoms.add((startUtf16: start, endUtf16: offset));
            requestsByAtom.add(
              ForumBodyRubyAtomRequest.segment(
                ForumBodyRubySegmentRequest(
                  background: background,
                  bases: [
                    for (final base in segmentBases)
                      ForumBodyTextRequest.paragraph(base),
                  ],
                  sides: [for (final level in pairing.levels) level.side],
                  spans: spans,
                  gaps: gaps,
                  annotationGaps: annotationGaps,
                  direction: group.style.textDirection,
                  maxWidth: width,
                ),
              ),
            );
            levelIds.add(levelId);
            previousCollapsibleSpace = false;
            atLineStart = false;
            lastPlain = null;
            if (tail != null) tailSource!.add(appendPlain(tail));
            sourceOrder.addAll(baseSources.expand((sources) => sources));
            sourceOrder.addAll(annotationSources);
            continue;
          }
          final levels = pairing.levels;
          final annotationCount = pairing.annotatedColumnCount;
          if (bases.isEmpty && annotationCount == 0) {
            _unsupported(group.rootPath);
          }
          final annotations = [
            for (final level in levels)
              [
                for (final span in level.spans)
                  _annotationInput(group, span.box),
              ],
          ];
          final baseSources = [for (final _ in bases) <int>[]];
          final annotationIndices = [for (final _ in levels) <int>[]];
          Map<(int, int), List<ForumBodyParagraphContent>>? gapFences;
          Set<int>? softEdges;
          for (final (rank, level) in levels.indexed) {
            for (final gap in level.gaps) {
              final content = gapContent(gap);
              if (content.projection.text.isNotEmpty) {
                if (!_isCollapsibleGap(content)) _unsupported(content.path);
                (softEdges ??= {}).add(gap.beforeColumn);
              }
              ((gapFences ??= {})[(rank, gap.beforeColumn)] ??= []).add(
                content,
              );
            }
          }
          Map<
            int,
            List<({ForumBodyParagraphContent content, List<int> source})>
          >?
          pendingBaseGaps;
          void appendBaseSpace(
            ForumBodyParagraphContent content,
            List<int> sources,
            int edge,
          ) {
            if (softEdges?.contains(edge) ?? false) {
              if (content.projection.text.isNotEmpty &&
                  !_isCollapsibleGap(content)) {
                _unsupported(content.path);
              }
              ((pendingBaseGaps ??= {})[edge] ??= []).add((
                content: content,
                source: sources,
              ));
            } else {
              sources.add(appendPlain(content));
            }
          }
          var emittedEdges = 0;
          void appendEdge(int edge) {
            if (!(softEdges?.contains(edge) ?? false)) return;
            final start = offset;
            final members = <ForumBodyRubySoftSpaceMemberRequest>[];
            for (final gap
                in pendingBaseGaps?.remove(edge) ??
                    const <
                      ({ForumBodyParagraphContent content, List<int> source})
                    >[]) {
              gap.source.add(append(gap.content));
              if (gap.content.projection.text.isNotEmpty) {
                members.add((
                  request: ForumBodyTextRequest.paragraph(gap.content),
                  annotationIndex: null,
                  gap: 0.0,
                ));
              }
            }
            for (var rank = 0; rank < levels.length; rank++) {
              for (final content
                  in gapFences?[(rank, edge)] ??
                      const <ForumBodyParagraphContent>[]) {
                // Empty transformed LF contexts remain original source fences,
                // never another native member or an invented opposite font.
                annotationIndices[rank].add(append(content));
                if (content.projection.text.isNotEmpty) {
                  members.add((
                    request: ForumBodyTextRequest.paragraph(content),
                    annotationIndex: rank,
                    gap: 0.0,
                  ));
                }
              }
            }
            (softSpaceAtoms ??= {}).add(atoms.length);
            atoms.add((startUtf16: start, endUtf16: offset));
            requestsByAtom.add(
              ForumBodyRubyAtomRequest.softSpace(
                ForumBodyRubySoftSpaceRequest(
                  background: background,
                  beforeColumn: edge,
                  members: members,
                  sides: [for (final level in levels) level.side],
                  direction: group.style.textDirection,
                ),
              ),
            );
            levelIds.add(levelId);
            emittedEdges++;
          }
          var column = 0;
          ForumBodyParagraphContent? anonymous;
          List<({ForumBodyParagraphContent content, ForumBodyRubySide side})>
          annotationsAt(int column) => [
            for (final (rank, level) in levels.indexed)
              (
                content: column < annotations[rank].length
                    ? annotations[rank][column]
                    : (anonymous ??= _anonymousBase(group)),
                side: level.side,
              ),
          ];
          ({ForumBodyParagraphContent content, List<int> source})? deferredTail;
          for (final (index, unit) in bases.indexed) {
            final sources = baseSources[index];
            var base = unit.content;
            if (unit.kind == ForumBodyRubyBaseInputKind.gap) {
              // Structural edge indentation is omitted; inter-base whitespace
              // uses the actual parent's text layout, without consuming an RT.
              final end = base.projection.text.length;
              if (column == 0 || column == unitCount) {
                sources.add(append(_window(base, end, end)));
              } else {
                appendBaseSpace(base, sources, column);
              }
              continue;
            }
            if (column >= annotationCount &&
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
                appendBaseSpace(_window(base, 0, 1), sources, column);
                base = _window(base, 1, base.projection.text.length);
              }
              if (_collapsibleEdge(base, leading: false)) {
                final end = base.projection.text.length;
                trailing = _window(base, end - 1, end);
                base = _window(base, 0, end - 1);
              }
            }
            appendEdge(column);
            appendColumn(
              base,
              annotationsAt(column),
              sources,
              annotationIndices,
              levelId,
              columnIndex: column,
              background: background,
              gapFences: (softEdges?.contains(column) ?? false)
                  ? null
                  : gapFences,
            );
            column++;
            if (trailing != null) {
              if (column == unitCount) {
                deferredTail = (content: trailing, source: sources);
              } else {
                appendBaseSpace(trailing, sources, column);
              }
            }
          }
          for (; column < annotationCount; column++) {
            appendEdge(column);
            appendColumn(
              anonymous ??= _anonymousBase(group),
              annotationsAt(column),
              const [],
              annotationIndices,
              levelId,
              columnIndex: column,
              background: background,
              gapFences: (softEdges?.contains(column) ?? false)
                  ? null
                  : gapFences,
            );
          }
          if (emittedEdges != (softEdges?.length ?? 0) ||
              (pendingBaseGaps?.isNotEmpty ?? false)) {
            _unsupported(group.rootPath);
          }
          if (deferredTail != null) {
            deferredTail.source.add(appendPlain(deferredTail.content));
          }
          // Display is column-major; source is bases/gaps followed by each
          // original level's RTs. Never sort, rebase or flatten these ranges.
          sourceOrder.addAll(baseSources.expand((sources) => sources));
          sourceOrder.addAll(annotationIndices.expand((indices) => indices));
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
      appliesFirstLineIndent: input.appliesFirstLineIndent,
      contexts: contexts,
      atomicRanges: atoms,
      softSpaceAtoms: softSpaceAtoms ?? const {},
      sourceOrder: sourceOrder,
    );
    final glyphContexts = Set<ForumBodyParagraphContent>.identity();
    for (final atom in requestsByAtom) {
      glyphContexts.addAll(atom.nativeRequests.map((r) => r.content));
    }
    final requests = _requests([
      // Batch children in the same explicit ORIGINAL source order as the parent
      // projection, not their reordered display columns. Never sort or rebase.
      for (final index in sourceOrder)
        if (glyphContexts.contains(contexts[index])) contexts[index],
      for (final atom in requestsByAtom)
        for (final request in atom.nativeRequests)
          if (request.content.isSourceFree) request.content,
    ]);
    return ForumBodyInlinePlanInput._(
      content,
      [
        for (final atom in requestsByAtom)
          atom.mapRequests((r) => requests[r.content] ?? r),
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
  final List<ForumBodyRubyAtomRequest> atoms;
  List<ForumBodyRubyColumnRequest> get groups => List.unmodifiable([
    for (final atom in atoms)
      switch (atom) {
        ForumBodyRubyColumnAtomRequest(:final value) => value,
        _ => throw StateError(
          'Inline plan contains a segment, not only columns',
        ),
      },
  ]);

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

    for (var i = 0; i < atoms.length; i++) {
      atoms[i] = atoms[i].mapRequests(replace);
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
  ForumBodyRubyGroupContent group,
  ForumBodyRubyAnnotationBoxInput box,
) {
  if (box is ForumBodyRubyAnonymousAnnotationInput) {
    return _plainContext(box.content, leading: true, trailing: true);
  }
  final annotation = (box as ForumBodyRubyExplicitAnnotationInput).annotation;
  final parts = annotation.parts;
  if (parts.isEmpty) {
    return ForumBodyParagraphContent.anonymousInline(
      identity: group.identity,
      fontRevision: group.fontRevision,
      styleRevision: group.styleRevision,
      style: annotation.style,
    );
  }
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

bool _isCollapsibleGap(ForumBodyParagraphContent context) =>
    context.projection.text.isNotEmpty &&
    context.projection.text.runes.every((r) => r == 9 || r == 32) &&
    context.projection.parts.every((part) {
      final mode = context.runs[part.runIndex].style.whiteSpace;
      return mode == ForumBodyWhiteSpace.normal ||
          mode == ForumBodyWhiteSpace.preLine;
    });

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
