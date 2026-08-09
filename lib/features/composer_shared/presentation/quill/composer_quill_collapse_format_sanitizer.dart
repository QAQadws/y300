import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:y300/features/composer_shared/presentation/quill/composer_quill_embeds.dart';

/// Keeps collapse embeds outside every Quill inline and block format.
///
/// The returned delta only clears attributes. It never replaces text or embed
/// payloads, so composing it preserves the active document and selection.
final class ComposerQuillCollapseFormatSanitizer {
  const ComposerQuillCollapseFormatSanitizer();

  Delta? buildSanitization(Document document) {
    final builder = _SanitizationDeltaBuilder();
    var documentOffset = 0;
    var collapseOnCurrentLine = false;

    for (final operation in document.toDelta().toList()) {
      final data = operation.data;
      final attributes = operation.attributes ?? const <String, dynamic>{};

      if (data is! String && composerQuillCollapseEmbedPayload(data) != null) {
        builder.clear(
          offset: documentOffset,
          length: 1,
          keys: _inlineAttributeKeys(attributes),
        );
        collapseOnCurrentLine = true;
        documentOffset += 1;
        continue;
      }

      if (data is String) {
        if (collapseOnCurrentLine) {
          final lineBreak = data.indexOf('\n');
          if (lineBreak >= 0) {
            builder.clear(
              offset: documentOffset + lineBreak,
              length: 1,
              keys: _blockAttributeKeys(attributes),
            );
            collapseOnCurrentLine = false;
          }
        }
        documentOffset += data.length;
        continue;
      }

      documentOffset += 1;
    }

    return builder.finish();
  }

  Iterable<String> _inlineAttributeKeys(Map<String, dynamic> attributes) {
    return attributes.keys.where((key) {
      final attribute = Attribute.fromKeyValue(key, attributes[key]);
      return attribute == null || attribute.scope != AttributeScope.block;
    });
  }

  Iterable<String> _blockAttributeKeys(Map<String, dynamic> attributes) {
    return attributes.keys.where(
      (key) =>
          Attribute.fromKeyValue(key, attributes[key])?.scope ==
          AttributeScope.block,
    );
  }
}

final class _SanitizationDeltaBuilder {
  final Delta _delta = Delta();
  var _cursor = 0;
  var _hasChanges = false;

  void clear({
    required int offset,
    required int length,
    required Iterable<String> keys,
  }) {
    final keyList = keys.toSet().toList(growable: false);
    if (length <= 0 || keyList.isEmpty || offset < _cursor) {
      return;
    }
    if (offset > _cursor) {
      _delta.retain(offset - _cursor);
    }
    _delta.retain(length, <String, dynamic>{
      for (final key in keyList) key: null,
    });
    _cursor = offset + length;
    _hasChanges = true;
  }

  Delta? finish() => _hasChanges ? _delta : null;
}
