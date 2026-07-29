import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projector.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

void main() {
  const key = ComicCommentSessionKey(
    episodeId: 'episode-1',
    sourceTid: '573279',
  );

  group('ComicCommentContentProjector', () {
    test(
      'none mode returns raw content without invoking either batch',
      () async {
        final plain = _RecordingPlainService();
        final html = _RecordingHtmlService();
        final recorder = _RecordingDiagnosticRecorder();
        final source = _source();

        final projection =
            await ComicCommentContentProjector(
              plainTextBatchConversionService: plain,
              htmlTextNodeConversionService: html,
              diagnosticRecorder: recorder,
            ).project(
              sessionKey: key,
              source: source,
              converter: const _TestConverter(mode: TextConversionMode.none),
            );

        expect(plain.callCount, 0);
        expect(html.callCount, 0);
        expect(recorder.events, isEmpty);
        expect(projection.isConverted, isFalse);
        expect(projection.items.first.displayDateline, '软件时间');
        expect(projection.items.first.displayMessage, contains('软件正文'));
      },
    );

    test(
      'converts one plain and one HTML batch while preserving source identity',
      () async {
        final plain = _RecordingPlainService();
        final html = _RecordingHtmlService();
        final recorder = _RecordingDiagnosticRecorder();
        final source = _source();

        final projection =
            await ComicCommentContentProjector(
              plainTextBatchConversionService: plain,
              htmlTextNodeConversionService: html,
              diagnosticRecorder: recorder,
            ).project(
              sessionKey: key,
              source: source,
              converter: const _TestConverter(),
            );

        expect(plain.callCount, 1);
        expect(plain.lastSources, <String>['软件时间', '第二时间']);
        expect(html.callCount, 1);
        expect(html.lastFragments, <String>[
          source.items[0].rawMessage,
          source.items[1].rawMessage,
        ]);
        expect(projection.items, hasLength(2));
        expect(projection.items[0].displayDateline, 'P:软件时间');
        expect(projection.items[1].displayDateline, 'P:第二时间');
        expect(projection.items[0].displayMessage, startsWith('H:'));
        expect(
          identical(projection.items[0].sourceItem, source.items[0]),
          isTrue,
        );
        expect(projection.items[0].sourceItem.authorName, '发型用户名');
        expect(projection.items[0].sourceItem.authorId, '8');
        expect(projection.items[0].sourceItem.avatarUrl, '/avatar/8');
        expect(projection.items[0].sourceItem.pid, 'p2');
        expect(projection.items[0].sourceItem.floorNumber, 2);

        final event = recorder.events.single;
        expect(event.surface, TextConversionSurface.comicComments);
        expect(event.mode, TextConversionMode.toTraditional);
        expect(event.sourceRevision, projection.sourceRevision);
        expect(event.plainSourceCount, 2);
        expect(event.htmlFragmentCount, 2);
        expect(event.failureType, isNull);
      },
    );

    test(
      'plain or HTML failure discards the whole converted surface',
      () async {
        final source = _source();
        final plainRecorder = _RecordingDiagnosticRecorder();
        final plainFailure =
            await ComicCommentContentProjector(
              plainTextBatchConversionService: const _ThrowingPlainService(),
              htmlTextNodeConversionService: _RecordingHtmlService(),
              diagnosticRecorder: plainRecorder,
            ).project(
              sessionKey: key,
              source: source,
              converter: const _TestConverter(),
            );
        expect(plainFailure.isConverted, isFalse);
        expect(plainFailure.items[0].displayDateline, '软件时间');
        expect(
          plainFailure.items[0].displayMessage,
          source.items[0].rawMessage,
        );
        expect(plainRecorder.events.single.failureType, 'StateError');

        final htmlRecorder = _RecordingDiagnosticRecorder();
        final htmlFailure =
            await ComicCommentContentProjector(
              plainTextBatchConversionService: _RecordingPlainService(),
              htmlTextNodeConversionService: _RecordingHtmlService(
                shouldThrow: true,
              ),
              diagnosticRecorder: htmlRecorder,
            ).project(
              sessionKey: key,
              source: source,
              converter: const _TestConverter(),
            );
        expect(htmlFailure.isConverted, isFalse);
        expect(htmlFailure.items[0].displayDateline, '软件时间');
        expect(htmlFailure.items[0].displayMessage, source.items[0].rawMessage);
        expect(htmlRecorder.events.single.failureType, 'StateError');
      },
    );

    test('cardinality mismatch fails closed', () async {
      final source = _source();
      final projection =
          await ComicCommentContentProjector(
            plainTextBatchConversionService: const _MismatchedPlainService(),
            htmlTextNodeConversionService: _RecordingHtmlService(),
            diagnosticRecorder: _RecordingDiagnosticRecorder(),
          ).project(
            sessionKey: key,
            source: source,
            converter: const _TestConverter(),
          );

      expect(projection.isConverted, isFalse);
      expect(projection.items[1].displayDateline, '第二时间');
    });

    test(
      'keeps profile link text and attributes raw while converting ordinary text',
      () async {
        final plain = DefaultPlainTextBatchConversionService();
        final source = _source(
          firstMessage:
              '<a href="/home.php?mod=space&amp;uid=8">发型用户名</a>'
              '<a href="/thread-99-1-1.html">软件链接</a>'
              '<img src="/raw.jpg" alt="软件属性">',
        );

        final projection =
            await ComicCommentContentProjector(
              plainTextBatchConversionService: plain,
              htmlTextNodeConversionService: DomHtmlTextNodeConversionService(
                plainTextBatchConversionService: plain,
              ),
              diagnosticRecorder: _RecordingDiagnosticRecorder(),
            ).project(
              sessionKey: key,
              source: source,
              converter: const _ReplacingConverter(),
            );

        final html = projection.items.first.displayMessage;
        expect(html, contains('>发型用户名</a>'));
        expect(html, contains('>軟體連結</a>'));
        expect(html, contains('href="/home.php?mod=space&amp;uid=8"'));
        expect(html, contains('src="/raw.jpg"'));
        expect(html, contains('alt="软件属性"'));
      },
    );

    test('revision includes session identity and every raw comment field', () {
      final source = _source();
      final base = ComicCommentContentProjector.sourceRevisionFor(
        sessionKey: key,
        source: source,
      );
      final otherEpisode = ComicCommentContentProjector.sourceRevisionFor(
        sessionKey: const ComicCommentSessionKey(
          episodeId: 'episode-2',
          sourceTid: '573279',
        ),
        source: source,
      );
      final changedAuthor = ComicCommentContentProjector.sourceRevisionFor(
        sessionKey: key,
        source: _source(firstAuthor: '另一用户名'),
      );

      expect(otherEpisode, isNot(base));
      expect(changedAuthor, isNot(base));
      expect(base, startsWith('comic-comments:'));
      expect(base, isNot(contains('软件正文')));
      expect(base, isNot(contains('发型用户名')));
    });
  });
}

ComicCommentLoadResult _source({
  String firstAuthor = '发型用户名',
  String firstMessage = '<p>软件正文</p><img src="/image.jpg" alt="软件图片">',
}) {
  return ComicCommentLoadResult(
    sourceTid: '573279',
    status: ComicCommentLoadStatus.success,
    items: <ComicCommentItem>[
      ComicCommentItem(
        pid: 'p2',
        authorId: '8',
        authorName: firstAuthor,
        dateline: '软件时间',
        floorNumber: 2,
        rawMessage: firstMessage,
        avatarUrl: '/avatar/8',
      ),
      const ComicCommentItem(
        pid: 'p3',
        authorId: '9',
        authorName: '第二用户',
        dateline: '第二时间',
        floorNumber: 3,
        rawMessage: '<p>第二正文</p>',
        avatarUrl: '/avatar/9',
      ),
    ],
    loadedPages: const <int>{1, 2},
    expectedPages: 2,
  );
}

final class _RecordingPlainService implements PlainTextBatchConversionService {
  int callCount = 0;
  List<String> lastSources = const <String>[];

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    callCount += 1;
    lastSources = List<String>.from(sources);
    return <String>[for (final source in sources) 'P:$source'];
  }
}

final class _RecordingHtmlService extends HtmlTextNodeConversionService {
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
      throw StateError('html failed');
    }
    return <HtmlTextNodeConversionResult>[
      for (final fragment in htmlFragments)
        HtmlTextNodeConversionResult(
          html: 'H:$fragment',
          convertedTextNodeCount: 1,
          converterId: converter.id,
        ),
    ];
  }
}

final class _ThrowingPlainService implements PlainTextBatchConversionService {
  const _ThrowingPlainService();

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) {
    throw StateError('plain failed');
  }
}

final class _MismatchedPlainService implements PlainTextBatchConversionService {
  const _MismatchedPlainService();

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    return const <String>['only-one'];
  }
}

final class _RecordingDiagnosticRecorder
    implements TextConversionDiagnosticRecorder {
  final List<TextConversionDiagnosticEvent> events =
      <TextConversionDiagnosticEvent>[];

  @override
  void record(TextConversionDiagnosticEvent event) {
    events.add(event);
  }
}

final class _TestConverter implements TextConverter {
  const _TestConverter({this.mode = TextConversionMode.toTraditional});

  @override
  final TextConversionMode mode;

  @override
  String get id => 'test:${mode.name}';

  @override
  Future<String> convertHtml(String html) async => html;
}

final class _ReplacingConverter implements TextConverter {
  const _ReplacingConverter();

  @override
  String get id => 'replace:traditional';

  @override
  TextConversionMode get mode => TextConversionMode.toTraditional;

  @override
  Future<String> convertHtml(String html) async {
    return html
        .replaceAll('软件', '軟體')
        .replaceAll('链接', '連結')
        .replaceAll('时间', '時間');
  }
}
