import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';

final class ComposerQuillCollapseHandle {
  const ComposerQuillCollapseHandle({
    required this.id,
    required this.title,
    required this.body,
    required this.rawOpeningLine,
    required this.rawClosing,
  });

  factory ComposerQuillCollapseHandle.fromPayload(Map<String, Object?> value) {
    return ComposerQuillCollapseHandle(
      id: value['id']!.toString(),
      title: value['title']!.toString(),
      body: value['body']!.toString(),
      rawOpeningLine: value['rawOpeningLine'] as String?,
      rawClosing: value['rawClosing'] as String?,
    );
  }

  final String id;
  final String title;
  final String body;
  final String? rawOpeningLine;
  final String? rawClosing;

  bool matches(Map<String, Object?> payload) {
    return payload['id']?.toString() == id &&
        payload['title']?.toString() == title &&
        payload['body']?.toString() == body &&
        payload['rawOpeningLine'] == rawOpeningLine &&
        payload['rawClosing'] == rawClosing;
  }
}

/// Inserts a collapse embed as a Quill block instead of an inline widget span.
///
/// Flutter Quill only gives an expanded embed block layout when the embed is
/// the sole child of its line. The service therefore adds structural line
/// breaks only where the surrounding document does not already provide them.
final class ComposerQuillCollapseInsertionService {
  const ComposerQuillCollapseInsertionService();

  bool replace({
    required QuillController controller,
    required ComposerQuillCollapseHandle expected,
    required Embeddable replacement,
  }) {
    final offset = _matchingOffset(controller.document, expected);
    if (offset == null) {
      return false;
    }
    controller.replaceText(
      offset,
      1,
      replacement,
      TextSelection.collapsed(offset: offset + 1),
    );
    return true;
  }

  bool delete({
    required QuillController controller,
    required ComposerQuillCollapseHandle expected,
  }) {
    final offset = _matchingOffset(controller.document, expected);
    if (offset == null) {
      return false;
    }
    final query = controller.document.queryChild(offset);
    final line = query.node;
    var deleteOffset = offset;
    var deleteLength = 1;
    if (line is Line &&
        line.childCount == 1 &&
        line.length < controller.document.length) {
      deleteOffset = line.documentOffset;
      deleteLength = line.length;
    }
    final nextOffset = deleteOffset
        .clamp(
          0,
          (controller.document.length - deleteLength - 1)
              .clamp(0, controller.document.length)
              .toInt(),
        )
        .toInt();
    controller.replaceText(
      deleteOffset,
      deleteLength,
      '',
      TextSelection.collapsed(offset: nextOffset),
    );
    return true;
  }

  TextSelection insert({
    required QuillController controller,
    required TextSelection selection,
    required Embeddable embed,
    required bool replaceSelection,
  }) {
    final document = controller.document;
    final editableEnd = (document.length - 1).clamp(0, document.length).toInt();
    final normalized = selection.copyWith(
      baseOffset: selection.baseOffset.clamp(0, editableEnd).toInt(),
      extentOffset: selection.extentOffset.clamp(0, editableEnd).toInt(),
    );
    final index = normalized.start;
    final replacedLength = replaceSelection
        ? normalized.end - normalized.start
        : 0;
    final plainText = document.toPlainText();
    final rightIndex = (index + replacedLength).clamp(0, plainText.length);
    final needsLeadingBreak =
        index > 0 && _characterAt(plainText, index - 1) != '\n';
    final rightCharacter = _characterAt(plainText, rightIndex);
    final needsTrailingBreak = rightCharacter != null && rightCharacter != '\n';

    final replacement = Delta();
    if (needsLeadingBreak) {
      replacement.insert('\n');
    }
    replacement.insert(embed.toJson());
    if (needsTrailingBreak) {
      replacement.insert('\n');
    }

    controller.replaceText(index, replacedLength, replacement, null);

    final insertedLength =
        (needsLeadingBreak ? 1 : 0) + 1 + (needsTrailingBreak ? 1 : 0);
    // If the right-hand newline already existed, move across it when possible
    // so returning to the parent editor starts after the collapse block.
    final existingBreakLength = !needsTrailingBreak && rightCharacter == '\n'
        ? 1
        : 0;
    final nextEditableEnd = (controller.document.length - 1)
        .clamp(0, controller.document.length)
        .toInt();
    final nextSelection = TextSelection.collapsed(
      offset: (index + insertedLength + existingBreakLength)
          .clamp(0, nextEditableEnd)
          .toInt(),
    );
    controller.updateSelection(nextSelection, ChangeSource.local);
    return nextSelection;
  }

  String? _characterAt(String source, int index) {
    if (index < 0 || index >= source.length) {
      return null;
    }
    return source[index];
  }

  int? _matchingOffset(
    Document document,
    ComposerQuillCollapseHandle expected,
  ) {
    var offset = 0;
    for (final operation in document.toDelta().toList()) {
      final data = operation.data;
      if (data is! String) {
        final payload = composerQuillCollapseEmbedPayload(data);
        if (payload != null && expected.matches(payload)) {
          return offset;
        }
      }
      offset += data is String ? data.length : 1;
    }
    return null;
  }
}
