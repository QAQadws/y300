import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/localization/app_server_content_conversion_provider.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_projection.dart';
import 'package:y300/features/profile/presentation/blog/blog_content_projection_provider.dart';
import 'package:y300/features/profile/presentation/blog/blog_read_providers.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_content_projection_batch_executor.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter_factory.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import '../test_support/blog_text_converter_fixture.dart';

void main() {
  BlogContentProjector projector() {
    final plain = DefaultPlainTextBatchConversionService();
    return BlogContentProjector(
      TextContentProjectionBatchExecutor(
        plainTextBatchConversionService: plain,
        htmlTextNodeConversionService: DomHtmlTextNodeConversionService(
          plainTextBatchConversionService: plain,
        ),
        diagnosticRecorder: const NoopTextConversionDiagnosticRecorder(),
      ),
    );
  }

  test(
    'article conversion preserves HTML structure, identities and raw input',
    () async {
      const html =
          '<p class="正文" title="正文">正文<a href="/正文?q=标题">标题</a>'
          '<img src="/正文.png" alt="正文"></p><pre>正文</pre><code>正文</code>';
      final article = _article(body: html);
      final source = BlogContentSource.article(article);
      final converter = BlogTextConverterFixture();
      final display = await projector().project(source, converter);
      expect(display.text(article.title), '標題');
      expect(display.text(article.publishedAtText!), '1 分鐘前');
      expect(display.text(article.authorName!), '作者');
      expect(
        display.html(html),
        '<p class="正文" title="正文">內文<a href="/正文?q=标题">標題</a>'
        '<img src="/正文.png" alt="正文"></p><pre>正文</pre><code>正文</code>',
      );
      expect(article.bodyHtml, html);
      expect(article.blogId, '11');
      expect(article.actions, {UserBlogAction.edit});
      expect(converter.inputs, hasLength(2));
      expect(converter.inputs.join(), isNot(contains('作者')));
    },
  );

  test(
    'summary and comments leave author names outside the display batch',
    () async {
      const summary = UserBlogSummary(
        blogId: '11',
        ownerUserId: '101',
        title: '标题',
        excerpt: '摘要',
        authorName: '作者',
        categoryNames: ['文章分类'],
      );
      final converter = BlogTextConverterFixture();
      final display = await projector().project(
        BlogContentSource.summary(summary),
        converter,
      );
      expect(display.text(summary.title), '標題');
      expect(display.text(summary.excerpt!), '摘錄');
      expect(display.text(summary.authorName!), '作者');
      expect(display.text(summary.categoryNames.single), '文章分類');
      const comment = UserBlogComment(
        commentId: '5',
        authorName: '作者',
        bodyHtml: '<p>评论</p>',
        publishedAtText: '1 分钟前',
      );
      final commentDisplay = await projector().project(
        BlogContentSource.comment(comment),
        converter,
      );
      expect(commentDisplay.html(comment.bodyHtml), '<p>評論</p>');
      expect(commentDisplay.text(comment.authorName), '作者');
      expect(commentDisplay.text(comment.publishedAtText!), '1 分鐘前');
    },
  );

  test(
    'disabled or failed conversion returns exact source without losing markup',
    () async {
      final source = BlogContentSource(
        text: const ['标题'],
        html: const ["<p class='keep'>正文 &amp; raw</p>"],
      );
      final disabled = BlogTextConverterFixture(mode: TextConversionMode.none);
      final failed = BlogTextConverterFixture()..fail = true;
      for (final converter in [disabled, failed]) {
        final display = await projector().project(source, converter);
        expect(display.text(source.text.single), source.text.single);
        expect(display.html(source.html.single), source.html.single);
      }
      expect(disabled.inputs, isEmpty);
    },
  );

  test('simplified mode follows the same display-only path', () async {
    final source = BlogContentSource(
      text: const ['標題'],
      html: const ['<p>內文</p>'],
    );
    final display = await projector().project(
      source,
      BlogTextConverterFixture(mode: TextConversionMode.toSimplified),
    );
    expect(display.text('標題'), '标题');
    expect(display.html('<p>內文</p>'), '<p>正文</p>');
  });

  test(
    'comment page changes reuse the article projection but edited body changes it',
    () {
      final first = BlogContentSource.article(_article());
      final next = BlogContentSource.article(_article(page: 2));
      expect(next, first);
      expect(next.hashCode, first.hashCode);
      expect(
        BlogContentSource.article(_article(body: '<p>changed</p>')),
        isNot(first),
      );
      expect(() => first.text.add('cannot mutate'), throwsUnsupportedError);
    },
  );

  test(
    'late conversion cannot publish under a renewed account epoch',
    () async {
      final gate = Completer<void>();
      final converter = BlogTextConverterFixture(gate: gate);
      final container = ProviderContainer(
        overrides: [
          blogAccountIdProvider.overrideWithValue('101'),
          appServerContentConversionModeProvider.overrideWithValue(
            converter.mode,
          ),
          textConverterProvider(converter.mode).overrideWithValue(converter),
        ],
      );
      addTearDown(container.dispose);
      final provider = blogContentProjectionProvider(
        BlogContentSource.article(_article()),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final oldOwner = container.read(blogMutationBusProvider);
      for (final actor in ['202', '101']) {
        container.updateOverrides([
          blogAccountIdProvider.overrideWithValue(actor),
          appServerContentConversionModeProvider.overrideWithValue(
            converter.mode,
          ),
          textConverterProvider(converter.mode).overrideWithValue(converter),
        ]);
        await container.pump();
      }
      expect(subscription.read().isLoading, isTrue);
      final newOwner = container.read(blogMutationBusProvider);
      expect(newOwner, isNot(same(oldOwner)));
      gate.complete();
      final result = await container.read(provider.future);
      expect(result.owner, same(newOwner));
      expect(result.display.text('标题'), '標題');
    },
  );
}

UserBlogDetailData _article({String body = '<p>正文</p>', int page = 1}) =>
    UserBlogDetailData(
      blogId: '11',
      ownerUserId: '101',
      title: '标题',
      authorName: '作者',
      bodyHtml: body,
      publishedAtText: '1 分钟前',
      actions: const {UserBlogAction.edit},
      commentPagination: UserBlogPagination(currentPage: page),
      comments: [
        UserBlogComment(
          commentId: '$page',
          authorName: '作者',
          bodyHtml: '<p>评论 $page</p>',
        ),
      ],
    );
