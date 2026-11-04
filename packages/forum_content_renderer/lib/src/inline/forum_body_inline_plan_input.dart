import '../flow/forum_body_inline_flow_content.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_geometry.dart';
import '../paragraph/forum_body_text_request.dart';
import 'forum_body_ruby_column_request.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_root_box.dart';
import 'forum_body_ruby_atom_request.dart';
import 'forum_body_ruby_segment_request.dart';
import 'forum_body_ruby_soft_space_request.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_inline_span_content.dart';
import 'forum_body_ruby_annotation_input.dart';
import 'forum_body_ruby_annotation_pairing.dart';
import 'forum_body_ruby_base_input.dart';
import 'forum_body_ruby_content.dart';
import 'forum_body_ruby_child_input.dart';
import 'forum_body_ruby_whitespace.dart';
import 'forum_body_inline_text_window.dart';
import 'forum_body_text_band_content.dart';
import 'forum_body_ruby_tree_input.dart';
import 'forum_body_emphasis_mark.dart';

/// Pure source-bound parent input and child requests for the session's pending
/// format. No native resource, owner or scheduler is retained here.
final class ForumBodyInlinePlanInput {
  ForumBodyInlinePlanInput._(
    this.content,
    this.atoms,
    this.width,
    List<int> levelIds,
    this.layoutMode,
    this.sourceContexts,
    this.retainedTextCodeUnits,
    this.retainedRuns,
  ) : rubyLevelIds = List.unmodifiable(levelIds),
      atomEngineOffsets = List.unmodifiable(
        content
            .projectionForLayout(layoutMode)
            .atoms
            .map((atom) => atom.engineUtf16),
      );
  static const revision = 27;

  factory ForumBodyInlinePlanInput(
    ForumBodyInlineFlowContent input,
    double width, {
    Map<ForumBodyRubyGroupContent, ForumBodyRubyTreeInput> trees = const {},
    Map<ForumBodyRubyGroupContent, ForumBodyRubyGlyphTreeInput> emphasisTrees =
        const {},
  }) {
    if (input.layoutMode == ForumBodyParagraphLayoutMode.fitSingleLine) {
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
    var atLineStart = input.trimCollapsibleEdges;
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
      final trimmed = trimForumBodyInlineText(
        old,
        leading: false,
        trailing: true,
      );
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
      final plain = trimForumBodyInlineText(
        context,
        leading: atLineStart || previousCollapsibleSpace,
        trailing: false,
      );
      final index = append(plain);
      if (plain.projection.text.isNotEmpty) {
        lastPlain = index;
        previousCollapsibleSpace = forumBodyInlineHasCollapsibleEdge(
          plain,
          leading: false,
        );
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
      ForumBodyRubyRootBoxInput? rootBox,
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
            rootBox: rootBox,
          ),
        ),
      );
      levelIds.add(levelId);
      previousCollapsibleSpace = false;
      atLineStart = false;
      lastPlain = null;
    }

    void appendSourceText(ForumBodyParagraphContent context) {
      if (!context.hasBaselineShift || context.projection.text.isEmpty) {
        sourceOrder.add(appendPlain(context));
        return;
      }
      void emitSingle(int start, int end, ForumBodyResolvedStyle style) {
        if (start == end) return;
        if (context.projection.sourceAtUtf16(start).displayUtf16 != start ||
            context.projection.sourceAtUtf16(end).displayUtf16 != end) {
          _unsupported(context.path);
        }
        if (style.baselineShift.isEmpty) {
          sourceOrder.add(
            appendPlain(
              context.displayWindow(startUtf16: start, endUtf16: end),
            ),
          );
          return;
        }
        var window = context.intrinsicDisplayWindow(
          startUtf16: start,
          endUtf16: end,
          style: style.withTextStyle(
            context.style.textStyle.copyWith(
              fontSize: style.textStyle.fontSize,
              height: style.textStyle.height,
            ),
          ),
        );
        if (forumBodyInlineHasCollapsibleEdge(window, leading: true)) {
          sourceOrder.add(appendPlain(windowForumBodyInlineText(window, 0, 1)));
          window = windowForumBodyInlineText(
            window,
            1,
            window.projection.text.length,
          );
        }
        ForumBodyParagraphContent? tail;
        if (window.projection.text.isNotEmpty &&
            forumBodyInlineHasCollapsibleEdge(window, leading: false)) {
          final length = window.projection.text.length;
          tail = windowForumBodyInlineText(window, length - 1, length);
          window = windowForumBodyInlineText(window, 0, length - 1);
        }
        if (window.projection.text.isNotEmpty) {
          final from = offset;
          sourceOrder.add(append(window));
          atoms.add((startUtf16: from, endUtf16: offset));
          requestsByAtom.add(
            ForumBodyTextBaselineAtomRequest(
              ForumBodyTextRequest.paragraph(window),
              style.baselineShift,
              width,
            ),
          );
          levelIds.add(-1);
          previousCollapsibleSpace = false;
          atLineStart = false;
          lastPlain = null;
        }
        if (tail != null) sourceOrder.add(appendPlain(tail));
      }

      void emit(int start, int end, ForumBodyResolvedStyle style) {
        if (style.baselineShift.isEmpty) {
          emitSingle(start, end, style);
          return;
        }
        final text = context.projection.text;
        var from = start;
        for (var i = start; i < end; i++) {
          final unit = text.codeUnitAt(i);
          if (!forumBodyIsDisplayLineBreak(unit) &&
              unit != 0x0d &&
              unit != 0x85) {
            continue;
          }
          emitSingle(from, i, style);
          final next =
              unit == 0x0d && i + 1 < end && text.codeUnitAt(i + 1) == 0x0a
              ? i + 2
              : i + 1;
          sourceOrder.add(
            appendPlain(context.displayWindow(startUtf16: i, endUtf16: next)),
          );
          from = next;
          i = next - 1;
        }
        emitSingle(from, end, style);
      }

      var start = 0, end = 0;
      ForumBodyResolvedStyle? current;
      for (final part in context.projection.parts) {
        final style = context.runs[part.runIndex].style;
        if (current != null &&
            !identical(current.baselineShift, style.baselineShift)) {
          emit(start, end, current);
          start = end;
        }
        current = style;
        end += part.text.length;
      }
      if (current != null) emit(start, end, current);
    }

    for (final part in input.parts) {
      switch (part) {
        case ForumBodyInlineFlowText():
          appendSourceText(part.content);
        case ForumBodyInlineFlowRuby():
          final group = part.group;
          if (!group.style.baselineShift.isEmpty) _unsupported(group.rootPath);
          final levelId = roots.putIfAbsent(group.rootPath, () => roots.length);
          if (group.identity != input.identity ||
              group.fontRevision != input.fontRevision ||
              group.styleRevision != input.styleRevision) {
            throw ForumBodyParagraphInputException(
              ForumBodyParagraphInputFailure.identity,
              group.rootPath,
            );
          }
          final glyphs = emphasisTrees[group];
          final tree = trees[group] ?? glyphs?.sourceTree;
          if (tree != null) {
            if (!identical(tree.rootGroup.group, group) ||
                tree.maxWidth != width ||
                (glyphs != null && !identical(glyphs.sourceTree, tree))) {
              throw ForumBodyParagraphInputException(
                ForumBodyParagraphInputFailure.identity,
                group.rootPath,
              );
            }
            final start = offset;
            for (final source in tree.sources) {
              if (!source.content.isSourceFree) {
                sourceOrder.add(append(source.content));
              }
            }
            if (start == offset) _unsupported(group.rootPath);
            atoms.add((startUtf16: start, endUtf16: offset));
            requestsByAtom.add(
              glyphs == null
                  ? ForumBodyRubyAtomRequest.tree(tree)
                  : ForumBodyRubyAtomRequest.emphasisTree(glyphs),
            );
            levelIds.add(levelId);
            previousCollapsibleSpace = false;
            atLineStart = false;
            lastPlain = null;
            continue;
          }
          final background = ForumBodyRubyContainerBackground.fromGroup(group);
          final rootBox = ForumBodyRubyRootBoxInput.fromGroup(group);
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
                sources.add(append(windowForumBodyInlineText(base, end, end)));
                continue;
              }
              if (unit.kind == ForumBodyRubyBaseInputKind.implicit) {
                if (forumBodyInlineHasCollapsibleEdge(base, leading: true)) {
                  if (column != 0) _unsupported(group.rootPath);
                  sources.add(
                    appendPlain(windowForumBodyInlineText(base, 0, 1)),
                  );
                  base = windowForumBodyInlineText(
                    base,
                    1,
                    base.projection.text.length,
                  );
                }
                if (forumBodyInlineHasCollapsibleEdge(base, leading: false)) {
                  if (column + 1 != unitCount) _unsupported(group.rootPath);
                  final end = base.projection.text.length;
                  tail = windowForumBodyInlineText(base, end - 1, end);
                  tailSource = sources;
                  base = windowForumBodyInlineText(base, 0, end - 1);
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
                  rootBox: rootBox,
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
                  rootBox: rootBox,
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
                sources.add(append(windowForumBodyInlineText(base, end, end)));
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
                  forumBodyInlineHasCollapsibleEdge(base, leading: false)) {
                _unsupported(group.rootPath);
              }
              if (forumBodyInlineHasCollapsibleEdge(base, leading: true)) {
                appendBaseSpace(
                  windowForumBodyInlineText(base, 0, 1),
                  sources,
                  column,
                );
                base = windowForumBodyInlineText(
                  base,
                  1,
                  base.projection.text.length,
                );
              }
              if (forumBodyInlineHasCollapsibleEdge(base, leading: false)) {
                final end = base.projection.text.length;
                trailing = windowForumBodyInlineText(base, end - 1, end);
                base = windowForumBodyInlineText(base, 0, end - 1);
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
              rootBox: rootBox,
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
              rootBox: rootBox,
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
    if (input.trimCollapsibleEdges) trimTrailingPlain();
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
    final derived =
        Map<ForumBodyParagraphContent, ForumBodyParagraphContent>.identity();
    for (final atom in requestsByAtom) {
      glyphContexts.addAll(atom.nativeRequests.map((r) => r.content));
      if (atom is ForumBodyRubyTreeEmphasisAtomRequest) {
        for (final source in atom.value.sources) {
          if (source.needsNative) derived[source.content] = source.glyphs;
        }
      }
    }
    final requests = _requests([
      // Batch children in the same explicit ORIGINAL source order as the parent
      // projection, not their reordered display columns. Never sort or rebase.
      for (final index in sourceOrder)
        if (glyphContexts.contains(derived[contexts[index]] ?? contexts[index]))
          derived[contexts[index]] ?? contexts[index],
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
      input.layoutMode,
      List.unmodifiable([for (final index in sourceOrder) contexts[index]]),
      content.projection.display.text.length +
          requestsByAtom.fold<int>(
            0,
            (sum, atom) => sum + atom.extraTextCodeUnits,
          ),
      content.runs.length +
          requestsByAtom.fold<int>(0, (sum, atom) => sum + atom.extraRuns),
    );
  }

  final ForumBodyInlineSpanContent content;
  final double width;
  final ForumBodyParagraphLayoutMode layoutMode;

  /// Explicit original order, independent of column display order.
  final List<ForumBodyParagraphContent> sourceContexts;
  final int retainedTextCodeUnits;
  final int retainedRuns;
  late final hasEmphasisTrees = atoms.any(
    (atom) => atom is ForumBodyRubyTreeEmphasisAtomRequest,
  );
  Iterable<double> get nativeFontSizes sync* {
    yield content.style.textStyle.fontSize!;
    for (final run in content.runs) {
      yield run.style.textStyle.fontSize!;
    }
    final bands = Set<ForumBodyTextBandContent>.identity();
    for (final atom in atoms) {
      if (atom is ForumBodyTextBaselineAtomRequest) {
        yield* atom.shift.referenceFontSizes;
      }
      if (atom.rootBox case final root?) {
        yield root.fontStrut.style.textStyle.fontSize!;
      }
      if (atom.background case final background?) {
        yield background.fontStrut.style.textStyle.fontSize!;
      }
      for (final request in atom.nativeRequests) {
        final contexts = request is ForumBodyTextBandChildRequest
            ? bands.add(request.band)
                  ? request.band.contexts
                  : const <ForumBodyParagraphContent>[]
            : [request.content];
        for (final context in contexts) {
          yield context.style.textStyle.fontSize!;
          for (final run in context.runs) {
            yield run.style.textStyle.fontSize!;
          }
        }
      }
      final tree = switch (atom) {
        ForumBodyRubyTreeAtomRequest(:final value) => value,
        ForumBodyRubyTreeEmphasisAtomRequest(:final value) => value.sourceTree,
        _ => null,
      };
      if (tree != null) {
        for (final node in tree.nodes) {
          if (node is ForumBodyRubyTreeContainer) {
            yield node.font.fontStrut.style.textStyle.fontSize!;
            if (node.background case final background?) {
              yield background.fontStrut.style.textStyle.fontSize!;
            }
          }
          if (node is ForumBodyRubyTreeInline) {
            yield* node.input.nativeFontSizes;
          }
        }
      }
      if (atom is ForumBodyRubyTreeEmphasisAtomRequest) {
        for (final source in atom.value.sources) {
          // Empty RTs have no glyph request but still contribute actual natural
          // font samples to a containing inline parent's frozen scaler.
          yield source.content.style.textStyle.fontSize!;
          for (final run in source.content.runs) {
            yield run.style.textStyle.fontSize!;
          }
          final emphasis = source.emphasis;
          if (emphasis == null) continue;
          for (final unit in emphasis.units) {
            yield ForumBodyEmphasisMarkInput.resolveFontSize(
              source.content.runs[unit.runIndex].style.textStyle,
            );
          }
        }
      }
    }
  }

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
    return trimForumBodyInlineText(box.content, leading: true, trailing: true);
  }
  final annotation = (box as ForumBodyRubyExplicitAnnotationInput).annotation;
  return trimForumBodyInlineText(
    ForumBodyRubyChildInput.annotation(group, annotation).requireText(),
    leading: true,
    trailing: true,
  );
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
