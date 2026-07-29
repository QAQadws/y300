import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_post_ratings_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/features/thread/presentation/thread_detail_content_projector.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';

void main() {
  group('ThreadDetailContentProjector', () {
    test(
      'none mode returns raw content without invoking either batch',
      () async {
        final plain = _PrefixPlainService();
        final html = _RecordingHtmlService();
        final recorder = _RecordingDiagnosticRecorder();
        final source = _source();

        final projection =
            await ThreadDetailContentProjector(
              plainTextBatchConversionService: plain,
              htmlTextNodeConversionService: html,
              diagnosticRecorder: recorder,
            ).project(
              source,
              converter: const _TestConverter(mode: TextConversionMode.none),
            );

        expect(plain.callCount, 0);
        expect(html.callCount, 0);
        expect(recorder.events, isEmpty);
        expect(projection.isConverted, isFalse);
        expect(projection.displaySubject, source.subject);
        expect(
          projection.posts.single.displayPost.message,
          source.posts.single.message,
        );
      },
    );

    test(
      'projects all allowed fields atomically and preserves source identities',
      () async {
        final plain = _PrefixPlainService();
        final html = _RecordingHtmlService();
        final recorder = _RecordingDiagnosticRecorder();
        final source = _source();

        final projection = await ThreadDetailContentProjector(
          plainTextBatchConversionService: plain,
          htmlTextNodeConversionService: html,
          diagnosticRecorder: recorder,
        ).project(source, converter: const _TestConverter());

        expect(plain.callCount, 1);
        expect(html.callCount, 1);
        expect(html.lastFragments, <String>[source.posts.single.message]);
        expect(projection.isConverted, isTrue);
        expect(projection.displaySubject, 'P:主题');
        expect(projection.displayForumName, 'P:漫画区');
        expect(projection.displayTypeName, 'P:资源');
        expect(projection.displaySourceTagName, 'P:中文漫画');

        final projected = projection.posts.single;
        final display = projected.displayPost;
        final raw = projected.sourcePost;
        expect(identical(raw, source.posts.single), isTrue);
        expect(display.message, contains('H:正文'));
        expect(
          display.message,
          contains('href="/home.php?mod=space&amp;uid=9"'),
        );
        expect(display.message, contains('用户名'));
        expect(display.dateline, 'P:昨天');
        expect(display.rateSummary, 'P:已有评分');
        expect(display.tagLinks.single.label, 'P:标签');
        expect(display.tagLinks.single.url, '/tag.php?id=2');
        expect(display.attachmentImages.single.filename, 'P:附件名称.jpg');
        expect(display.attachmentImages.single.url, '/attachment.php?aid=8');

        expect(display.author, '服务器用户名');
        expect(display.authorId, '9');
        expect(display.replyUrl, '/reply?pid=1');
        expect(display.rateUrl, '/rate?pid=1');
        expect(display.commentUrl, '/comment?pid=1');

        expect(display.poll?.summary, 'P:投票摘要');
        expect(display.poll?.deadlineText, 'P:截止时间');
        expect(display.poll?.statusText, 'P:投票状态');
        expect(display.poll?.options.single.label, 'P:投票选项');
        expect(display.poll?.options.single.id, 'option-1');
        expect(display.poll?.actionUrl, '/poll');
        expect(display.poll?.formHash, 'raw-formhash');

        expect(display.comments.single.author, '点评用户名');
        expect(display.comments.single.message, 'P:点评正文');
        expect(display.comments.single.dateline, 'P:点评时间');
        expect(display.comments.single.authorUrl, '/home.php?uid=10');

        final summary = display.ratingSummary!;
        expect(summary.participantText, 'P:参与人数');
        expect(summary.scoreText, 'P:积分合计');
        expect(summary.ratings.single.userName, '评分用户名');
        expect(summary.ratings.single.score, 'P:+2');
        expect(summary.ratings.single.reason, 'P:评分理由');
        expect(summary.ratings.single.dateline, 'P:评分时间');
        expect(summary.viewAllUrl, '/ratings?pid=1');

        final fullRatings = projection.displayRatingsByPostId['1']!.details!;
        expect(fullRatings.participantCount, 2);
        expect(fullRatings.totalScoreText, 'P:+5 点');
        expect(fullRatings.ratings.single.userName, '完整评分用户名');
        expect(fullRatings.ratings.single.reason, 'P:完整评分理由');

        final event = recorder.events.single;
        expect(event.surface, TextConversionSurface.threadDetail);
        expect(event.mode, TextConversionMode.toTraditional);
        expect(event.sourceRevision, projection.sourceRevision);
        expect(event.htmlFragmentCount, 1);
        expect(event.failureType, isNull);
        expect(event.toString(), isNot(contains('主题')));
        expect(event.toString(), isNot(contains('服务器用户名')));
      },
    );

    test('plain failure discards the whole converted surface', () async {
      final source = _source();
      final html = _RecordingHtmlService();
      final recorder = _RecordingDiagnosticRecorder();

      final projection = await ThreadDetailContentProjector(
        plainTextBatchConversionService: const _ThrowingPlainService(),
        htmlTextNodeConversionService: html,
        diagnosticRecorder: recorder,
      ).project(source, converter: const _TestConverter());

      expect(projection.isConverted, isFalse);
      expect(projection.displaySubject, '主题');
      expect(
        projection.posts.single.displayPost.message,
        source.posts.single.message,
      );
      expect(html.callCount, 0);
      expect(recorder.events.single.failureType, 'StateError');
    });

    test('HTML failure discards successful plain values', () async {
      final source = _source();
      final recorder = _RecordingDiagnosticRecorder();

      final projection = await ThreadDetailContentProjector(
        plainTextBatchConversionService: _PrefixPlainService(),
        htmlTextNodeConversionService: _RecordingHtmlService(shouldThrow: true),
        diagnosticRecorder: recorder,
      ).project(source, converter: const _TestConverter());

      expect(projection.isConverted, isFalse);
      expect(projection.displaySubject, '主题');
      expect(projection.posts.single.displayPost.dateline, '昨天');
      expect(recorder.events.single.failureType, 'StateError');
    });

    test(
      'keeps Yamibo user link text raw while converting ordinary link text',
      () async {
        final plain = _PrefixPlainService();
        final source = _source(
          message:
              '<a href="/home.php?mod=space&amp;uid=9">用户名</a>'
              '<a href="/thread-99-1-1.html">普通链接</a>'
              '<img src="/raw.jpg" alt="属性文字">',
        );

        final projection = await ThreadDetailContentProjector(
          plainTextBatchConversionService: plain,
          htmlTextNodeConversionService: DomHtmlTextNodeConversionService(
            plainTextBatchConversionService: plain,
          ),
          diagnosticRecorder: _RecordingDiagnosticRecorder(),
        ).project(source, converter: const _TestConverter());

        final html = projection.posts.single.displayPost.message;
        expect(html, contains('>用户名</a>'));
        expect(html, contains('>P:普通链接</a>'));
        expect(html, contains('href="/home.php?mod=space&amp;uid=9"'));
        expect(html, contains('src="/raw.jpg"'));
        expect(html, contains('alt="属性文字"'));
      },
    );

    test(
      'revision ignores transient state but includes loaded rating content',
      () {
        final source = _source().copyWith(
          ratingsByPostId: const <String, ThreadPostRatingsViewState>{},
        );
        final base = ThreadDetailContentProjector.sourceRevisionFor(source);
        final transient = source.copyWith(
          selectedPollOptionIds: const <String>{'option-1'},
          isPollVoteSubmitting: true,
          ratingsByPostId: const <String, ThreadPostRatingsViewState>{
            '1': ThreadPostRatingsViewState.loading(),
          },
        );
        final loaded = source.copyWith(
          ratingsByPostId: const <String, ThreadPostRatingsViewState>{
            '1': ThreadPostRatingsViewState.loaded(
              ThreadPostRatingDetails(
                participantCount: 1,
                totalScoreText: '+1',
                ratings: <ThreadPostRating>[
                  ThreadPostRating(userName: '用户', score: '+1', reason: '理由'),
                ],
              ),
            ),
          },
        );

        expect(ThreadDetailContentProjector.sourceRevisionFor(transient), base);
        expect(
          ThreadDetailContentProjector.sourceRevisionFor(loaded),
          isNot(base),
        );
      },
    );
  });
}

ThreadDetailPageState _source({String? message}) {
  final post = ThreadPost(
    pid: '1',
    author: '服务器用户名',
    authorId: '9',
    message:
        message ??
        '<p>正文</p>'
            '<a href="/home.php?mod=space&amp;uid=9">用户名</a>'
            '<img src="/image.jpg" alt="图片属性">',
    number: 1,
    isFirst: true,
    dateline: '昨天',
    avatarUrl: '/avatar/9',
    replyUrl: '/reply?pid=1',
    rateUrl: '/rate?pid=1',
    commentUrl: '/comment?pid=1',
    rateSummary: '已有评分',
    tagLinks: const <ThreadPostTagLink>[
      ThreadPostTagLink(label: '标签', url: '/tag.php?id=2', tagId: '2'),
    ],
    attachmentImages: const <ForumPostAttachmentImage>[
      ForumPostAttachmentImage(
        aid: '8',
        url: '/attachment.php?aid=8',
        attachment: 'raw/path.jpg',
        filename: '附件名称.jpg',
        attachimg: '1',
        ext: 'jpg',
      ),
    ],
    poll: const ThreadPoll(
      isMultipleChoice: false,
      summary: '投票摘要',
      deadlineText: '截止时间',
      statusText: '投票状态',
      actionUrl: '/poll',
      formHash: 'raw-formhash',
      options: <ThreadPollOption>[
        ThreadPollOption(
          id: 'option-1',
          label: '投票选项',
          voteCount: 3,
          percent: 50,
        ),
      ],
    ),
    comments: const <ThreadPostCommentEntry>[
      ThreadPostCommentEntry(
        author: '点评用户名',
        authorId: '10',
        authorUrl: '/home.php?uid=10',
        message: '点评正文',
        dateline: '点评时间',
      ),
    ],
    ratingSummary: const ThreadPostRatingSummary(
      participantText: '参与人数',
      scoreText: '积分合计',
      viewAllUrl: '/ratings?pid=1',
      ratings: <ThreadPostRating>[
        ThreadPostRating(
          userName: '评分用户名',
          userId: '11',
          score: '+2',
          reason: '评分理由',
          dateline: '评分时间',
        ),
      ],
    ),
  );
  return ThreadDetailPageState.initial(tid: '100', subject: '主题').copyWith(
    fid: '30',
    typeid: '7',
    typeName: '资源',
    forumName: '漫画区',
    sourceTagName: '中文漫画',
    contentKind: ThreadContentKind.comic,
    currentPage: 2,
    queryParameters: const <String, String>{'authorid': '9', 'ordertype': '1'},
    isLoadingInitial: false,
    posts: <ThreadPost>[post],
    ratingsByPostId: const <String, ThreadPostRatingsViewState>{
      '1': ThreadPostRatingsViewState.loaded(
        ThreadPostRatingDetails(
          participantCount: 2,
          totalScoreText: '+5 点',
          ratings: <ThreadPostRating>[
            ThreadPostRating(
              userName: '完整评分用户名',
              userId: '12',
              score: '+3',
              reason: '完整评分理由',
              dateline: '完整评分时间',
            ),
          ],
        ),
      ),
    },
  );
}

class _PrefixPlainService implements PlainTextBatchConversionService {
  int callCount = 0;

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    callCount += 1;
    return <String>[for (final source in sources) 'P:$source'];
  }
}

class _ThrowingPlainService implements PlainTextBatchConversionService {
  const _ThrowingPlainService();

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) {
    throw StateError('plain conversion failed');
  }
}

class _RecordingHtmlService extends HtmlTextNodeConversionService {
  _RecordingHtmlService({this.shouldThrow = false});

  final bool shouldThrow;
  int callCount = 0;
  List<String> lastFragments = const <String>[];

  @override
  Future<List<HtmlTextNodeConversionResult>> convertAll({
    required List<String> htmlFragments,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  }) async {
    callCount += 1;
    lastFragments = List<String>.from(htmlFragments);
    if (shouldThrow) {
      throw StateError('HTML conversion failed');
    }
    return <HtmlTextNodeConversionResult>[
      for (final fragment in htmlFragments)
        HtmlTextNodeConversionResult(
          html: fragment.replaceFirst('正文', 'H:正文'),
          convertedTextNodeCount: 1,
          converterId: converter.id,
        ),
    ];
  }
}

class _TestConverter implements TextConverter {
  const _TestConverter({this.mode = TextConversionMode.toTraditional});

  @override
  final TextConversionMode mode;

  @override
  String get id => 'test:${mode.name}';

  @override
  Future<String> convertHtml(String html) async => html;
}

class _RecordingDiagnosticRecorder implements TextConversionDiagnosticRecorder {
  final List<TextConversionDiagnosticEvent> events =
      <TextConversionDiagnosticEvent>[];

  @override
  void record(TextConversionDiagnosticEvent event) {
    events.add(event);
  }
}
