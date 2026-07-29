import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/presentation/forum_home_content_projector.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';

void main() {
  group('ForumHomeContentProjector', () {
    test('converts regular and forum text in one batch', () async {
      final service = _PrefixBatchConversionService();
      final recorder = _RecordingDiagnosticRecorder();
      final source = _source();
      final projection = await ForumHomeContentProjector(
        plainTextBatchConversionService: service,
        diagnosticRecorder: recorder,
      ).project(source, converter: const _TestConverter());

      expect(service.callCount, 1);
      expect(service.lastSources, <String>[
        '综合区',
        '公告区',
        '站点公告',
        '收藏区',
        '常逛版块',
      ]);
      expect(projection.isConverted, isTrue);
      expect(projection.sections[0].displayTitle, 'T:综合区');
      expect(projection.sections[0].items[0].displayTitle, 'T:公告区');
      expect(projection.sections[0].items[0].displayDescription, 'T:站点公告');
      expect(
        projection.sections[1].displayTitle,
        isNull,
        reason: 'favorite section title remains an ARB fallback',
      );
      expect(projection.sections[1].items[0].displayTitle, 'T:收藏区');
      expect(projection.sections[1].items[0].displayDescription, 'T:常逛版块');
      expect(identical(projection.source, source), isTrue);
      expect(
        identical(projection.sections[0].source, source.sections[0]),
        isTrue,
      );
      expect(projection.sections[0].source.sourceIdentity, 'regular:2');
      expect(
        () => projection.sections.add(projection.sections.first),
        throwsUnsupportedError,
      );

      expect(recorder.events, hasLength(1));
      final event = recorder.events.single;
      expect(event.surface, TextConversionSurface.forumHome);
      expect(event.mode, TextConversionMode.toTraditional);
      expect(event.plainSourceCount, 5);
      expect(event.sourceRevision, projection.sourceRevision);
      expect(event.failureType, isNull);
    });

    test(
      'none mode returns raw projection without invoking the batch service',
      () async {
        final service = _PrefixBatchConversionService();
        final recorder = _RecordingDiagnosticRecorder();

        final projection =
            await ForumHomeContentProjector(
              plainTextBatchConversionService: service,
              diagnosticRecorder: recorder,
            ).project(
              _source(),
              converter: const _TestConverter(mode: TextConversionMode.none),
            );

        expect(service.callCount, 0);
        expect(recorder.events, isEmpty);
        expect(projection.isConverted, isFalse);
        expect(projection.sections[0].displayTitle, '综合区');
        expect(projection.sections[0].items[0].displayTitle, '公告区');
      },
    );

    test('conversion failure atomically falls back to raw content', () async {
      final recorder = _RecordingDiagnosticRecorder();
      final source = _source();

      final projection = await ForumHomeContentProjector(
        plainTextBatchConversionService:
            const _ThrowingBatchConversionService(),
        diagnosticRecorder: recorder,
      ).project(source, converter: const _TestConverter());

      expect(projection.isConverted, isFalse);
      expect(projection.sections[0].displayTitle, '综合区');
      expect(projection.sections[0].items[0].displayTitle, '公告区');
      expect(projection.sections[0].items[0].displayDescription, '站点公告');
      expect(recorder.events.single.failureType, 'StateError');
    });
  });
}

ForumHomeViewData _source() {
  return ForumHomeViewData(
    isLoggedIn: true,
    sections: const <ForumSection>[
      ForumSection(
        sourceIdentity: 'regular:2',
        title: '综合区',
        items: <ForumHomeForumDisplayItem>[
          ForumHomeForumDisplayItem(
            fid: '2',
            title: '公告区',
            description: '站点公告',
            todayPosts: 3,
          ),
        ],
      ),
      ForumSection(
        sourceIdentity: 'favorite:55',
        title: '',
        type: ForumSectionType.favorite,
        items: <ForumHomeForumDisplayItem>[
          ForumHomeForumDisplayItem(
            fid: '55',
            title: '收藏区',
            description: '常逛版块',
            todayPosts: null,
          ),
        ],
      ),
    ],
  );
}

class _PrefixBatchConversionService implements PlainTextBatchConversionService {
  int callCount = 0;
  List<String> lastSources = const <String>[];

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    callCount += 1;
    lastSources = List<String>.from(sources);
    return <String>[for (final source in sources) 'T:$source'];
  }
}

class _ThrowingBatchConversionService
    implements PlainTextBatchConversionService {
  const _ThrowingBatchConversionService();

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) {
    throw StateError('conversion failed');
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
