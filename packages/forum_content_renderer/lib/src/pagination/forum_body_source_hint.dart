import 'package:html_pagination_core/html_pagination_core.dart';

/// Raw source envelope for candidate search only. Hidden gaps can be inside;
/// neither this envelope nor its endpoints prove visible semantic coverage.
({int runeStart, int runeEnd})? forumBodySourceHint(
  HtmlDisplayTextProjection projection,
  int startUtf16,
  int endUtf16,
) {
  RangeError.checkValidRange(startUtf16, endUtf16, projection.text.length);
  if (startUtf16 == endUtf16) return null;
  final start = projection.sourceAtUtf16(startUtf16);
  final end = projection.sourceAtUtf16(
    endUtf16,
    affinity: HtmlProjectionAffinity.upstream,
  );
  if (start.displayUtf16 != startUtf16 ||
      end.displayUtf16 != endUtf16 ||
      end.sourceRune < start.sourceRune) {
    throw ArgumentError('Source hints require a complete display window');
  }
  return (runeStart: start.sourceRune, runeEnd: end.sourceRune);
}
