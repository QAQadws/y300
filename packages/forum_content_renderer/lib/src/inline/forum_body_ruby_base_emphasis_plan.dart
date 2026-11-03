part of 'forum_body_emphasis_line_layout.dart';

/// Drawing input for the base plane only. RT glyphs and their source bindings
/// remain owned by the containing ruby; this is not coverage of a whole column.
final class ForumBodyRubyBaseEmphasisPlan {
  const ForumBodyRubyBaseEmphasisPlan._(this.geometry, this.pictureInput);
  final ForumBodyRubyBaseEmphasisGeometry geometry;
  final ForumBodyTextPictureInput pictureInput;

  Iterable<ForumBodyNativeBudgetSlot> get nativeBudgetFootprint sync* {
    yield* geometry.line.nativeFootprint;
    yield (
      request: ForumBodyTextPictureBudgetInput(pictureInput),
      width: geometry.line.requestWidth,
      minimumLineCount: 0,
    );
  }
}

/// Compose actual measured font keys, preserving the marker's baseline and
/// local font transforms separately. No native request or source is acquired.
final class ForumBodyRubyBaseEmphasisPlanPreparation {
  ForumBodyRubyBaseEmphasisPlanPreparation({
    required ForumBodyRubyBaseEmphasisGeometry geometry,
    required void Function() ensureOwner,
  }) : _geometry = geometry,
       _composition = ForumBodyTextPictureInputComposition(
         inputs: _inputs(geometry),
         ensureOwner: ensureOwner,
         maxInputs: 513,
         maxCommands: 513,
       );
  ForumBodyRubyBaseEmphasisGeometry? _geometry;
  final ForumBodyTextPictureInputComposition _composition;
  bool get isReady => _composition.isReady;
  int advance({int maxParts = 32}) => _composition.advance(maxParts: maxParts);
  ForumBodyRubyBaseEmphasisPlan takePlan() {
    try {
      final picture = _composition.takeInput();
      final geometry = _geometry!;
      _geometry = null;
      return ForumBodyRubyBaseEmphasisPlan._(geometry, picture);
    } catch (_) {
      close();
      rethrow;
    }
  }

  void close() {
    _geometry = null;
    _composition.close();
  }

  static Iterable<ForumBodyPositionedTextPictureInput> _inputs(
    ForumBodyRubyBaseEmphasisGeometry geometry,
  ) sync* {
    final line = geometry.line;
    yield (
      input: ForumBodyTextPictureInput(
        commands: [
          ForumBodyTextPictureCommand(
            nativeInputIdentity: line._baseKey,
            offset: geometry.group.baseOffset,
            bandChildIndex: line.baseRequest is ForumBodyTextBandChildRequest
                ? (line.baseRequest as ForumBodyTextBandChildRequest).childIndex
                : null,
          ),
        ],
      ),
      offset: Offset.zero,
    );
    for (final placed in geometry.marks) {
      final mark = placed.mark;
      yield (
        input: ForumBodyTextPictureInput(
          commands: [
            ForumBodyTextPictureCommand(
              nativeInputIdentity:
                  line._markKeys[line._unitMarks[mark.unitIndex]],
              offset: placed.fontOffset,
              fitScale: mark.fitScale,
            ).translated(placed.baselineOrigin),
          ],
        ),
        offset: Offset.zero,
      );
    }
  }
}
