part of 'forum_body_inline_paragraph_view.dart';

// These cursors borrow actual transferred bindings. Every structural member
// yields, including empty ranks. Resource validation/adoption stays with the
// single scene transaction; a yielded pure command grants no source authority.
Iterable<ForumBodyInlinePaintCommand?> _rubyPaintCommands(
  _RubyBinding binding,
  Offset offset,
) sync* {
  yield null;
  switch (binding) {
    case _BaselineTextBinding():
      yield ForumBodyInlinePaintCommand.text(
        binding.text.lease,
        offset + binding.text.metrics.childOffset,
      );
    case _RubyRootFrameBinding():
      yield* _rubyPaintCommands(
        binding.child,
        offset + binding.frame.childOffset,
      );
    case _RubyColumnBinding():
      yield* _groupPaintCommands(binding.group, offset);
    case _RubySegmentBinding():
      final segment = binding.segment, members = segment.inspectMembers();
      for (final (i, column) in members.columns.indexed) {
        yield null;
        segment.inspectMembers();
        yield* _groupPaintCommands(
          column,
          offset + segment.metrics.columnOffsets[i],
        );
      }
      for (final (i, gap) in members.gaps.indexed) {
        yield null;
        segment.inspectMembers();
        yield* _groupPaintCommands(
          gap,
          offset + segment.metrics.gaps[i].offset,
        );
      }
      for (final (i, span) in members.spans.indexed) {
        yield null;
        segment.inspectMembers();
        if (span.lease case final lease?) {
          yield ForumBodyInlinePaintCommand.text(
            lease,
            offset + segment.metrics.spans[i].offset,
          );
        }
      }
      for (final (i, gap) in members.annotationGaps.indexed) {
        yield null;
        segment.inspectMembers();
        yield ForumBodyInlinePaintCommand.text(
          gap.lease!,
          offset + segment.metrics.annotationGaps[i].offset,
        );
      }
      segment.inspectMembers();
    case _RubySpaceBinding():
      final members = binding.space.inspectMembers();
      for (final (i, lease) in members.indexed) {
        yield null;
        binding.space.inspectMembers();
        yield ForumBodyInlinePaintCommand.text(
          lease,
          offset + binding.space.metrics.members[i].offset,
        );
      }
      binding.space.inspectMembers();
    case _RubyTreeBinding():
      yield* binding.tree.paintCommands(offset);
    case _RubyEmphasisTreeBinding():
      yield* binding.tree.paintCommands(offset);
  }
}

Iterable<ForumBodyInlinePaintCommand?> _groupPaintCommands(
  ForumBodyRubyGroupLayout group,
  Offset offset,
) sync* {
  final members = group.inspectMembers();
  yield ForumBodyInlinePaintCommand.text(
    members.base,
    offset + group.baseOffset,
  );
  for (final (i, item) in members.annotations.indexed) {
    yield null;
    group.inspectMembers();
    if (item.lease case final lease?) {
      yield ForumBodyInlinePaintCommand.text(
        lease,
        offset + group.metrics.annotations[i].offset,
      );
    }
  }
  group.inspectMembers();
}
