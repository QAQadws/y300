import 'package:forum_content_renderer/forum_text.dart';

/// Raw source envelope for candidate search only. Hidden gaps can be inside;
/// neither this envelope nor its endpoints prove visible semantic coverage.
({int runeStart, int runeEnd})? forumBodySourceHint(
  HtmlDisplayTextProjection projection,
  int startUtf16,
  int endUtf16,
) => projection.sourceEnvelope(startUtf16: startUtf16, endUtf16: endUtf16);
