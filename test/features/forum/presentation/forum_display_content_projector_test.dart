import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_display_models.dart';
import 'package:y300/features/forum/presentation/forum_display_content_projector.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

void main() {
  group('ForumDisplayContentProjector', () {
    test(
      'converts allowed fields and preserves raw identities in one batch',
      () async {
        final service = _PrefixBatchConversionService();
        final recorder = _RecordingDiagnosticRecorder();
        final source = _source();

        final projection = await ForumDisplayContentProjector(
          plainTextBatchConversionService: service,
          diagnosticRecorder: recorder,
        ).project(source, converter: const _TestConverter());

        expect(service.callCount, 1);
        expect(projection.isConverted, isTrue);
        expect(projection.displayTitle, 'T:漫画交流区');
        expect(projection.primaryFilters.single.displayLabel, 'T:全部主题');
        expect(projection.typeFilters.single.displayLabel, 'T:资源标签');
        expect(projection.subForums.single.displayTitle, 'T:汉化发布');
        expect(projection.topEntries.single.displayTitle, 'T:站务公告');
        expect(projection.topEntries.single.displayBadgeLabel, 'T:公告');

        final first = projection.threads.first;
        expect(first.displaySubject, 'T:测试标题');
        expect(first.displayExcerpt, 'T:测试摘要');
        expect(first.displaySourceTagName, 'T:漫画');
        expect(first.displayBadgeLabel, 'T:关闭');
        expect(first.displayDateline, 'T:昨天');
        expect(first.source.author, 'alice');
        expect(first.source.uid, '100');
        expect(first.source.threadUrl, '/thread-10-1-1.html');
        expect(first.source.isLocked, isTrue);

        final second = projection.threads[1];
        expect(second.displaySubject, 'T:第二标题');
        expect(second.displayExcerpt, 'T:第二摘要');
        expect(second.displaySourceTagName, isNull);
        expect(second.displayBadgeLabel, isNull);
        expect(
          second.displayDateline,
          'T:今天',
          reason: 'nullable fields still consume their batch slots',
        );
        expect(identical(projection.sourceState, source), isTrue);
        expect(
          identical(
            projection.primaryFilters.single.source,
            source.primaryFilters.single,
          ),
          isTrue,
        );
        expect(projection.sourceState.query.parameters['typeid'], '7');
        expect(
          () => projection.threads.add(projection.threads.first),
          throwsUnsupportedError,
        );

        expect(recorder.events, hasLength(1));
        final event = recorder.events.single;
        expect(event.surface, TextConversionSurface.forumDisplay);
        expect(event.mode, TextConversionMode.toTraditional);
        expect(event.plainSourceCount, 16);
        expect(event.sourceRevision, projection.sourceRevision);
        expect(event.failureType, isNull);
      },
    );

    test('none mode keeps server text and skips conversion', () async {
      final service = _PrefixBatchConversionService();
      final recorder = _RecordingDiagnosticRecorder();

      final projection =
          await ForumDisplayContentProjector(
            plainTextBatchConversionService: service,
            diagnosticRecorder: recorder,
          ).project(
            _source(),
            converter: const _TestConverter(mode: TextConversionMode.none),
          );

      expect(service.callCount, 0);
      expect(recorder.events, isEmpty);
      expect(projection.isConverted, isFalse);
      expect(projection.displayTitle, '漫画交流区');
      expect(projection.threads.first.displaySubject, '测试标题');
      expect(projection.threads.first.source.author, 'alice');
    });

    test(
      'invalid batch cardinality falls back atomically and is diagnosed',
      () async {
        final recorder = _RecordingDiagnosticRecorder();
        final source = _source();

        final projection = await ForumDisplayContentProjector(
          plainTextBatchConversionService: const _ShortBatchConversionService(),
          diagnosticRecorder: recorder,
        ).project(source, converter: const _TestConverter());

        expect(projection.isConverted, isFalse);
        expect(projection.displayTitle, '漫画交流区');
        expect(projection.primaryFilters.single.displayLabel, '全部主题');
        expect(projection.threads.first.displaySubject, '测试标题');
        expect(
          recorder.events.single.failureType,
          'PlainTextBatchConversionException',
        );
      },
    );
  });
}

ForumDisplayPageState _source() {
  return ForumDisplayPageState(
    fid: '30',
    title: '漫画交流区',
    currentPage: 2,
    hasMore: true,
    isLoadingInitial: false,
    isLoadingMore: false,
    query: const ForumDisplayQuery(
      fid: '30',
      page: 2,
      parameters: <String, String>{'typeid': '7', 'filter': 'typeid'},
    ),
    primaryFilters: const <ForumDisplayFilterItem>[
      ForumDisplayFilterItem(
        label: '全部主题',
        url: '/forum.php?mod=forumdisplay&fid=30',
        isSelected: true,
      ),
    ],
    typeFilters: const <ForumDisplayFilterItem>[
      ForumDisplayFilterItem(
        label: '资源标签',
        url: '/forum.php?mod=forumdisplay&fid=30&typeid=7',
        typeid: '7',
      ),
    ],
    subForums: const <ForumDisplaySubForum>[
      ForumDisplaySubForum(
        fid: '31',
        title: '汉化发布',
        url: '/forum.php?mod=forumdisplay&fid=31',
      ),
    ],
    topEntries: const <ForumDisplayTopEntry>[
      ForumDisplayTopEntry(
        tid: '9',
        title: '站务公告',
        badgeLabel: '公告',
        url: '/thread-9-1-1.html',
        isAnnouncement: true,
      ),
    ],
    threads: <ForumThreadSummary>[
      ForumThreadSummary(
        tid: '10',
        typeid: '7',
        sourceTagName: '漫画',
        subject: '测试标题',
        author: 'alice',
        replies: 3,
        views: 20,
        dateline: '昨天',
        uid: '100',
        avatarUrl: '/avatar/100',
        authorUrl: '/home.php?mod=space&uid=100',
        threadUrl: '/thread-10-1-1.html',
        excerpt: '测试摘要',
        sourceTagUrl: '/forum.php?mod=forumdisplay&fid=30&typeid=7',
        badgeLabel: '关闭',
        isLocked: true,
      ),
      ForumThreadSummary(
        tid: '11',
        subject: '第二标题',
        author: 'bob',
        replies: 0,
        views: 1,
        dateline: '今天',
        uid: '101',
        threadUrl: '/thread-11-1-1.html',
        excerpt: '第二摘要',
      ),
    ],
  );
}

class _PrefixBatchConversionService implements PlainTextBatchConversionService {
  int callCount = 0;

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    callCount += 1;
    return <String>[for (final source in sources) 'T:$source'];
  }
}

class _ShortBatchConversionService implements PlainTextBatchConversionService {
  const _ShortBatchConversionService();

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    return sources.skip(1).toList();
  }
}

class _TestConverter implements TextConverter {
  const _TestConverter({this.mode = TextConversionMode.toTraditional});

  @override
  String get id => 'test:${mode.name}';

  @override
  final TextConversionMode mode;

  @override
  Future<String> convertHtml(String html) async => html;
}

class _RecordingDiagnosticRecorder implements TextConversionDiagnosticRecorder {
  final events = <TextConversionDiagnosticEvent>[];

  @override
  void record(TextConversionDiagnosticEvent event) {
    events.add(event);
  }
}
