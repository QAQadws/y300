import 'package:flutter/foundation.dart';

@immutable
class ForumHtmlRenderInput {
  const ForumHtmlRenderInput({
    required this.sourceId,
    required this.rawHtml,
    required this.fragmentHtml,
  });

  final String sourceId;
  final String rawHtml;
  final String fragmentHtml;
}
