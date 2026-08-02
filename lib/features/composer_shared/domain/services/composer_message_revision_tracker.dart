import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';

/// Tracks contiguous raw-message edits while an asynchronous insertion is in
/// flight and remaps the original editor selection through those edits.
class ComposerMessageRevisionTracker {
  ComposerMessageRevisionTracker({
    String initialSource = '',
    int initialRevision = 0,
  }) : _source = initialSource,
       _revision = initialRevision;

  String _source;
  int _revision;
  final List<_ComposerMessageEdit> _edits = <_ComposerMessageEdit>[];

  int get revision => _revision;
  String get source => _source;

  void reset({required String source, int revision = 0}) {
    _source = source;
    _revision = revision;
    _edits.clear();
  }

  void recordChange({
    required String previousSource,
    required String nextSource,
  }) {
    if (previousSource == nextSource) {
      return;
    }
    final edit = _ComposerMessageEdit.fromSources(
      baseRevision: _revision,
      previousSource: previousSource,
      nextSource: nextSource,
    );
    _edits.add(edit);
    _source = nextSource;
    _revision += 1;
  }

  /// Returns the anchor remapped to the current revision, or null when any
  /// edit intersects the captured selection.
  ComposerInsertionAnchor? resolve(ComposerInsertionAnchor anchor) {
    // A local editor owns both the revision and the offsets. The captured
    // closure performs its own remap; root-message edits must not reinterpret
    // either value.
    if (anchor.localAttachmentInsertion != null) {
      return anchor;
    }
    if (anchor.baseRevision < 0 || anchor.baseRevision > _revision) {
      return null;
    }
    var selection = anchor.selection;
    for (final edit in _edits) {
      if (edit.baseRevision < anchor.baseRevision) {
        continue;
      }
      final transformed = edit.transform(selection);
      if (transformed == null) {
        return null;
      }
      selection = transformed;
    }
    return ComposerInsertionAnchor(
      baseRevision: _revision,
      selection: selection,
      mode: anchor.mode,
      localAttachmentInsertion: anchor.localAttachmentInsertion,
    );
  }
}

class _ComposerMessageEdit {
  const _ComposerMessageEdit({
    required this.baseRevision,
    required this.start,
    required this.deletedLength,
    required this.insertedLength,
  });

  factory _ComposerMessageEdit.fromSources({
    required int baseRevision,
    required String previousSource,
    required String nextSource,
  }) {
    final maxPrefix = previousSource.length < nextSource.length
        ? previousSource.length
        : nextSource.length;
    var prefix = 0;
    while (prefix < maxPrefix &&
        previousSource.codeUnitAt(prefix) == nextSource.codeUnitAt(prefix)) {
      prefix += 1;
    }

    var previousEnd = previousSource.length;
    var nextEnd = nextSource.length;
    while (previousEnd > prefix &&
        nextEnd > prefix &&
        previousSource.codeUnitAt(previousEnd - 1) ==
            nextSource.codeUnitAt(nextEnd - 1)) {
      previousEnd -= 1;
      nextEnd -= 1;
    }

    return _ComposerMessageEdit(
      baseRevision: baseRevision,
      start: prefix,
      deletedLength: previousEnd - prefix,
      insertedLength: nextEnd - prefix,
    );
  }

  final int baseRevision;
  final int start;
  final int deletedLength;
  final int insertedLength;

  int get end => start + deletedLength;
  int get delta => insertedLength - deletedLength;

  ComposerSelection? transform(ComposerSelection selection) {
    if (selection.isCollapsed) {
      final offset = selection.start;
      if (deletedLength == 0) {
        // Left affinity: typing at the captured offset happens after the
        // anchor, so the attachment remains before that new text.
        return ComposerSelection(
          start: start < offset ? offset + insertedLength : offset,
          end: start < offset ? offset + insertedLength : offset,
        );
      }
      if (end <= offset) {
        final next = offset + delta;
        return ComposerSelection(start: next, end: next);
      }
      return null;
    }

    if (end <= selection.start) {
      return ComposerSelection(
        start: selection.start + delta,
        end: selection.end + delta,
      );
    }
    if (start >= selection.end) {
      return selection;
    }
    return null;
  }
}
