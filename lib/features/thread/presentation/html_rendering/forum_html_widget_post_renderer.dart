import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_style_policy.dart';

class ForumHtmlWidgetPostRenderer extends StatelessWidget {
  const ForumHtmlWidgetPostRenderer({
    super.key,
    required this.html,
    this.callbacks = const ForumHtmlRenderCallbacks(),
    this.preferences,
    this.sourceId,
  });

  static final Uri forumBaseUri = Uri.parse('https://bbs.yamibo.com/');

  final String html;
  final ForumHtmlRenderCallbacks callbacks;
  final ForumHtmlReaderPreferences? preferences;
  final String? sourceId;

  @override
  Widget build(BuildContext context) {
    final resolvedPreferences =
        preferences ?? ForumHtmlReaderPreferences.defaults();
    final stylePolicy = ForumHtmlStylePolicy(resolvedPreferences);
    return HtmlWidget(
      stylePolicy.prepareHtml(html),
      key: Key('forum-html-renderer-${sourceId ?? 'anonymous'}'),
      baseUrl: forumBaseUri,
      customStylesBuilder: stylePolicy.customStylesFor,
      renderMode: RenderMode.column,
      textStyle: stylePolicy.baseTextStyle(context),
      onTapUrl: callbacks.onTapUrl,
    );
  }
}
