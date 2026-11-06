import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyRubyGroupContent readAuthoredRuby(
  ForumBodyDocument document,
  ForumBodyReaderStyle reader,
) => readAuthoredRubies(document, reader).first;

List<ForumBodyRubyGroupContent> readAuthoredRubies(
  ForumBodyDocument document,
  ForumBodyReaderStyle reader,
) {
  final flow = ForumBodyStyledFlowCursor(document: document, reader: reader);
  try {
    return _authoredGroups(flow);
  } finally {
    flow.close();
  }
}

ForumBodyInlineFlowContent withAuthoredRuby(
  ForumBodyInlineFlowContent content,
  ForumBodyRubyGroupContent group,
) => withAuthoredRubies(content, [group]);

ForumBodyInlineFlowContent withAuthoredRubies(
  ForumBodyInlineFlowContent content,
  Iterable<ForumBodyRubyGroupContent> groups,
) {
  final byOccurrence = {
    for (final group in groups) (group.rootPath, group.index): group,
  };
  return ForumBodyInlineFlowContent(
    identity: content.identity,
    path: content.path,
    fontRevision: content.fontRevision,
    styleRevision: content.styleRevision,
    style: content.style,
    layoutMode: content.layoutMode,
    appliesFirstLineIndent: content.appliesFirstLineIndent,
    trimCollapsibleEdges: content.trimCollapsibleEdges,
    parts: [
      for (final part in content.parts)
        if (part case ForumBodyInlineFlowRuby(:final group))
          ForumBodyInlineFlowRuby(byOccurrence[(group.rootPath, group.index)]!)
        else
          part,
    ],
    ignored: content.ignored,
    issues: content.issues,
  );
}

/// The low-level layout fixtures can exercise authored levels directly.
/// Reader and PageSession tests go through the readable text flow instead.
ForumBodyRubyGroupContent readUnprojectedRubyGroup(
  ForumBodyStyledFlowCursor flow,
) => _authoredGroups(flow, firstOnly: true).first;

List<ForumBodyRubyGroupContent> _authoredGroups(
  ForumBodyStyledFlowCursor flow, {
  bool firstOnly = false,
}) {
  final groups = <ForumBodyRubyGroupContent>[];
  while (flow.moveNext()) {
    final event = flow.current!;
    if (event.phase != ForumBodyFlowPhase.open ||
        event.node is! ForumBodyElement ||
        (event.node as ForumBodyElement).kind != ForumBodyElementKind.ruby) {
      continue;
    }
    final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
    try {
      while (!cursor.isComplete) {
        if (cursor.advance(maxEvents: 1).hasOutput) {
          groups.add(cursor.current!);
          if (firstOnly) return groups;
        }
      }
    } finally {
      cursor.close();
    }
  }
  return groups;
}
