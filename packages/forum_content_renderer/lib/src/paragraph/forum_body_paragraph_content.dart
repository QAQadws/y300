import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../document/forum_body_document.dart';
import '../style/forum_body_length.dart';
import '../style/forum_body_style_options.dart';

enum ForumBodyParagraphInputFailure {
  identity,
  structure,
  inputLimit,
  runLimit,
}

final class ForumBodyParagraphInputException implements Exception {
  const ForumBodyParagraphInputException(this.failure, this.path);
  final ForumBodyParagraphInputFailure failure;
  final String? path;
  @override
  String toString() => 'ForumBodyParagraphInputException(${failure.name})';
}

final class ForumBodyParagraphRun {
  const ForumBodyParagraphRun(this.path, this.style);
  final String path;
  final ForumBodyResolvedStyle style;
}

/// One ordinary paragraph's display text and styles, without DOM or Host state.
/// The source projection is not a persisted novel semantic coordinate.
final class ForumBodyParagraphContent {
  ForumBodyParagraphContent._({
    required this.identity,
    required this.path,
    required this.fontRevision,
    required this.styleRevision,
    required this.style,
    required this.projection,
    required List<ForumBodyParagraphRun> runs,
    required List<ForumBodyStyleIssue> issues,
  }) : runs = List.unmodifiable(runs),
       issues = List.unmodifiable(issues);

  final ForumBodyIdentity identity;
  final String? path;
  final String fontRevision;
  final int styleRevision;
  final ForumBodyResolvedStyle style;
  final HtmlDisplayTextProjection projection;
  final List<ForumBodyParagraphRun> runs;
  final List<ForumBodyStyleIssue> issues;

  /// No recognizers are retained; interaction uses the same layout coordinates.
  late final TextSpan textSpan = TextSpan(
    style: style.textStyle,
    children: [
      for (final part in projection.parts)
        TextSpan(
          text: part.text,
          style: _paintStyle(runs[part.runIndex].style),
        ),
    ],
  );

  static TextStyle _paintStyle(ForumBodyResolvedStyle style) =>
      style.visibilityHidden
      ? style.textStyle.copyWith(
          foreground: Paint()..color = const Color(0x00000000),
          background: Paint()..color = const Color(0x00000000),
          decoration: TextDecoration.none,
          shadows: const [],
        )
      : style.textStyle;
}

/// Complex containers/resources require their own block/inline layout. They
/// cannot pass through this ordinary paragraph port and silently lose content.
final class ForumBodyParagraphContentBuilder {
  const ForumBodyParagraphContentBuilder({
    this.maxInputCodeUnits = 16384,
    this.maxRuns = 512,
  }) : assert(maxInputCodeUnits >= 0),
       assert(maxRuns >= 0);
  final int maxInputCodeUnits;
  final int maxRuns;

  ForumBodyParagraphContent build({
    required ForumBodyDocument document,
    required ForumBodyStyleResult styles,
    String? path,
  }) {
    if (document.identity != styles.identity) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        path,
      );
    }
    final root = path == null ? null : document.nodeAtPath(path);
    if (path != null && root == null) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        path,
      );
    }
    final base = path == null ? styles.root : styles.byPath[path];
    if (base == null) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.identity,
        path,
      );
    }
    final pending = <Iterator<ForumBodyNode>>[
      (root == null ? document.nodes : [root]).iterator,
    ];
    final inputs = <HtmlDisplayTextRun>[];
    final runs = <ForumBodyParagraphRun>[];
    var inputSize = 0;
    while (pending.isNotEmpty) {
      if (!pending.last.moveNext()) {
        pending.removeLast();
        continue;
      }
      final node = pending.last.current;
      final style = styles.byPath[node.path];
      if (style == null) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.identity,
          node.path,
        );
      }
      if (style.hidden) continue;
      if (node is ForumBodyElement &&
          node.kind != ForumBodyElementKind.hardBreak) {
        final ordinaryRoot =
            identical(node, root) &&
            const {
              ForumBodyElementKind.paragraph,
              ForumBodyElementKind.heading,
              ForumBodyElementKind.container,
            }.contains(node.kind);
        final ordinaryInline =
            const {
              ForumBodyElementKind.inline,
              ForumBodyElementKind.unknown,
            }.contains(node.kind) &&
            style.display == ForumBodyDisplay.inline &&
            _inlineBoxIsEmpty(style);
        if (!ordinaryRoot && !ordinaryInline) {
          throw ForumBodyParagraphInputException(
            ForumBodyParagraphInputFailure.structure,
            node.path,
          );
        }
        pending.add(node.children.iterator);
        continue;
      }
      final text = node is ForumBodyText ? node.text : '\n';
      inputSize += text.length;
      if (inputSize > maxInputCodeUnits) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.inputLimit,
          node.path,
        );
      }
      if (inputs.length >= maxRuns) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.runLimit,
          node.path,
        );
      }
      inputs.add(
        HtmlDisplayTextRun(
          text: text,
          sourceRuneStart: node.source.runeStart,
          hardBreak: node is ForumBodyElement,
          whiteSpace: switch (style.whiteSpace) {
            ForumBodyWhiteSpace.normal => HtmlDisplayWhiteSpace.normal,
            ForumBodyWhiteSpace.pre => HtmlDisplayWhiteSpace.pre,
            ForumBodyWhiteSpace.preWrap => HtmlDisplayWhiteSpace.preWrap,
            ForumBodyWhiteSpace.preLine => HtmlDisplayWhiteSpace.preLine,
          },
        ),
      );
      runs.add(ForumBodyParagraphRun(node.path, style));
    }
    return ForumBodyParagraphContent._(
      identity: document.identity,
      path: path,
      fontRevision: styles.fontRevision,
      styleRevision: styles.resolverRevision,
      style: base,
      projection: HtmlDisplayTextProjection.build(
        inputs,
        maxOutputCodeUnits: maxInputCodeUnits,
      ),
      runs: runs,
      issues: styles.issues
          .where(
            (issue) =>
                path == null ||
                issue.path == path ||
                issue.path.startsWith('$path/'),
          )
          .toList(),
    );
  }

  static bool _inlineBoxIsEmpty(ForumBodyResolvedStyle style) =>
      [
        style.margin.left,
        style.margin.right,
        style.padding.top,
        style.padding.right,
        style.padding.bottom,
        style.padding.left,
      ].every(
        (length) =>
            length.unit != ForumBodyLengthUnit.auto && length.value == 0,
      );
}
