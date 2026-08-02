import 'package:y300/features/composer_shared/domain/models/composer_collapse_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_collapse_bbcode_grammar.dart';

final class ComposerCollapseSerializer {
  const ComposerCollapseSerializer({
    this.grammar = const ComposerCollapseBbCodeGrammar(),
  });

  final ComposerCollapseBbCodeGrammar grammar;

  String serializeBlock({
    required String title,
    required String bodyBbCode,
    ComposerCollapseMode mode = ComposerCollapseMode.collapsed,
    String? rawOpeningLine,
    String? rawClosing,
  }) {
    final openingLine = _validatedOpeningLine(
      rawOpeningLine,
      title: title,
      mode: mode,
    );
    final closing = _validatedClosing(rawClosing);
    return '${openingLine ?? '[collapse=${mode.wireValue},$title]\n'}'
        '$bodyBbCode${closing ?? '[/collapse]'}';
  }

  String serialize(ComposerCollapseDocument document) {
    final buffer = StringBuffer();
    var atLineStart = true;
    for (final part in document.parts) {
      switch (part) {
        case ComposerCollapseText(:final value):
          buffer.write(value);
          if (value.isNotEmpty) {
            atLineStart = value.endsWith('\n');
          }
        case ComposerCollapseBlock(
          :final title,
          :final body,
          :final mode,
          :final rawOpeningLine,
          :final rawClosing,
        ):
          if (!atLineStart) {
            buffer.write('\n');
          }
          final serialized = serializeBlock(
            title: title,
            bodyBbCode: serialize(body),
            mode: mode,
            rawOpeningLine: rawOpeningLine,
            rawClosing: rawClosing,
          );
          buffer.write(serialized);
          atLineStart = serialized.endsWith('\n');
      }
    }
    return buffer.toString();
  }

  String? _validatedOpeningLine(
    String? source, {
    required String title,
    required ComposerCollapseMode mode,
  }) {
    if (source == null) {
      return null;
    }
    final token = grammar.openingAt(source, 0);
    if (token == null ||
        token.bodyStart != source.length ||
        token.title != title ||
        token.mode != mode) {
      return null;
    }
    return source;
  }

  String? _validatedClosing(String? source) {
    if (source == null) {
      return null;
    }
    final token = grammar.closingAt(source, 0);
    return token != null && token.end == source.length ? source : null;
  }
}
