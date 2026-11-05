part of 'forum_body_inline_plan_input.dart';

extension ForumBodyInlinePlanWindow on ForumBodyInlinePlanInput {
  /// Continue a shaped inline flow at a complete native line boundary. A
  /// resource can share its display fence with other resources, so its engine
  /// slot, not a text offset or URL, decides whether it was consumed.
  ForumBodyInlinePlanInput remainingAt({
    required double width,
    int? engineEndUtf16,
  }) {
    final projection = content.projectionForLayout(layoutMode);
    var engine = engineEndUtf16 ?? projection.enginePrefix.length;
    final cut = projection.displayAtEngineUtf16(engine);
    if (!cut.isExact || engine < projection.enginePrefix.length) {
      _unsupported(content.path);
    }
    var display = cut.displayUtf16;
    // A soft space formerly between two ruby columns no longer has a left
    // neighbor after this break. It is an unpainted leading separator.
    for (final atom in projection.atoms) {
      if (atom.engineUtf16 == engine && atom.isSoftSpace) {
        engine = atom.engineEndUtf16;
        display = atom.displayEndUtf16;
        break;
      }
    }
    final contexts = <ForumBodyParagraphContent>[];
    final positions = Map<ForumBodyParagraphContent, int>.identity();
    for (final context in content.contexts) {
      if (context.endUtf16 <= display) continue;
      positions[context.content] = contexts.length;
      contexts.add(
        context.startUtf16 >= display
            ? context.content
            : windowForumBodyInlineText(
                context.content,
                display - context.startUtf16,
                context.endUtf16 - context.startUtf16,
              ),
      );
    }
    final inset = contexts.isEmpty
        ? 0.0
        : forumBodyHorizontalTextInset([
            content.style,
            for (final context in contexts)
              for (final part in context.projection.parts)
                context.runs[part.runIndex].style,
          ]);
    final available = forumBodyInnerTextWidth(width, inset);
    final ranges = <({int startUtf16, int endUtf16})>[];
    final soft = <int>{};
    final images = <int, ForumBodyInlineImageInput>{};
    final originals = <String, ForumBodyInlineImageInput>{};
    final requests = <ForumBodyRubyAtomRequest>[];
    final levels = <int>[];
    for (final atom in projection.atoms) {
      if (atom.engineEndUtf16 <= engine) continue;
      if (atom.engineUtf16 < engine || atom.displayStartUtf16 < display) {
        _unsupported(content.path);
      }
      final index = ranges.length;
      ranges.add((
        startUtf16: atom.displayStartUtf16 - display,
        endUtf16: atom.displayEndUtf16 - display,
      ));
      if (atom.isSoftSpace) soft.add(index);
      final request = atoms[atom.index];
      if (request is ForumBodyInlineImageAtomRequest) {
        final path = request.input.element.path;
        final original = originals[path] = sourceImages[path] ?? request.input;
        final image = images[index] = original.fitWidth(
          available,
          containingWidth: width,
        );
        requests.add(ForumBodyInlineImageAtomRequest(image));
      } else {
        requests.add(_resizeSourceAtom(request, width));
      }
      levels.add(rubyLevelIds[atom.index]);
    }
    final sourceOrder = [
      for (final context in sourceContexts) ?positions[context],
    ];
    final orderedContexts = [for (final index in sourceOrder) contexts[index]];
    final glyphContexts = Set<ForumBodyParagraphContent>.identity();
    for (final atom in requests) {
      glyphContexts.addAll(
        atom.nativeRequests.map((request) => request.content),
      );
    }
    // A native child band may formerly have included ruby columns from both
    // sides of the cut. Batch only the remaining source contexts again.
    final rebound = _requests([
      for (final context in orderedContexts)
        if (glyphContexts.contains(context)) context,
    ]);
    final parent = ForumBodyInlineSpanContent.compose(
      identity: content.identity,
      path: content.path,
      fontRevision: content.fontRevision,
      styleRevision: content.styleRevision,
      style: content.style,
      appliesFirstLineIndent:
          engineEndUtf16 == null && content.appliesFirstLineIndent,
      contexts: contexts,
      atomicRanges: ranges,
      softSpaceAtoms: soft,
      resourceAtoms: images.keys.toSet(),
      images: images,
      sourceOrder: sourceOrder,
    );
    return ForumBodyInlinePlanInput._(
      parent,
      [
        for (final atom in requests)
          atom.mapRequests((request) => rebound[request.content] ?? request),
      ],
      width,
      levels,
      layoutMode,
      List.unmodifiable(orderedContexts),
      parent.projection.display.text.length +
          requests.fold<int>(
            0,
            (sum, request) => sum + request.extraTextCodeUnits,
          ),
      parent.runs.length +
          requests.fold<int>(0, (sum, request) => sum + request.extraRuns),
      Map.unmodifiable(originals),
    );
  }
}

ForumBodyRubyAtomRequest _resizeSourceAtom(
  ForumBodyRubyAtomRequest request,
  double width,
) => switch (request) {
  ForumBodyRubyColumnAtomRequest(:final value) =>
    ForumBodyRubyAtomRequest.column(
      ForumBodyRubyColumnRequest.layers(
        base: value.base,
        annotations: value.annotations,
        maxWidth: width,
        background: value.background,
        rootBox: value.rootBox,
      ),
    ),
  ForumBodyRubySegmentAtomRequest(:final value) =>
    ForumBodyRubyAtomRequest.segment(
      value.mapRequests((request) => request, availableWidth: width),
    ),
  ForumBodyTextBaselineAtomRequest(:final text, :final shift) =>
    ForumBodyTextBaselineAtomRequest(text, shift, width),
  // Intrinsic groups and existing compound ruby subtrees remain whole and
  // keep their own admitted measurement limits as the parent band widens.
  _ => request,
};
