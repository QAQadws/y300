import 'package:flutter/painting.dart';

import '../style/forum_body_style_options.dart';
import '../style/forum_body_length.dart';
import 'forum_body_paragraph_geometry.dart';

/// Immutable validation work, retained by the exact paragraph input. Actual
/// scaler values are deliberately absent and must be read on every admission.
final class ForumBodyParagraphInputAdmission {
  ForumBodyParagraphInputAdmission._(Iterable<double?> sizes, this._failure)
    : _sizes = List.unmodifiable(sizes);

  factory ForumBodyParagraphInputAdmission({
    required ForumBodyResolvedStyle style,
    required Iterable<ForumBodyResolvedStyle> runStyles,
    required String displayText,
    required bool wraps,
    required bool allowsIndent,
    required bool appliesFirstLineIndent,
  }) {
    // Intrinsic children leave inherited indentation to their containing block.
    if (!allowsIndent &&
        appliesFirstLineIndent &&
        style.indent.value != 0 &&
        (!wraps ||
            !style.indent.value.isFinite ||
            style.indent.value < 0 ||
            style.indent.unit == ForumBodyLengthUnit.auto ||
            style.indent.unit == ForumBodyLengthUnit.rem)) {
      return ForumBodyParagraphInputAdmission._(
        const [],
        ForumBodyParagraphLayoutFailure.indent,
      );
    }
    if (!wraps &&
        displayText.runes.any(
          (rune) =>
              forumBodyIsDisplayLineBreak(rune) || rune == 0x0d || rune == 0x85,
        )) {
      return ForumBodyParagraphInputAdmission._(
        const [],
        ForumBodyParagraphLayoutFailure.singleLine,
      );
    }
    final sizes = <double?>{};
    ForumBodyParagraphLayoutFailure? failure;
    for (final current in [style, ...runStyles]) {
      if (current.textDirection != style.textDirection) {
        failure = ForumBodyParagraphLayoutFailure.direction;
        break;
      }
      if (current.whiteSpace == ForumBodyWhiteSpace.pre && wraps) {
        failure = ForumBodyParagraphLayoutFailure.noWrap;
        break;
      }
      final size = current.textStyle.fontSize;
      sizes.add(size);
      if (size == null) break;
    }
    return ForumBodyParagraphInputAdmission._(sizes, failure);
  }

  final List<double?> _sizes;
  final ForumBodyParagraphLayoutFailure? _failure;

  /// Replays unique sizes in original style order, then any terminal immutable
  /// failure. A later invalid style cannot hide an earlier scaler failure or
  /// skip caller code. The map is request-local, including reentrant requests.
  void resolveScalesInto(
    Map<double, double> scales, {
    required TextScaler textScaler,
  }) {
    scales.clear();
    for (final input in _sizes) {
      // Unresolved font sizes fail here, after preceding scaler calls, just as
      // on the uncached input path. They never enter a successful native key.
      final size = input!;
      final scaled = textScaler.scale(size);
      if (!scaled.isFinite || scaled <= 0 || scaled > 4096) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.scale,
        );
      }
      scales[size] = scaled;
    }
    final failure = _failure;
    if (failure != null) throw ForumBodyParagraphLayoutException(failure);
  }
}
