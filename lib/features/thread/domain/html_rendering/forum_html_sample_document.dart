import 'package:flutter/foundation.dart';

@immutable
class ForumHtmlSampleDocument {
  const ForumHtmlSampleDocument({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.sourceDocPath,
  });

  final String id;
  final String title;
  final String assetPath;
  final String sourceDocPath;
}

const List<ForumHtmlSampleDocument> forumHtmlPrototypeSamples =
    <ForumHtmlSampleDocument>[
      ForumHtmlSampleDocument(
        id: 'ruby',
        title: '注音',
        assetPath: 'assets/prototypes/forum_html/ruby.html',
        sourceDocPath: 'docs/html/特殊格式/注音.html',
      ),
      ForumHtmlSampleDocument(
        id: 'background_color',
        title: '文字背景色',
        assetPath: 'assets/prototypes/forum_html/background_color.html',
        sourceDocPath: 'docs/html/特殊格式/文字背景色.html',
      ),
      ForumHtmlSampleDocument(
        id: 'collapse_directory',
        title: '折叠目录',
        assetPath: 'assets/prototypes/forum_html/collapse_directory.html',
        sourceDocPath: 'docs/html/特殊格式/折叠目录.html',
      ),
      ForumHtmlSampleDocument(
        id: 'text_color_size',
        title: '字颜色字号',
        assetPath: 'assets/prototypes/forum_html/text_color_size.html',
        sourceDocPath: 'docs/html/特殊格式/字颜色字号.html',
      ),
    ];
