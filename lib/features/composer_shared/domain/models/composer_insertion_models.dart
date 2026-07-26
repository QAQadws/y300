/// The editor surface that captured an insertion anchor.
enum ComposerEditorMode { source, quill }

typedef ComposerImageInsertCallback =
    Future<void> Function(ComposerInsertionAnchor? anchor);

/// A text selection expressed in Dart/Flutter UTF-16 code-unit offsets.
class ComposerSelection {
  const ComposerSelection({required this.start, required this.end});

  final int start;
  final int end;

  bool get isCollapsed => start == end;

  ComposerSelection normalized(int textLength) {
    final normalizedStart = start.clamp(0, textLength).toInt();
    final normalizedEnd = end.clamp(0, textLength).toInt();
    if (normalizedStart <= normalizedEnd) {
      return ComposerSelection(start: normalizedStart, end: normalizedEnd);
    }
    return ComposerSelection(start: normalizedEnd, end: normalizedStart);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ComposerSelection && other.start == start && other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ComposerSelection($start, $end)';
}

/// A selection captured before an asynchronous image picker/upload flow.
class ComposerInsertionAnchor {
  const ComposerInsertionAnchor({
    required this.baseRevision,
    required this.selection,
    required this.mode,
  });

  final int baseRevision;
  final ComposerSelection selection;
  final ComposerEditorMode mode;
}

/// The result of inserting one or more attachment blocks into raw BBCode.
class ComposerTextMutation {
  const ComposerTextMutation({
    required this.previousSource,
    required this.nextSource,
    required this.replacedSelection,
    required this.resultSelection,
    required this.revision,
  });

  final String previousSource;
  final String nextSource;
  final ComposerSelection replacedSelection;
  final ComposerSelection resultSelection;
  final int revision;
}
