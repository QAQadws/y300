import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';

class ForumHtmlWidgetPostRenderer extends StatelessWidget {
  const ForumHtmlWidgetPostRenderer({
    super.key,
    required this.html,
    this.callbacks = const ForumHtmlRenderCallbacks(),
    this.sourceId,
  });

  static final Uri forumBaseUri = Uri.parse('https://bbs.yamibo.com/');

  final String html;
  final ForumHtmlRenderCallbacks callbacks;
  final String? sourceId;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return HtmlWidget(
      html,
      key: Key('forum-html-renderer-${sourceId ?? 'anonymous'}'),
      baseUrl: forumBaseUri,
      renderMode: RenderMode.column,
      textStyle: textStyle,
      onTapUrl: callbacks.onTapUrl,
    );
  }
}
