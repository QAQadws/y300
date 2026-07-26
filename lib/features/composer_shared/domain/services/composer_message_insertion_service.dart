import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';

/// Inserts uploaded attachment codes as a standalone block in raw BBCode.
///
/// This service intentionally knows nothing about Flutter, Quill, upload
/// state, or persistence. Both editor surfaces use its output as the single
/// source of truth for the message mutation.
class ComposerMessageInsertionService {
  const ComposerMessageInsertionService();

  ComposerTextMutation insertAttachmentBlock({
    required String source,
    required ComposerSelection selection,
    required List<String> attachmentCodes,
    required int revision,
  }) {
    final range = selection.normalized(source.length);
    final codes = attachmentCodes
        .where((code) => code.isNotEmpty)
        .toList(growable: false);
    if (codes.isEmpty) {
      return ComposerTextMutation(
        previousSource: source,
        nextSource: source,
        replacedSelection: range,
        resultSelection: ComposerSelection(
          start: range.start,
          end: range.start,
        ),
        revision: revision,
      );
    }

    final left = source.substring(0, range.start);
    final right = source.substring(range.end);
    final block = codes.join('\n');
    final leftSeparator = left.isNotEmpty && !left.endsWith('\n') ? '\n' : '';
    final rightSeparator = right.isEmpty || !right.startsWith('\n') ? '\n' : '';
    final inserted = '$leftSeparator$block$rightSeparator';
    final nextSource = source.replaceRange(range.start, range.end, inserted);

    // When the right side already starts with a newline, that existing
    // newline is the separator after the attachment block. The caret still
    // moves past it to the beginning of the following logical line.
    const separatorLength = 1;
    final resultOffset =
        range.start + leftSeparator.length + block.length + separatorLength;
    return ComposerTextMutation(
      previousSource: source,
      nextSource: nextSource,
      replacedSelection: range,
      resultSelection: ComposerSelection(
        start: resultOffset,
        end: resultOffset,
      ),
      revision: revision,
    );
  }
}
