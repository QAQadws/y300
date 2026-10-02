import 'package:flutter/foundation.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_content_projection_batch_executor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Only displayable fields enter conversion. Identity, action targets and
/// editor inputs continue to come from the untouched source models.
@immutable
final class BlogContentSource {
  BlogContentSource({
    List<String> text = const [],
    List<String> html = const [],
  }) : text = List.unmodifiable(text),
       html = List.unmodifiable(html);

  factory BlogContentSource.summary(UserBlogSummary item) => BlogContentSource(
    text: [
      item.title,
      ?item.excerpt,
      ?item.publishedAtText,
      ...item.categoryNames,
    ],
  );

  factory BlogContentSource.article(UserBlogDetailData article) =>
      BlogContentSource(
        text: [
          article.title,
          ?article.publishedAtText,
          for (final link in article.categoryLinks) link.name,
        ],
        html: [article.bodyHtml],
      );

  factory BlogContentSource.comment(UserBlogComment comment) =>
      BlogContentSource(
        text: [?comment.publishedAtText],
        html: [comment.bodyHtml],
      );

  final List<String> text;
  final List<String> html;

  @override
  bool operator ==(Object other) =>
      other is BlogContentSource &&
      listEquals(text, other.text) &&
      listEquals(html, other.html);

  @override
  int get hashCode => Object.hash(Object.hashAll(text), Object.hashAll(html));
}

/// A display-only lookup. Returning the raw value is also the initial,
/// disabled and failed-conversion behavior; no loading subtree is required.
@immutable
final class BlogDisplayText {
  const BlogDisplayText.raw() : _text = const {}, _html = const {};
  BlogDisplayText._(Map<String, String> text, Map<String, String> html)
    : _text = Map.unmodifiable(text),
      _html = Map.unmodifiable(html);

  final Map<String, String> _text;
  final Map<String, String> _html;
  String text(String raw) => _text[raw] ?? raw;
  String html(String raw) => _html[raw] ?? raw;
}

final class BlogContentProjector {
  const BlogContentProjector(this.executor);
  final TextContentProjectionBatchExecutor executor;

  Future<BlogDisplayText> project(
    BlogContentSource source,
    TextConverter converter,
  ) async {
    if (converter.mode == TextConversionMode.none) {
      return const BlogDisplayText.raw();
    }
    final batch = await executor.convert(
      surface: TextConversionSurface.blogs,
      plainSources: source.text,
      htmlFragments: source.html,
      converter: converter,
      sourceRevision: 'blog:${source.hashCode}',
    );
    if (!batch.succeeded) return const BlogDisplayText.raw();
    return BlogDisplayText._(
      {
        for (var i = 0; i < source.text.length; i++)
          source.text[i]: batch.plainValues[i],
      },
      {
        for (var i = 0; i < source.html.length; i++)
          source.html[i]: batch.htmlValues[i].html,
      },
    );
  }
}
