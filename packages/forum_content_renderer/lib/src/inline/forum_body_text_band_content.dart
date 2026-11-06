import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_content.dart';

/// Independent intrinsic text contexts, not a new document or source axis.
/// Empty text needs no native slot. Incompatible root directions/alignment or
/// locales belong in separate bounded bands; nothing is silently restyled.
final class ForumBodyTextBandContent {
  ForumBodyTextBandContent._(
    this.contexts,
    this.projection,
    this.textCodeUnits,
    this.runCount,
  );
  static const revision = 1;
  factory ForumBodyTextBandContent({
    required List<ForumBodyParagraphContent> contexts,
    int maxChildren = 64,
    int maxInputCodeUnits = 16384,
    int maxRuns = 512,
  }) {
    if (maxChildren < 0 || maxInputCodeUnits < 0 || maxRuns < 0) {
      throw ArgumentError('Invalid text band input budget');
    }
    if (contexts.isEmpty) {
      throw const ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.structure,
        null,
      );
    }
    if (contexts.length > maxChildren) {
      throw ForumBodyParagraphInputException(
        ForumBodyParagraphInputFailure.inputLimit,
        contexts.first.path,
      );
    }
    final first = contexts.first;
    var runs = 0;
    var textCodeUnits = 0;
    for (final context in contexts) {
      if (context.identity != first.identity ||
          context.fontRevision != first.fontRevision ||
          context.styleRevision != first.styleRevision) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.identity,
          context.path,
        );
      }
      if (!supportsContext(context) ||
          context.style.textDirection != first.style.textDirection ||
          context.style.textAlign != first.style.textAlign ||
          context.style.textStyle.locale != first.style.textStyle.locale) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.structure,
          context.path,
        );
      }
      runs += context.runs.length;
      textCodeUnits += context.projection.text.length;
      if (runs > maxRuns) {
        throw ForumBodyParagraphInputException(
          ForumBodyParagraphInputFailure.runLimit,
          context.path,
        );
      }
    }
    return ForumBodyTextBandContent._(
      List.unmodifiable(contexts),
      HtmlTextBandProjection.build(
        contexts.map((context) => context.projection).toList(),
        maxChildren: maxChildren,
        maxDisplayCodeUnits: maxInputCodeUnits,
      ),
      textCodeUnits,
      runs,
    );
  }
  final List<ForumBodyParagraphContent> contexts;
  final HtmlTextBandProjection projection;
  final int textCodeUnits;
  final int runCount;

  late final ForumBodyTextBandContent withoutTextBackground =
      ForumBodyTextBandContent._(
        List.unmodifiable([
          for (final context in contexts)
            context.hasSolidTextBackground
                ? context.withoutTextBackground
                : context,
        ]),
        projection,
        textCodeUnits,
        runCount,
      );

  /// Pure eligibility only. Scope, source order, root compatibility and total
  /// budgets still belong to construction. Native isolation is checked later.
  static bool supportsContext(ForumBodyParagraphContent context) =>
      context.layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine &&
      context.projection.text.isNotEmpty &&
      [context.style, ...context.runs.map((run) => run.style)].every(
        (style) =>
            !(style.textStyle.shadows?.isNotEmpty ?? false) &&
            !_needsInkBounds(style.textStyle.foreground) &&
            !_needsInkBounds(style.textStyle.background),
      );
}

bool _needsInkBounds(Paint? paint) =>
    paint != null &&
    (paint.style != PaintingStyle.fill ||
        paint.maskFilter != null ||
        paint.imageFilter != null);

// Internal native input, intentionally excluded from the package barrel. The
// neutral root prevents a first child's optional family/weight/paint leaking
// into a later context that uses native defaults.
TextSpan buildForumBodyTextBandSpan(
  ForumBodyTextBandContent content,
  double gutter,
) => TextSpan(
  style: TextStyle(fontSize: content.contexts.first.style.textStyle.fontSize),
  children: [
    for (var i = 0; i < content.contexts.length; i++) ...[
      if (i > 0) _TextBandSeparator(gutter),
      content.contexts[i].textSpan,
    ],
  ],
);

final class _TextBandSeparator extends TextSpan {
  const _TextBandSeparator(this.gutter)
    : super(text: HtmlTextBandProjection.separator);
  final double gutter;
  static final _breakStyle = ui.TextStyle(
    fontSize: 0,
    // An exact zero height takes default engine metrics (a one-pixel font
    // floor). A positive near-zero override stays neutral for tiny author rows.
    height: 0.001,
    color: const Color(0x00000000),
  );
  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    void lineBreak() {
      builder.pushStyle(_breakStyle);
      builder.addText('\n');
      builder.pop();
    }

    lineBreak();
    // This is a transparent engine spacer, already in logical pixels. Applying
    // the caller's TextScaler here would scale the separation a second time.
    builder.pushStyle(
      ui.TextStyle(
        fontFamily: 'sans-serif',
        fontSize: gutter,
        height: 1,
        color: const Color(0x00000000),
        decoration: TextDecoration.none,
      ),
    );
    builder.addText('\u200b');
    builder.pop();
    lineBreak();
  }

  @override
  RenderComparison compareTo(InlineSpan other) =>
      other is _TextBandSeparator && other.gutter == gutter
      ? RenderComparison.identical
      : RenderComparison.layout;
  @override
  bool operator ==(Object other) =>
      other is _TextBandSeparator && other.gutter == gutter && super == other;
  @override
  int get hashCode => Object.hash(super.hashCode, gutter);
}
