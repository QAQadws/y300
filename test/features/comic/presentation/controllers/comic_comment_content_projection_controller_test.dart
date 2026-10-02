import 'dart:async';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projector.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_content_projection_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/html_text_node_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/identity_text_converter.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/plain_text_batch_conversion_service.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_diagnostics.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_conversion_mode.dart';
import 'package:y300/features/reader_shared/domain/rich_text/text_conversion/text_converter.dart';
import '../../data/comic_comment_fixtures.dart';

void main() {
  for (final count in [20, 200, 1000]) {
    test(
      '$count comments reuse snapshots without scanning posts per row',
      () async {
        final items = List.generate(count, (i) => _CountingCommentItem(i));
        final source = ComicCommentLoadResult(
          sourceTid: '573279',
          status: ComicCommentLoadStatus.success,
          items: items,
          loadedPages: const {1},
          expectedPages: 1,
        );
        final session = _session(_SequenceLoader([source]));
        final controller = _controller(
          session: session,
          plainService: _ImmediatePlainService(),
          initialMode: TextConversionMode.none,
          initialConverter: const IdentityTextConverter(),
        );
        addTearDown(session.dispose);
        addTearDown(controller.dispose);
        await session.load();
        final snapshot = session.state.result!;
        final projection = controller.projectionFor(snapshot);
        for (final item in items) {
          item.postReads = 0;
        }
        for (var i = 0; i < 120; i++) {
          expect(controller.projectionFor(snapshot), same(projection));
        }
        expect(items.fold(0, (sum, item) => sum + item.postReads), 0);

        final row = projection.items.first;
        expect(row.displayPost, same(row.displayPost));
        expect(items.first.postReads, 1);
      },
    );
  }

  test(
    'equal body revisions still replace pagination and command snapshots',
    () async {
      final first = ComicCommentLoadResult.fromRead(commentDetailPage());
      final second = ComicCommentLoadResult(
        sourceTid: first.sourceTid,
        status: first.status,
        items: first.items,
        loadedPages: first.loadedPages,
        expectedPages: first.expectedPages,
        nextPage: 3,
        reads: {1: commentDetailPage()},
      );
      final session = _session(_SequenceLoader([first, second]));
      final controller = _controller(
        session: session,
        plainService: _ImmediatePlainService(),
        initialMode: TextConversionMode.none,
        initialConverter: const IdentityTextConverter(),
      );
      addTearDown(session.dispose);
      addTearDown(controller.dispose);
      await session.load();
      final before = controller.projection!;
      await session.refreshAfterMutation(page: 1);
      final after = controller.projection!;
      expect(after.sourceRevision, before.sourceRevision);
      expect(after.sourceResult, same(session.state.result));
      expect(after.sourceResult.nextPage, 3);
      expect(after.sourceResult.reads[1], same(second.reads[1]));
      expect(controller.projectionFor(session.state.result!), same(after));
    },
  );

  test('converted display models are created once per projection', () {
    final source = _result('正文').items.single;
    final projection = ComicCommentItemProjection(
      sourceItem: source,
      displayMessage: '<p>轉換後</p>',
      displayDateline: '轉換時間',
    );
    final post = projection.displayPost;
    expect(post.message, '<p>轉換後</p>');
    expect(post.dateline, '轉換時間');
    expect(projection.displayPost, same(post));
    expect(source.rawMessage, '<p>正文</p>');
  });

  test(
    'unchanged refresh keeps converted text with fresh source items',
    () async {
      final first = _result('正文');
      final second = _result('正文');
      final session = _session(_SequenceLoader([first, second]));
      final plain = _ImmediatePlainService();
      final controller = _controller(
        session: session,
        plainService: plain,
        initialMode: TextConversionMode.toTraditional,
        initialConverter: const _ModeConverter(
          mode: TextConversionMode.toTraditional,
          converterId: 'traditional',
        ),
      );
      addTearDown(session.dispose);
      addTearDown(controller.dispose);
      await session.load();
      await _drain();
      final before = controller.projection!;
      final convertedStates = <bool>[];
      controller.addListener(
        () => convertedStates.add(controller.projection!.isConverted),
      );
      await session.refreshAfterMutation(page: 1);
      await _drain();
      expect(plain.callCount, 1);
      expect(convertedStates, [true]);
      expect(
        controller.projection!.items.single.sourceItem,
        same(second.items.single),
      );
      expect(
        controller.projection!.items.single.displayPost,
        same(before.items.single.displayPost),
      );
      expect(controller.projection!.sourceResult, same(session.state.result));
    },
  );

  test(
    'layout revisions ignore metadata and append, but track replacements and conversion',
    () {
      ComicCommentContentProjection projection(
        int count, {
        String message = '<p>软件</p>',
        bool converted = false,
        String metadata = 'same',
      }) {
        final source = ComicCommentLoadResult.fromRead(
          commentDetailPage(
            posts: List.generate(
              count,
              (i) => commentPost(i + 1, message: message),
            ),
          ),
        );
        return ComicCommentContentProjection(
          sourceResult: source,
          items: [
            for (final item in source.items)
              ComicCommentItemProjection(
                sourceItem: item,
                displayMessage: converted
                    ? item.rawMessage.replaceAll('软件', '軟體')
                    : item.rawMessage,
                displayDateline: item.dateline,
              ),
          ],
          mode: converted
              ? TextConversionMode.toTraditional
              : TextConversionMode.none,
          converterId: 'fixture',
          sourceRevision: metadata,
          isConverted: converted,
        );
      }

      final tracker = ComicCommentLayoutRevisionTracker();
      expect(tracker.update(projection(2)), 0);
      expect(tracker.update(projection(2, metadata: 'updated counters')), 0);
      expect(tracker.update(projection(5)), 0);
      expect(tracker.update(projection(5, converted: true)), 1);
      expect(
        tracker.update(
          projection(5, message: '<p>edited 软件</p>', converted: true),
        ),
        2,
      );
      expect(
        tracker.update(
          projection(3, message: '<p>edited 软件</p>', converted: true),
        ),
        3,
      );
    },
  );
  test(
    'projects loaded comments and mode changes never reload the session',
    () async {
      final loader = _SequenceLoader(<ComicCommentLoadResult>[_result('正文一')]);
      final session = _session(loader);
      final plain = _ImmediatePlainService();
      final controller = _controller(
        session: session,
        plainService: plain,
        initialMode: TextConversionMode.none,
        initialConverter: const IdentityTextConverter(),
      );
      addTearDown(controller.dispose);
      addTearDown(session.dispose);

      await session.load();
      expect(loader.calls, 1);
      expect(controller.projection?.isConverted, isFalse);

      controller.updateConversion(
        mode: TextConversionMode.toTraditional,
        converter: const _ModeConverter(
          mode: TextConversionMode.toTraditional,
          converterId: 'traditional',
        ),
      );
      await _drain();

      expect(loader.calls, 1);
      expect(plain.callCount, 1);
      expect(controller.projection?.isConverted, isTrue);
      expect(controller.projection?.items.single.displayDateline, 'T:软件时间');
      expect(controller.projection?.items.single.sourceItem.authorName, '用户名');

      controller.updateConversion(
        mode: TextConversionMode.toTraditional,
        converter: const _ModeConverter(
          mode: TextConversionMode.toTraditional,
          converterId: 'traditional',
        ),
      );
      await _drain();
      expect(plain.callCount, 1);
      expect(loader.calls, 1);
    },
  );

  test('rapid mode changes accept only the latest generation', () async {
    final loader = _SequenceLoader(<ComicCommentLoadResult>[_result('正文一')]);
    final session = _session(loader);
    final plain = _ControlledPlainService();
    final controller = _controller(
      session: session,
      plainService: plain,
      initialMode: TextConversionMode.none,
      initialConverter: const IdentityTextConverter(),
    );
    addTearDown(controller.dispose);
    addTearDown(session.dispose);

    await session.load();
    controller.updateConversion(
      mode: TextConversionMode.toTraditional,
      converter: const _ModeConverter(
        mode: TextConversionMode.toTraditional,
        converterId: 'traditional',
      ),
    );
    controller.updateConversion(
      mode: TextConversionMode.toSimplified,
      converter: const _ModeConverter(
        mode: TextConversionMode.toSimplified,
        converterId: 'simplified',
      ),
    );
    expect(plain.pending, hasLength(2));
    expect(controller.projection?.isConverted, isFalse);

    plain.complete('simplified');
    await _drain();
    expect(controller.projection?.converterId, 'simplified');
    expect(controller.projection?.items.single.displayDateline, 'S:软件时间');

    plain.complete('traditional');
    await _drain();
    expect(controller.projection?.converterId, 'simplified');
    expect(controller.projection?.items.single.displayDateline, 'S:软件时间');
    expect(loader.calls, 1);
  });

  test(
    'retry creates a new revision without coupling conversion to load',
    () async {
      final loader = _SequenceLoader(<ComicCommentLoadResult>[
        _result('正文一'),
        _result('正文二'),
      ]);
      final session = _session(loader);
      final plain = _ImmediatePlainService();
      final controller = _controller(
        session: session,
        plainService: plain,
        initialMode: TextConversionMode.toTraditional,
        initialConverter: const _ModeConverter(
          mode: TextConversionMode.toTraditional,
          converterId: 'traditional',
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(session.dispose);

      await session.load();
      await _drain();
      final firstRevision = controller.projection?.sourceRevision;

      await session.retry();
      await _drain();

      expect(loader.calls, 2);
      expect(plain.callCount, 2);
      expect(controller.projection?.sourceRevision, isNot(firstRevision));
      expect(
        controller.projection?.items.single.displayMessage,
        contains('正文二'),
      );
    },
  );

  test('conversion failure keeps a successful comment session raw', () async {
    final loader = _SequenceLoader(<ComicCommentLoadResult>[_result('正文一')]);
    final session = _session(loader);
    final controller = _controller(
      session: session,
      plainService: const _ThrowingPlainService(),
      initialMode: TextConversionMode.toTraditional,
      initialConverter: const _ModeConverter(
        mode: TextConversionMode.toTraditional,
        converterId: 'traditional',
      ),
    );
    addTearDown(controller.dispose);
    addTearDown(session.dispose);

    await session.load();
    await _drain();

    expect(session.state.result?.status, ComicCommentLoadStatus.success);
    expect(session.state.isLoading, isFalse);
    expect(controller.isConverting, isFalse);
    expect(controller.projection?.isConverted, isFalse);
    expect(controller.projection?.items.single.displayMessage, contains('正文一'));
  });

  test('dispose ignores a late conversion result', () async {
    final loader = _SequenceLoader(<ComicCommentLoadResult>[_result('正文一')]);
    final session = _session(loader);
    final plain = _ControlledPlainService();
    final controller = _controller(
      session: session,
      plainService: plain,
      initialMode: TextConversionMode.toTraditional,
      initialConverter: const _ModeConverter(
        mode: TextConversionMode.toTraditional,
        converterId: 'traditional',
      ),
    );
    addTearDown(session.dispose);

    await session.load();
    expect(plain.pending, hasLength(1));
    controller.dispose();
    plain.complete('traditional');
    await _drain();

    expect(loader.calls, 1);
  });
}

ComicCommentSessionController _session(_SequenceLoader loader) {
  return ComicCommentSessionController(
    key: const ComicCommentSessionKey(
      episodeId: 'episode-1',
      sourceTid: '573279',
    ),
    loader: loader,
    maxAutomaticAttempts: 1,
  );
}

ComicCommentContentProjectionController _controller({
  required ComicCommentSessionController session,
  required PlainTextBatchConversionService plainService,
  required TextConversionMode initialMode,
  required TextConverter initialConverter,
}) {
  return ComicCommentContentProjectionController(
    session: session,
    projector: ComicCommentContentProjector(
      plainTextBatchConversionService: plainService,
      htmlTextNodeConversionService: _ModeHtmlService(),
      diagnosticRecorder: const NoopTextConversionDiagnosticRecorder(),
    ),
    initialMode: initialMode,
    initialConverter: initialConverter,
  );
}

Future<void> _drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

ComicCommentLoadResult _result(String message) {
  return ComicCommentLoadResult(
    sourceTid: '573279',
    status: ComicCommentLoadStatus.success,
    items: <ComicCommentItem>[
      ComicCommentItem(
        pid: 'p2',
        authorId: '8',
        authorName: '用户名',
        dateline: '软件时间',
        floorNumber: 2,
        rawMessage: '<p>$message</p>',
        avatarUrl: '/avatar/8',
      ),
    ],
    loadedPages: const <int>{1},
    expectedPages: 1,
  );
}

final class _SequenceLoader implements ComicCommentLoader {
  _SequenceLoader(this.results);

  final List<ComicCommentLoadResult> results;
  int calls = 0;

  @override
  Future<ComicCommentLoadResult> loadPage({
    int page = 1,
    required String sourceTid,
    ComicCommentCancellationToken? cancellationToken,
  }) async {
    return results[calls++];
  }
}

class _CountingCommentItem extends ComicCommentItem {
  _CountingCommentItem(int i)
    : super(
        pid: 'p$i',
        authorId: '8',
        authorName: 'author',
        dateline: 'date',
        floorNumber: i + 1,
        rawMessage: '<p>comment $i</p>',
        avatarUrl: null,
      );

  int postReads = 0;
  @override
  ThreadPost get post {
    postReads++;
    return super.post;
  }
}

final class _ImmediatePlainService implements PlainTextBatchConversionService {
  int callCount = 0;

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) async {
    callCount += 1;
    final prefix = converter.id == 'simplified' ? 'S:' : 'T:';
    return <String>[for (final source in sources) '$prefix$source'];
  }
}

final class _ControlledPlainService implements PlainTextBatchConversionService {
  final Map<String, _PendingPlainConversion> _pending =
      <String, _PendingPlainConversion>{};

  List<String> get pending => _pending.keys.toList(growable: false);

  @override
  Future<List<String>> convertAll({
    required List<String> sources,
    required TextConverter converter,
  }) {
    final pending = _PendingPlainConversion(
      sources: List<String>.from(sources),
    );
    _pending[converter.id] = pending;
    return pending.completer.future;
  }

  void complete(String converterId) {
    final pending = _pending.remove(converterId)!;
    final prefix = converterId == 'simplified' ? 'S:' : 'T:';
    pending.completer.complete(<String>[
      for (final source in pending.sources) '$prefix$source',
    ]);
  }
}

final class _PendingPlainConversion {
  _PendingPlainConversion({required this.sources});

  final List<String> sources;
  final Completer<List<String>> completer = Completer<List<String>>();
}

final class _ModeHtmlService extends HtmlTextNodeConversionService {
  @override
  Future<List<HtmlTextNodeConversionResult>> convertAll({
    required List<String> htmlFragments,
    required TextConverter converter,
    HtmlTextNodeConversionOptions options =
        const HtmlTextNodeConversionOptions(),
  }) async {
    final prefix = converter.id == 'simplified' ? 'S:' : 'T:';
    return <HtmlTextNodeConversionResult>[
      for (final html in htmlFragments)
        HtmlTextNodeConversionResult(
          html: '$prefix$html',
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
    throw StateError('conversion failed');
  }
}

final class _ModeConverter implements TextConverter {
  const _ModeConverter({required this.mode, required this.converterId});

  @override
  final TextConversionMode mode;
  final String converterId;

  @override
  String get id => converterId;

  @override
  Future<String> convertHtml(String html) async => html;
}
