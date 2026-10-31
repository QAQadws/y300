import 'dart:convert';

import 'package:html_pagination_core/html_pagination_core.dart';

/// Exact display-input provenance, not a persisted novel semantic anchor.
final class ForumBodyIdentity {
  const ForumBodyIdentity({
    required this.sourceId,
    required this.inputHash,
    required this.conversionIdentity,
    required this.parserRevision,
  });

  final String sourceId;
  final String inputHash;
  final String conversionIdentity;
  final int parserRevision;

  String get cacheIdentity =>
      jsonEncode([sourceId, inputHash, conversionIdentity, parserRevision]);

  @override
  bool operator ==(Object other) =>
      other is ForumBodyIdentity &&
      sourceId == other.sourceId &&
      inputHash == other.inputHash &&
      conversionIdentity == other.conversionIdentity &&
      parserRevision == other.parserRevision;
  @override
  int get hashCode =>
      Object.hash(sourceId, inputHash, conversionIdentity, parserRevision);
}

enum ForumBodyElementKind {
  inline,
  paragraph,
  container,
  heading,
  quote,
  list,
  listItem,
  code,
  hardBreak,
  rule,
  image,
  ruby,
  rubyText,
  rubyFallback,
  table,
  tableSection,
  tableRow,
  tableCell,
  collapse,
  collapseTitle,
  collapseContent,
  editStatus,
  attachment,
  locked,
  media,
  hidden,
  unknown,
}

sealed class ForumBodyNode {
  const ForumBodyNode({required this.path, required this.source});

  /// Child-node path in the repaired fragment. Valid only within [identity]
  /// of the containing document; comments/removed nodes do not renumber it.
  final String path;
  final HtmlSourceTextRange source;
}

final class ForumBodyText extends ForumBodyNode {
  const ForumBodyText({
    required super.path,
    required super.source,
    required this.text,
  });
  final String text;

  /// Raw source coordinate only; legal grapheme/semantic navigation is a
  /// separate projection and must use the containing document identity.
  int sourceRuneAtUtf16(int offset) {
    RangeError.checkValueInInterval(offset, 0, text.length, 'offset');
    return source.runeStart +
        HtmlTextCoordinates.codePointOffsetForUtf16(text, offset);
  }
}

final class ForumBodyDeclaration {
  const ForumBodyDeclaration(this.property, this.value, this.important);
  final String property;
  final String value;
  final bool important;
}

final class ForumBodyAuthorStyle {
  ForumBodyAuthorStyle({
    required Iterable<ForumBodyDeclaration> declarations,
    this.isValid = true,
  }) : declarations = List.unmodifiable(declarations);

  final List<ForumBodyDeclaration> declarations;
  final bool isValid;

  String? value(String property) => effectiveDeclaration({property})?.value;

  /// Includes competing shorthand/longhand names in one source-order cascade.
  ForumBodyDeclaration? effectiveDeclaration(Set<String> properties) {
    ForumBodyDeclaration? result;
    for (final declaration in declarations) {
      if (!properties.contains(declaration.property)) continue;
      if (result?.important == true && !declaration.important) continue;
      result = declaration;
    }
    return result;
  }
}

/// Resource identity stays independent of Host/cache/request implementations.
final class ForumBodyResourceReference {
  const ForumBodyResourceReference({
    required this.rawSource,
    this.readableImageIndex,
    this.attachmentId,
    this.alt,
    this.title,
    this.width,
    this.height,
  });

  final String? rawSource;
  final int? readableImageIndex;
  final String? attachmentId;
  final String? alt;
  final String? title;
  final double? width;
  final double? height;
}

final class ForumBodyElement extends ForumBodyNode {
  ForumBodyElement({
    required super.path,
    required super.source,
    required this.tag,
    required this.kind,
    required this.style,
    required Map<String, String> attributes,
    required Iterable<ForumBodyNode> children,
    this.resource,
  }) : attributes = Map.unmodifiable(attributes),
       children = List.unmodifiable(children);

  final String tag;
  final ForumBodyElementKind kind;
  final Map<String, String> attributes;
  final ForumBodyAuthorStyle style;
  final List<ForumBodyNode> children;
  final ForumBodyResourceReference? resource;
}

enum ForumBodyIssueCode {
  removedActiveContent,
  removedEventAttribute,
  invalidStyle,
  unknownElement,
}

final class ForumBodyIssue {
  const ForumBodyIssue(this.code, this.path);
  final ForumBodyIssueCode code;
  final String path;
}

/// Pure immutable IR. No DOM, native paragraph or Host is retained here.
final class ForumBodyDocument {
  ForumBodyDocument({
    required this.identity,
    required this.sourceMap,
    required Iterable<ForumBodyNode> nodes,
    required Iterable<ForumBodyIssue> issues,
    required this.parsedNodeCount,
    required this.uniqueStyleCount,
  }) : nodes = List.unmodifiable(nodes),
       issues = List.unmodifiable(issues);

  final ForumBodyIdentity identity;
  final List<ForumBodyNode> nodes;
  final HtmlSourceTextMap sourceMap;
  final List<ForumBodyIssue> issues;
  final int parsedNodeCount;
  final int uniqueStyleCount;

  /// Built once on demand; repeated paragraph lookup does not rescan the IR.
  late final Map<String, ForumBodyNode> nodesByPath = Map.unmodifiable({
    for (final node in descendants) node.path: node,
  });

  Iterable<ForumBodyNode> get descendants sync* {
    final stack = <Iterator<ForumBodyNode>>[nodes.iterator];
    while (stack.isNotEmpty) {
      final iterator = stack.last;
      if (!iterator.moveNext()) {
        stack.removeLast();
        continue;
      }
      final node = iterator.current;
      yield node;
      if (node is ForumBodyElement) stack.add(node.children.iterator);
    }
  }

  /// DOM source text, including ruby annotations/hidden content, BR as LF and
  /// textless resources as zero. This is not visible text or novel semantics.
  String get sourceText {
    final text = StringBuffer();
    for (final node in descendants) {
      if (node is ForumBodyText) text.write(node.text);
      if (node is ForumBodyElement &&
          node.kind == ForumBodyElementKind.hardBreak) {
        text.write('\n');
      }
    }
    return text.toString();
  }
}
