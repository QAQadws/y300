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
  rubyBase,
  rubyText,
  rubyAnnotationContainer,
  rubyFallback,
  table,
  tableCaption,
  tableColumnGroup,
  tableColumn,
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
    Map<ForumBodyElementKind, int> elementCounts = const {},
    Iterable<ForumBodyElement> imageElements = const [],
    Iterable<ForumBodyElement> collapseElements = const [],
    Iterable<ForumBodyElement> tableElements = const [],
  }) : nodes = List.unmodifiable(nodes),
       issues = List.unmodifiable(issues),
       elementCounts = Map.unmodifiable(elementCounts),
       imageElements = List.unmodifiable(imageElements),
       collapseElements = List.unmodifiable(collapseElements),
       tableElements = List.unmodifiable(tableElements);

  final ForumBodyIdentity identity;
  final List<ForumBodyNode> nodes;
  final HtmlSourceTextMap sourceMap;
  final List<ForumBodyIssue> issues;
  final Map<ForumBodyElementKind, int> elementCounts;

  /// Actual image occurrences in source order, indexed during parsing.
  final List<ForumBodyElement> imageElements;
  final List<ForumBodyElement> collapseElements;

  /// Postorder by repaired child path. Descendant tables are contiguous.
  final List<ForumBodyElement> tableElements;
  final int parsedNodeCount;
  final int uniqueStyleCount;

  Iterable<ForumBodyElement> tablesBelow(ForumBodyElement container) sync* {
    if (tableElements.isEmpty) return;
    final prefix = '${container.path}/';
    final parent = container.path.split('/').map(int.parse).toList();
    var low = 0, high = tableElements.length;
    // Ancestors occur after their descendants in the parser's index. Only
    // paths in a preceding sibling subtree sort before the whole container.
    bool precedes(String path) {
      final child = path.split('/');
      for (var i = 0; i < child.length && i < parent.length; i++) {
        final index = int.parse(child[i]);
        if (index != parent[i]) return index < parent[i];
      }
      return false;
    }

    while (low < high) {
      final middle = (low + high) >> 1;
      if (precedes(tableElements[middle].path)) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    while (low < tableElements.length &&
        tableElements[low].path.startsWith(prefix)) {
      yield tableElements[low++];
    }
  }

  /// Resolves a repaired child-node path without building an index of the whole
  /// document. Parser output retains increasing source child indices, including
  /// gaps for removed comments/active content, so each level supports binary
  /// search. This lets prefix consumers avoid a second full-tree first lookup.
  ForumBodyNode? nodeAtPath(String path) => _nodeAtPath(path);

  /// Actual ancestors including [element], or null for a foreign element.
  List<ForumBodyElement>? ancestryOf(ForumBodyElement element) {
    final ancestors = <ForumBodyElement>[];
    if (!identical(_nodeAtPath(element.path, ancestors), element)) return null;
    return ancestors..add(element);
  }

  ForumBodyNode? _nodeAtPath(String path, [List<ForumBodyElement>? ancestors]) {
    if (path.isEmpty) return null;
    var children = nodes;
    var prefix = '';
    final segments = path.split('/');
    for (var depth = 0; depth < segments.length; depth++) {
      final segment = segments[depth];
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index.toString() != segment) {
        return null;
      }
      prefix = prefix.isEmpty ? segment : '$prefix/$segment';
      var low = 0;
      var high = children.length - 1;
      ForumBodyNode? found;
      while (low <= high) {
        final middle = (low + high) >> 1;
        final candidate = children[middle];
        final candidateIndex = int.tryParse(
          candidate.path.substring(candidate.path.lastIndexOf('/') + 1),
        );
        if (candidateIndex == null) return null;
        if (candidateIndex < index) {
          low = middle + 1;
        } else if (candidateIndex > index) {
          high = middle - 1;
        } else {
          if (candidate.path != prefix) return null;
          found = candidate;
          break;
        }
      }
      if (found == null) return null;
      if (depth == segments.length - 1) return found;
      if (found is! ForumBodyElement) return null;
      ancestors?.add(found);
      children = found.children;
    }
    return null;
  }

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
