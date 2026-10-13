import 'package:csslib/parser.dart' as css_parser;
import 'package:csslib/visitor.dart' as css_ast;

final class CssInlineStyleDeclaration {
  const CssInlineStyleDeclaration({
    required this.property,
    required this.value,
    required this.important,
    this.expression,
  });

  final String property;
  final String value;
  final bool important;
  final css_ast.Expression? expression;

  String toCss() {
    return '$property: $value${important ? ' !important' : ''}';
  }
}

final class CssInlineStyleDeclarationList {
  CssInlineStyleDeclarationList(
    Iterable<CssInlineStyleDeclaration> declarations,
  ) : declarations = List<CssInlineStyleDeclaration>.unmodifiable(declarations);

  final List<CssInlineStyleDeclaration> declarations;

  CssInlineStyleDeclaration? effectiveDeclaration(Iterable<String> properties) {
    final targets = properties
        .map((property) => property.toLowerCase())
        .toSet();
    CssInlineStyleDeclaration? selected;
    for (final declaration in declarations) {
      if (!targets.contains(declaration.property)) {
        continue;
      }
      if (selected?.important == true && !declaration.important) {
        continue;
      }
      selected = declaration;
    }
    return selected;
  }

  CssInlineStyleDeclarationList withoutProperties(Iterable<String> properties) {
    final targets = properties
        .map((property) => property.toLowerCase())
        .toSet();
    return CssInlineStyleDeclarationList(
      declarations.where(
        (declaration) => !targets.contains(declaration.property),
      ),
    );
  }

  CssInlineStyleDeclarationList upsert({
    required String property,
    required String value,
    bool important = false,
  }) {
    final normalizedProperty = property.trim().toLowerCase();
    return CssInlineStyleDeclarationList(<CssInlineStyleDeclaration>[
      ...declarations.where(
        (declaration) => declaration.property != normalizedProperty,
      ),
      CssInlineStyleDeclaration(
        property: normalizedProperty,
        value: value.trim(),
        important: important,
      ),
    ]);
  }

  String toCss() {
    return declarations.map((declaration) => declaration.toCss()).join('; ');
  }
}

/// Parses inline declarations by wrapping them in a synthetic csslib rule.
///
/// A syntax error returns null so callers can preserve the original style
/// instead of partially rewriting unrelated declarations.
final class CssInlineStyleDeclarationCodec {
  const CssInlineStyleDeclarationCodec() : _cache = null;

  /// Reuses declarations only within the owning synchronous operation.
  ///
  /// Admission is bounded so a document with unique author styles cannot retain
  /// an additional unbounded set of csslib trees. Consumers treat expressions
  /// as read-only; declaration updates already return new lists.
  CssInlineStyleDeclarationCodec.scoped() : _cache = _InlineStyleParseCache();

  final _InlineStyleParseCache? _cache;

  static const _options = css_parser.PreprocessorOptions(
    checked: false,
    lessSupport: false,
    useColors: false,
    inputFile: 'y300-inline-style',
  );

  CssInlineStyleDeclarationList? tryParse(String style) {
    final cache = _cache;
    if (cache != null && cache.results.containsKey(style)) {
      return cache.results[style];
    }
    final result = _parse(style);
    cache?.remember(style, result);
    return result;
  }

  CssInlineStyleDeclarationList? _parse(String style) {
    if (style.trim().isEmpty) {
      return CssInlineStyleDeclarationList(const <CssInlineStyleDeclaration>[]);
    }
    final errors = <css_parser.Message>[];
    try {
      final source = '.__y300_inline__ { $style }';
      final sheet = css_parser.parse(
        _maskUnsupportedVarFunctions(source),
        errors: errors,
        options: _options,
      );
      if (errors.any(
        (message) => message.level == css_parser.MessageLevel.severe,
      )) {
        return null;
      }
      final rules = sheet.topLevels.whereType<css_ast.RuleSet>().toList();
      if (rules.length != 1) {
        return null;
      }
      final nodes = rules.single.declarationGroup.declarations;
      if (nodes.any((node) => node is! css_ast.Declaration)) {
        return null;
      }
      final result = <CssInlineStyleDeclaration>[];
      for (final node in nodes.whereType<css_ast.Declaration>()) {
        final expression = node.expression;
        if (expression == null) {
          return null;
        }
        final sourceParts = _declarationSourceParts(node, source);
        if (sourceParts == null) {
          return null;
        }
        result.add(
          CssInlineStyleDeclaration(
            property: sourceParts.property,
            value: sourceParts.value,
            important: node.important,
            expression: expression,
          ),
        );
      }
      return CssInlineStyleDeclarationList(result);
    } catch (_) {
      return null;
    }
  }

  String _maskUnsupportedVarFunctions(String source) {
    final lower = source.toLowerCase();
    final chars = source.split('');
    int? quote;
    var escaped = false;
    for (var index = 0; index < source.length; index++) {
      final unit = source.codeUnitAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (unit == 0x5C) {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (unit == quote) {
          quote = null;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27) {
        quote = unit;
        continue;
      }
      if (!lower.startsWith('var(', index) ||
          (index > 0 && _isIdentifierUnit(source.codeUnitAt(index - 1)))) {
        continue;
      }
      final end = _matchingParenthesis(source, index + 3);
      if (end == null) {
        continue;
      }
      for (var masked = index; masked <= end; masked++) {
        chars[masked] = 'x';
      }
      chars[index] = 'r';
      chars[index + 1] = 'e';
      chars[index + 2] = 'd';
      index = end;
    }
    return chars.join();
  }

  int? _matchingParenthesis(String source, int openIndex) {
    var depth = 0;
    int? quote;
    var escaped = false;
    for (var index = openIndex; index < source.length; index++) {
      final unit = source.codeUnitAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (unit == 0x5C) {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (unit == quote) {
          quote = null;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27) {
        quote = unit;
        continue;
      }
      if (unit == 0x28) {
        depth++;
      } else if (unit == 0x29) {
        depth--;
        if (depth == 0) {
          return index;
        }
      }
    }
    return null;
  }

  bool _isIdentifierUnit(int unit) {
    return (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        unit == 0x2D ||
        unit == 0x5F;
  }

  _CssDeclarationSourceParts? _declarationSourceParts(
    css_ast.Declaration declaration,
    String source,
  ) {
    final span = declaration.span;
    final start = span.start.offset;
    final end = span.end.offset;
    if (start < 0 || end > source.length || start >= end) {
      return null;
    }
    final declarationSource = source.substring(start, end);
    final colonIndex = declarationSource.indexOf(':');
    if (colonIndex < 0) {
      return null;
    }
    final property = declarationSource
        .substring(0, colonIndex)
        .trim()
        .toLowerCase();
    var value = declarationSource.substring(colonIndex + 1).trim();
    if (declaration.important) {
      value = value.replaceFirst(
        RegExp(r'\s*!important\s*$', caseSensitive: false),
        '',
      );
    }
    return _CssDeclarationSourceParts(property, value.trim());
  }
}

final class _InlineStyleParseCache {
  static const _maxEntries = 128;
  static const _maxSourceCodeUnits = 64 * 1024;

  final results = <String, CssInlineStyleDeclarationList?>{};
  int _sourceCodeUnits = 0;

  void remember(String style, CssInlineStyleDeclarationList? result) {
    if (results.length >= _maxEntries ||
        _sourceCodeUnits + style.length > _maxSourceCodeUnits) {
      return;
    }
    results[style] = result;
    _sourceCodeUnits += style.length;
  }
}

final class _CssDeclarationSourceParts {
  const _CssDeclarationSourceParts(this.property, this.value);

  final String property;
  final String value;
}
