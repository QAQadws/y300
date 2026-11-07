import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/fonts/fonts.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_layout_scroll_controller.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_reader_exit_result.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_poll_option_body.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_return_coordinator.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_capability.dart';
import 'package:y300/features/thread/presentation/thread_detail_state.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';
import 'package:y300/l10n/app_localizations.dart';

const _image =
    '<img src="https://example.test/same.png" width="100" height="40">';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 400 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    final error = tester.takeException();
    if (error != null) fail('$error');
  }
  expect(ready(), isTrue, reason: 'Actual poll body did not become ready');
}

Finder _body(String option) => find.byKey(ValueKey(('1', option)));
Finder _picture(String option, int index) => find.descendant(
  of: _body(option),
  matching: find.byKey(
    ValueKey((
      'native-readable-image',
      'thread:100:post:1:poll:$option',
      index,
    )),
  ),
);

final class _Harness {
  _Harness(this.tester, this.cache) {
    returns = ThreadImageReaderReturnCoordinator(scrollController: scroll);
  }
  final WidgetTester tester;
  final _Cache cache;
  final scroll = ReaderLayoutScrollController();
  late final ThreadImageReaderReturnCoordinator returns;
  late StateSetter update;
  final selected = <String>{};
  final requests = <ThreadImageOpenRequest>[];
  final links = <String>[];
  var selections = 0, submissions = 0, revision = 0;
  var html71 =
      '$_image<p>Alpha</p>$_image<p><a href="https://example.test/read">Open</a></p>';
  var html72 = _image;

  ThreadPost get post => ThreadPost(
    pid: '1',
    author: 'Reader',
    authorId: '2',
    number: 1,
    isFirst: true,
    dateline: 'today',
    message: '<p>Main</p>$_image',
    poll: ThreadPoll(
      isMultipleChoice: false,
      summary: 'Single choice',
      options: [
        ThreadPollOption(id: '71', label: 'Alpha Open', contentHtml: html71),
        ThreadPollOption(id: '72', label: '', contentHtml: html72),
      ],
    ),
  );

  static Future<_Harness> open(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
    bool tall = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 1400);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final cache = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('y300-poll-');
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawPaint(Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(8, 6);
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final file = File('${directory.path}/image.png');
        await file.writeAsBytes(bytes.buffer.asUint8List());
        return _Cache(file, directory);
      } finally {
        picture.dispose();
        image.dispose();
      }
    });
    final h = _Harness(tester, cache!);
    if (tall) {
      tester.view.physicalSize = const Size(500, 800);
      h.html71 = '$_image<p>${'Words ' * 300}</p>$_image';
      h.html72 = '$_image<p>${'Trailing ' * 300}</p>';
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(h.cache),
          forumHtmlReaderFontBindingProvider.overrideWithValue(
            ForumHtmlReaderFontBinding(
              preferences: ForumHtmlReaderPreferences.defaults(),
              resolution: const FontResolution(
                requestedId: FontIdentity.system,
                font: ResolvedFont.system,
              ),
              isReady: true,
            ),
          ),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                h.update = update;
                final state =
                    ThreadDetailPageState.initial(
                      tid: '100',
                      subject: 'Poll',
                    ).copyWith(
                      isLoadingInitial: false,
                      currentPage: 1,
                      hasMore: false,
                      posts: [h.post],
                      selectedPollOptionIds: Set.of(h.selected),
                      pollVoteCommandAvailable: true,
                    );
                return ThreadDetailContent(
                  key: ValueKey(h.revision),
                  state: state,
                  nativeBody: true,
                  scrollController: h.scroll,
                  imageReaderReturnCoordinator: h.returns,
                  imageReferer:
                      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
                  onLoadPreviousPage: () {},
                  onLoadNextPage: () {},
                  onLoadPageNumber: (_) {},
                  onOpenAuthorProfile: (_) {},
                  onOpenCommentAuthorProfile: (_) {},
                  onCopyActionUrl: (_, _) {},
                  onOpenPostLink: h.links.add,
                  onOpenPostActions: (_) {},
                  onTogglePollOption: (_, option) => update(() {
                    h.selections++;
                    h.selected
                      ..clear()
                      ..add(option.id);
                  }),
                  onSubmitPollVote: (_) => h.submissions++,
                  onOpenPostImages: (_, request) => h.requests.add(request),
                );
              },
            ),
          ),
        ),
      ),
    );
    await h.ready();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      h.returns.dispose();
      h.scroll.dispose();
      await tester.runAsync(() => h.cache.directory.delete(recursive: true));
    });
    return h;
  }

  Future<void> ready({bool firstImage = true}) async {
    await tester.pump();
    await _until(tester, () {
      final boxes = tester
          .widgetList<ForumBodyFlowBox>(
            firstImage
                ? find.byType(ForumBodyFlowBox)
                : find.descendant(
                    of: _body('71'),
                    matching: find.byType(ForumBodyFlowBox),
                  ),
          )
          .toList();
      return boxes.length == (firstImage ? 3 : 1) &&
          boxes.every((box) => box.prefix.isComplete);
    });
    if (firstImage) {
      await _until(tester, () => _picture('71', 0).evaluate().isNotEmpty);
    }
  }

  ForumBodyTextPageSession sessionFor(String option) => tester
      .widget<ForumBodyFlowBox>(
        find.descendant(
          of: _body(option),
          matching: find.byType(ForumBodyFlowBox),
        ),
      )
      .session;
}

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      '${locale.toLanguageTag()} rich options separate selection, image and link actions',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final h = await _Harness.open(tester, locale: locale);
          expect(find.byType(ThreadPollOptionBody), findsNWidgets(2));
          final first = h.sessionFor('71');
          await tester.tap(_picture('71', 1));
          expect(h.requests, hasLength(1));
          final request = h.requests.single;
          expect(
            (request.tid, request.pid, request.pollOptionId),
            ('100', '1', '71'),
          );
          expect(request.initialIndex, 1);
          expect(request.group.entries.map((entry) => entry.indexInPost), [
            0,
            1,
          ]);
          expect(
            request.continuousImages.every(
              (item) => item.ownerId == request.sourceOwnerId,
            ),
            isTrue,
          );
          expect(h.selections, 0);
          expect(h.submissions, 0);
          await tester.tapAt(tester.getCenter(find.bySemanticsLabel('Open')));
          expect(h.links, ['https://example.test/read']);
          expect(h.selections, 0);
          await tester.tap(find.byKey(const Key('thread-poll-option-71')));
          await h.ready();
          expect(h.selected, {'71'});
          expect(h.selections, 1);
          expect(h.submissions, 0);
          expect(h.sessionFor('71'), same(first));
          final strings = AppLocalizations.of(
            tester.element(find.byType(ThreadPollCard)),
          );
          final capability = ThreadImageReaderCapability(
            request: request,
            imageReferer: request.referer,
            title: strings.threadImageReaderTitle,
            displayLabel: strings.threadImageDisplay,
            downloadLabel: strings.threadImageDownload,
          );
          expect(capability.content.ownerId, request.sourceOwnerId);
          expect(
            capability
                .exportMetadataFor(request.continuousImages.last)
                ?.baseName,
            'Y300-thread-100-post-1-poll-71-2',
          );
          capability.retire();
          final selector = tester.widget<IconButton>(
            find.byKey(const Key('thread-poll-option-72')),
          );
          expect(selector.tooltip, strings.threadPollOptionDescription(2));
          await tester.tap(_picture('72', 0));
          expect(h.requests.last.pollOptionId, '72');
          expect(h.requests.last.group.entries, hasLength(1));
          expect(h.requests.last.sourceOwnerId, isNot(request.sourceOwnerId));
          expect(h.selected, {'71'});
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'remount preserves selection, sources and retires old option sessions',
    (tester) async {
      final h = await _Harness.open(tester);
      await tester.tap(find.byKey(const Key('thread-poll-option-71')));
      final old = [h.sessionFor('71'), h.sessionFor('72')];
      h.update(() => h.revision++);
      await h.ready();
      expect(h.selected, {'71'});
      expect(
        old.every(
          (session) => session.isClosed && session.activeIssuedFragments == 0,
        ),
        isTrue,
      );
      await tester.tap(_picture('71', 1));
      expect(h.requests.single.initialEntry?.indexInPost, 1);
      expect(h.requests.single.pollOptionId, '71');
      expect(h.submissions, 0);
      final mounted = [h.sessionFor('71'), h.sessionFor('72')];
      await tester.tap(find.byKey(const Key('thread-poll-header')));
      await tester.pump();
      expect(find.byType(ThreadPollOptionBody), findsNothing);
      expect(mounted.every((session) => session.isClosed), isTrue);
      await tester.tap(find.byKey(const Key('thread-poll-header')));
      await h.ready();
      expect(h.selected, {'71'});
      await tester.tap(_picture('71', 1));
      expect(h.requests.last.initialEntry?.indexInPost, 1);
      expect(h.requests.last.pollOptionId, '71');
    },
  );

  testWidgets(
    'gallery return reveals its own repeated occurrence, stale option HTML cannot redirect it',
    (tester) async {
      final h = await _Harness.open(tester, tall: true);
      await tester.tap(_picture('71', 0));
      final request = h.requests.single;
      final target = request.group.entries[1];
      expect(
        h.returns.anchorsFor('1'),
        isNot(same(h.returns.anchorsFor('1', pollOptionId: '71'))),
      );
      final callback = h.returns.beforeExitFor(request)!;
      final result = ThreadImageReaderExitResult(
        tid: '100',
        pid: '1',
        indexInPost: 1,
        cacheKey: target.cacheKey,
        url: target.url,
      );
      var returned = false;
      callback(result).then((_) => returned = true);
      await _until(tester, () => returned);
      expect(h.scroll.offset, greaterThan(0));
      expect(tester.getTopLeft(_picture('71', 1)).dy, closeTo(0, 2));
      final stale = h.returns.beforeExitFor(request)!;
      h.update(() => h.html71 = '${h.html71}<p>Changed</p>');
      await h.ready(firstImage: false);
      final position = h.scroll.offset;
      await stale(result);
      expect(h.scroll.offset, position);
    },
  );
}

final class _Cache implements ImageCacheService {
  _Cache(this.file, this.directory);
  final File file;
  final Directory directory;
  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async =>
      CachedImageResult(
        success: true,
        cacheKey: request.cacheKey,
        localPath: file.path,
        fromCache: true,
        width: 8,
        height: 6,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
