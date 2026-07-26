import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_message_revision_tracker.dart';

void main() {
  test('adjusts an anchor when text is inserted before it', () {
    final tracker = ComposerMessageRevisionTracker(initialSource: 'abcd');
    final anchor = const ComposerInsertionAnchor(
      baseRevision: 0,
      selection: ComposerSelection(start: 2, end: 2),
      mode: ComposerEditorMode.source,
    );

    tracker.recordChange(previousSource: 'abcd', nextSource: 'aXYbcd');

    expect(
      tracker.resolve(anchor)?.selection,
      const ComposerSelection(start: 4, end: 4),
    );
  });

  test('does not move a collapsed anchor when typing at the same offset', () {
    final tracker = ComposerMessageRevisionTracker(initialSource: 'abcd');
    final anchor = const ComposerInsertionAnchor(
      baseRevision: 0,
      selection: ComposerSelection(start: 2, end: 2),
      mode: ComposerEditorMode.source,
    );

    tracker.recordChange(previousSource: 'abcd', nextSource: 'abXYcd');

    expect(
      tracker.resolve(anchor)?.selection,
      const ComposerSelection(start: 2, end: 2),
    );
  });

  test('keeps an anchor unchanged when editing after it', () {
    final tracker = ComposerMessageRevisionTracker(initialSource: 'abcd');
    const anchor = ComposerInsertionAnchor(
      baseRevision: 0,
      selection: ComposerSelection(start: 1, end: 1),
      mode: ComposerEditorMode.quill,
    );

    tracker.recordChange(previousSource: 'abcd', nextSource: 'abcdXY');

    expect(
      tracker.resolve(anchor)?.selection,
      const ComposerSelection(start: 1, end: 1),
    );
  });

  test('invalidates an anchor when an edit overlaps it', () {
    final tracker = ComposerMessageRevisionTracker(initialSource: 'abcdef');
    const anchor = ComposerInsertionAnchor(
      baseRevision: 0,
      selection: ComposerSelection(start: 2, end: 4),
      mode: ComposerEditorMode.source,
    );

    tracker.recordChange(previousSource: 'abcdef', nextSource: 'abXYef');

    expect(tracker.resolve(anchor), isNull);
  });

  test('applies multiple independent changes in order', () {
    final tracker = ComposerMessageRevisionTracker(initialSource: 'abcdef');
    const anchor = ComposerInsertionAnchor(
      baseRevision: 0,
      selection: ComposerSelection(start: 5, end: 5),
      mode: ComposerEditorMode.source,
    );

    tracker.recordChange(previousSource: 'abcdef', nextSource: 'aXbcdef');
    tracker.recordChange(previousSource: 'aXbcdef', nextSource: 'aXbYcdef');

    expect(
      tracker.resolve(anchor)?.selection,
      const ComposerSelection(start: 7, end: 7),
    );
  });
}
