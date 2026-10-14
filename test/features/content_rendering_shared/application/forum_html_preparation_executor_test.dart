import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/content_rendering_shared/application/host/cache_forum_html_prepared_image_resource.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  group('ForumHtmlPreparationExecutor', () {
    test(
      'optional safe plan has identical worker and synchronous boundaries',
      () async {
        final executor = ForumHtmlPreparationExecutor();
        addTearDown(executor.dispose);
        final html = List.generate(
          3000,
          (index) => 'paragraph number $index with words',
        ).join('<br>');
        final request = _request(
          html,
          preparer: const DefaultForumHtmlRenderPreparer(
            enablePlainTextLinks: true,
            enableSafeDisplayPlanning: true,
          ),
        );
        final direct = request.prepareSynchronously();
        final lease = executor.tryAcquire(request)!;
        final worker = (await lease.future)!;
        lease.release();
        expect(worker.safeDisplayPlan!.isChunked, isTrue);
        expect(
          worker.safeDisplayPlan!.chunks.map(
            (chunk) => (chunk.html, chunk.startUnit, chunk.endUnit),
          ),
          direct.safeDisplayPlan!.chunks.map(
            (chunk) => (chunk.html, chunk.startUnit, chunk.endUnit),
          ),
        );
        expect(worker.safeDisplayPlan!.chunks.first.endUnit, 48);
        expect(worker.preparedHtml, direct.preparedHtml);
        expect(_projection(worker), _projection(direct));
        expect(_request(html).prepareSynchronously().safeDisplayPlan, isNull);
      },
    );
    test(
      'real worker output matches synchronous HTML and cache resources',
      () async {
        final executor = ForumHtmlPreparationExecutor(codeUnitThreshold: 0);
        addTearDown(executor.dispose);
        for (final theme in [_lightTheme, _darkTheme]) {
          for (final preserveSize in [false, true]) {
            final request = _request(
              _equivalenceHtml,
              theme: theme,
              preferences: ForumHtmlReaderPreferences.defaults().copyWith(
                preserveAuthorFontSize: preserveSize,
              ),
              preparer: const DefaultForumHtmlRenderPreparer(
                enablePlainTextLinks: true,
              ),
            );
            expect(executor.usesBackground(request), isTrue);
            final synchronous = request.prepareSynchronously();
            final lease = executor.tryAcquire(request)!;
            final background = (await lease.future)!;
            lease.release();
            await _drain();
            expect(_projection(background), _projection(synchronous));
            expect(background.sequence.entries, hasLength(1));
            // This count describes retained readable images after attachment
            // deduplication, rather than the number of removed attachments.
            expect(background.duplicatedReadableUrlCount, 0);
            expect(
              background.preparedHtml,
              contains('href="https://example.com/'),
            );
            expect(
              background.sequence.entries.single.resource,
              isA<CacheForumHtmlPreparedImageResource>(),
            );
            expect(executor.activeCount, 0);
          }
        }
      },
    );

    test(
      'pure background input can prepare on a different real isolate',
      () async {
        final callingIsolate = Isolate.current.hashCode;
        int? preparingIsolate;
        final executor = ForumHtmlPreparationExecutor(
          codeUnitThreshold: 0,
          worker: (input) async {
            final result = await Isolate.run(
              () => (Isolate.current.hashCode, input.prepare()),
            );
            preparingIsolate = result.$1;
            return result.$2;
          },
        );
        addTearDown(executor.dispose);
        final lease = executor.tryAcquire(_request(_equivalenceHtml))!;
        expect((await lease.future)!.sequence.sourceId, 'body');
        lease.release();
        expect(preparingIsolate, isNotNull);
        expect(preparingIsolate, isNot(callingIsolate));
      },
    );

    test(
      'same request shares running work and releasing one consumer preserves the other',
      () async {
        final worker = _ControlledWorker();
        final executor = _executor(worker);
        final request = _request('<p>shared</p>');
        final first = executor.tryAcquire(request)!;
        final second = executor.tryAcquire(request)!;
        expect(worker.jobs, hasLength(1));
        expect(second.future, same(first.future));
        expect(executor.activeCount, 1);
        first.release();
        first.release();
        expect(executor.activeCount, 1);
        worker.complete(0);
        expect((await second.future)!.preparedHtml, contains('shared'));
        second.release();
        await _drain();
        expect(executor.activeCount, 0);
        final third = executor.tryAcquire(request)!;
        expect(
          worker.jobs,
          hasLength(2),
          reason: 'There is no completed cache.',
        );
        worker.complete(1);
        await third.future;
        third.release();
      },
    );

    test('parallel workers and queued entry count remain bounded', () async {
      final worker = _ControlledWorker();
      final executor = _executor(worker, maxConcurrent: 2, maxQueued: 2);
      final leases = <ForumHtmlPreparationLease>[
        for (var index = 0; index < 4; index++)
          executor.tryAcquire(_request('request-$index'))!,
      ];
      expect(executor.activeCount, 2);
      expect(executor.queuedCount, 2);
      expect(worker.jobs, hasLength(2));
      expect(executor.tryAcquire(_request('excess')), isNull);
      worker.complete(0);
      await _drain();
      expect(executor.activeCount, 2);
      expect(executor.queuedCount, 1);
      expect(worker.jobs[2].input.html, 'request-2');
      worker.complete(1);
      await _drain();
      expect(executor.activeCount, 2);
      expect(executor.queuedCount, 0);
      expect(worker.jobs[3].input.html, 'request-3');
      worker.complete(2);
      worker.complete(3);
      await Future.wait(leases.map((lease) => lease.future));
      for (final lease in leases) {
        lease.release();
      }
      await _drain();
      expect(executor.activeCount, 0);
      expect(executor.queuedCodeUnits, 0);
    });

    test(
      'queued UTF-16 budget includes inputs once and cancellation frees it',
      () async {
        final worker = _ControlledWorker();
        final executor = _executor(
          worker,
          maxQueued: 10,
          maxQueuedCodeUnits: 8,
        );
        final running = executor.tryAcquire(_request('running'))!;
        final queuedRequest = _request('🙂🙂🙂');
        final queued = executor.tryAcquire(queuedRequest)!;
        final sharedQueued = executor.tryAcquire(queuedRequest)!;
        expect(executor.queuedCount, 1);
        expect(executor.queuedCodeUnits, 6);
        expect(executor.tryAcquire(_request('four')), isNull);
        queued.release();
        expect(executor.queuedCodeUnits, 6);
        sharedQueued.release();
        expect(await sharedQueued.future, isNull);
        expect(executor.queuedCount, 0);
        expect(executor.queuedCodeUnits, 0);
        final replacement = executor.tryAcquire(_request('four'))!;
        expect(executor.queuedCodeUnits, 4);
        worker.complete(0);
        await running.future;
        running.release();
        await _drain();
        expect(worker.jobs, hasLength(2));
        expect(worker.jobs.last.input.html, 'four');
        worker.complete(1);
        await replacement.future;
        replacement.release();
        await _drain();
        expect(executor.activeCount, 0);
      },
    );

    test(
      'retired running work holds its slot until actual completion',
      () async {
        final worker = _ControlledWorker();
        final executor = _executor(worker, maxQueued: 0);
        final running = executor.tryAcquire(_request('old'))!;
        running.release();
        expect(executor.activeCount, 1);
        expect(executor.tryAcquire(_request('next')), isNull);
        worker.complete(0);
        await running.future;
        await _drain();
        expect(executor.activeCount, 0);
        final next = executor.tryAcquire(_request('next'))!;
        worker.complete(1);
        await next.future;
        next.release();
      },
    );

    test(
      'disposing retires queued inputs and rejects new admissions',
      () async {
        final worker = _ControlledWorker();
        final executor = ForumHtmlPreparationExecutor(
          codeUnitThreshold: 0,
          worker: worker.call,
        );
        var notifications = 0;
        executor.addListener(() => notifications++);
        final running = executor.tryAcquire(_request('running'))!;
        final queued = executor.tryAcquire(_request('queued'))!;
        executor.dispose();
        expect(await queued.future, isNull);
        expect(executor.queuedCount, 0);
        expect(executor.queuedCodeUnits, 0);
        expect(executor.activeCount, 1);
        expect(() => executor.tryAcquire(_request('new')), throwsStateError);
        running.release();
        queued.release();
        worker.complete(0);
        await running.future;
        await _drain();
        expect(executor.activeCount, 0);
        expect(worker.jobs, hasLength(1));
        expect(notifications, 0);
      },
    );

    test('unknown configuration stays outside the background boundary', () {
      final executor = ForumHtmlPreparationExecutor(codeUnitThreshold: 0);
      addTearDown(executor.dispose);
      final unsupported = <ForumHtmlRenderPreparer>[
        _SensitivePreparer(),
        _DefaultSubclass(),
        DefaultForumHtmlRenderPreparer(fragmentCodec: _CountingCodec()),
        const DefaultForumHtmlRenderPreparer(
          urlResolver: SiteUrlResolver(siteOrigin: 'https://example.com/'),
        ),
        const DefaultForumHtmlRenderPreparer(imagePolicy: _RejectImages()),
        const DefaultForumHtmlRenderPreparer(
          imageDeduplicator: ForumHtmlImageDeduplicator(
            resolveUrl: _identityUrl,
          ),
        ),
        const DefaultForumHtmlRenderPreparer(
          imageRequestResolver: _RequestResolverSubclass(),
        ),
        const DefaultForumHtmlRenderPreparer(
          themeAdapter: DefaultForumHtmlThemeAdapter(
            contrast: _InjectedContrast(),
          ),
        ),
      ];
      for (final preparer in unsupported) {
        final request = _request('long-enough', preparer: preparer);
        expect(request.backgroundInput, isNull);
        expect(executor.usesBackground(request), isFalse);
        expect(() => executor.tryAcquire(request), throwsArgumentError);
      }
    });
  });

  group('ForumHtmlPreparationController', () {
    test('small default and unknown preparers remain synchronous', () {
      final worker = _ControlledWorker();
      final executor = _executor(worker, codeUnitThreshold: 100);
      final controller = ForumHtmlPreparationController(executor: executor);
      addTearDown(controller.dispose);
      final small = controller.resolve(_request('<p>small</p>'))!;
      expect(small.preparedHtml, contains('small'));
      final codec = _CountingCodec();
      final injected = DefaultForumHtmlRenderPreparer(fragmentCodec: codec);
      final long = _request('long' * 100, preparer: injected);
      expect(controller.resolve(long), isNotNull);
      expect(codec.parseCount, 1);
      expect(controller.resolve(long), isNotNull);
      expect(codec.parseCount, 1);
      expect(worker.jobs, isEmpty);
    });

    test(
      'default layout-only preferences reuse pending and completed preparation',
      () async {
        final worker = _ControlledWorker();
        final executor = _executor(worker);
        final controller = ForumHtmlPreparationController(executor: executor);
        addTearDown(controller.dispose);
        final preferences = ForumHtmlReaderPreferences.defaults();
        final changed = preferences.copyWith(
          typography: preferences.typography.copyWith(
            fontScale: 2,
            lineHeightScale: 1.8,
            paragraphSpacing: 20,
          ),
        );
        final first = _request('<p>layout</p>', preferences: preferences);
        final layoutOnly = _request('<p>layout</p>', preferences: changed);
        expect(first.identity, layoutOnly.identity);
        expect(controller.resolve(first), isNull);
        expect(controller.resolve(layoutOnly), isNull);
        expect(worker.jobs, hasLength(1));
        worker.complete(0);
        await _drain();
        final document = controller.resolve(layoutOnly)!;
        expect(controller.resolve(first), same(document));
        expect(worker.jobs, hasLength(1));
        final authorSize = _request(
          '<p>layout</p>',
          preferences: changed.copyWith(preserveAuthorFontSize: false),
        );
        expect(controller.resolve(authorSize), isNull);
        expect(worker.jobs, hasLength(2));
        worker.complete(1);
        await _drain();
        expect(controller.resolve(authorSize), isNot(same(document)));
      },
    );

    test(
      'custom preparers retain full preference identity and synchronous retry',
      () {
        final worker = _ControlledWorker();
        final executor = _executor(worker);
        final controller = ForumHtmlPreparationController(executor: executor);
        addTearDown(controller.dispose);
        final preparer = _SensitivePreparer();
        final preferences = ForumHtmlReaderPreferences.defaults();
        final first = _request(
          'custom',
          preparer: preparer,
          preferences: preferences,
        );
        final document = controller.resolve(first)!;
        expect(controller.resolve(first), same(document));
        expect(preparer.calls, 1);
        final changed = _request(
          'custom',
          preparer: preparer,
          preferences: preferences.copyWith(
            typography: preferences.typography.copyWith(fontScale: 2),
          ),
        );
        expect(controller.resolve(changed)!.preparedHtml, contains('2.0'));
        expect(preparer.calls, 2);
        preparer.failNext = true;
        controller.reset();
        expect(() => controller.resolve(first), throwsStateError);
        expect(controller.resolve(first), isNotNull);
        expect(preparer.calls, 4);
        expect(worker.jobs, isEmpty);
      },
    );

    test(
      'capacity notification admits a waiting consumer without UI preparation',
      () async {
        final worker = _ControlledWorker();
        final executor = _executor(worker, maxQueued: 0);
        final first = ForumHtmlPreparationController(executor: executor);
        final waiting = ForumHtmlPreparationController(executor: executor);
        addTearDown(first.dispose);
        addTearDown(waiting.dispose);
        var notifications = 0;
        waiting.addListener(() => notifications++);
        final firstRequest = _request('first');
        final waitingRequest = _request('waiting');
        expect(first.resolve(firstRequest), isNull);
        expect(waiting.resolve(waitingRequest), isNull);
        expect(executor.activeCount, 1);
        expect(executor.queuedCount, 0);
        expect(worker.jobs, hasLength(1));
        worker.complete(0);
        await _drain();
        expect(worker.jobs, hasLength(2));
        expect(worker.jobs[1].input.html, 'waiting');
        expect(waiting.resolve(waitingRequest), isNull);
        expect(notifications, 0);
        worker.complete(1);
        await _drain();
        expect(
          waiting.resolve(waitingRequest)!.preparedHtml,
          contains('waiting'),
        );
        expect(notifications, 1);
      },
    );

    test(
      'resetting queued and waiting consumers removes their pending work',
      () async {
        final worker = _ControlledWorker();
        final executor = _executor(worker, maxQueued: 1);
        final running = ForumHtmlPreparationController(executor: executor);
        final queued = ForumHtmlPreparationController(executor: executor);
        final waiting = ForumHtmlPreparationController(executor: executor);
        addTearDown(running.dispose);
        addTearDown(queued.dispose);
        addTearDown(waiting.dispose);
        running.resolve(_request('running'));
        queued.resolve(_request('queued'));
        waiting.resolve(_request('waiting'));
        expect(executor.queuedCount, 1);
        queued.reset();
        waiting.reset();
        expect(executor.queuedCount, 0);
        expect(executor.queuedCodeUnits, 0);
        worker.complete(0);
        await _drain();
        expect(worker.jobs, hasLength(1));
        expect(queued.identity, isNull);
        expect(waiting.identity, isNull);
      },
    );

    test(
      'A to B to A retires callbacks while exact in-flight A can be shared',
      () async {
        final worker = _ControlledWorker();
        final executor = _executor(worker);
        final controller = ForumHtmlPreparationController(executor: executor);
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.addListener(() => notifications++);
        final a = _request('A');
        final b = _request('B');
        controller.resolve(a);
        controller.resolve(b);
        expect(executor.queuedCount, 1);
        controller.resolve(a);
        expect(executor.queuedCount, 0);
        expect(worker.jobs, hasLength(1));
        worker.complete(0);
        await _drain();
        expect(controller.identity, a.identity);
        expect(controller.resolve(a)!.preparedHtml, 'A');
        expect(
          notifications,
          1,
          reason: 'The retired first A must not publish.',
        );
        expect(worker.jobs, hasLength(1), reason: 'Retired B never starts.');
      },
    );

    test(
      'HTML owner and theme replacements reject out-of-order results',
      () async {
        final worker = _ControlledWorker();
        final executor = _executor(worker, maxConcurrent: 3);
        final controller = ForumHtmlPreparationController(executor: executor);
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.addListener(() => notifications++);
        final original = _request(_equivalenceHtml);
        final owner = _request(_equivalenceHtml, owner: 'owner-b');
        final theme = _request(
          _equivalenceHtml,
          owner: 'owner-b',
          theme: _darkTheme,
        );
        controller.resolve(original);
        controller.resolve(owner);
        controller.resolve(theme);
        expect(worker.jobs, hasLength(3));
        worker.complete(1);
        worker.complete(0);
        await _drain();
        expect(controller.identity, theme.identity);
        expect(controller.resolve(theme), isNull);
        expect(notifications, 0);
        worker.complete(2);
        await _drain();
        final current = controller.resolve(theme)!;
        expect(current.themeSignature, _darkTheme.signature);
        expect(_projection(current), _projection(theme.prepareSynchronously()));
        expect(
          (current.sequence.entries.single.resource
                  as CacheForumHtmlPreparedImageResource)
              .request
              .ownerId,
          'owner-b',
        );
        expect(notifications, 1);
      },
    );

    test('a failed background request can retry after reset', () async {
      final worker = _ControlledWorker();
      final executor = _executor(worker);
      final controller = ForumHtmlPreparationController(executor: executor);
      addTearDown(controller.dispose);
      final request = _request('retry');
      controller.resolve(request);
      worker.fail(0);
      await _drain();
      expect(controller.hasError, isTrue);
      expect(() => controller.resolve(request), throwsStateError);
      controller.reset();
      expect(controller.hasError, isFalse);
      expect(controller.resolve(request), isNull);
      expect(worker.jobs, hasLength(2));
      worker.complete(1);
      await _drain();
      expect(controller.resolve(request)!.preparedHtml, 'retry');
    });

    test('closed controller rejects late success and late failure', () async {
      final worker = _ControlledWorker();
      final executor = _executor(worker, maxConcurrent: 2);
      final controller = ForumHtmlPreparationController(executor: executor);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.resolve(_request('first'));
      controller.resolve(_request('second'));
      controller.dispose();
      expect(controller.identity, isNull);
      expect(executor.activeCount, 2);
      worker.complete(0);
      worker.fail(1);
      await _drain();
      expect(notifications, 0);
      expect(controller.hasError, isFalse);
      expect(executor.activeCount, 0);
      expect(() => controller.resolve(_request('third')), throwsStateError);
    });
  });
}

ForumHtmlPreparationExecutor _executor(
  _ControlledWorker worker, {
  int codeUnitThreshold = 0,
  int maxConcurrent = 1,
  int maxQueued = 16,
  int maxQueuedCodeUnits = 512 * 1024,
}) {
  final executor = ForumHtmlPreparationExecutor(
    codeUnitThreshold: codeUnitThreshold,
    maxConcurrent: maxConcurrent,
    maxQueued: maxQueued,
    maxQueuedCodeUnits: maxQueuedCodeUnits,
    worker: worker.call,
  );
  addTearDown(executor.dispose);
  return executor;
}

ForumHtmlPreparationRequest _request(
  String html, {
  String owner = 'owner-a',
  ForumHtmlThemeContext theme = _lightTheme,
  ForumHtmlReaderPreferences? preferences,
  ForumHtmlRenderPreparer preparer = const DefaultForumHtmlRenderPreparer(),
}) => ForumHtmlPreparationRequest(
  html: html,
  preferences: preferences ?? ForumHtmlReaderPreferences.defaults(),
  theme: theme,
  sourceId: 'body',
  threadId: '100',
  imageCacheOwnerId: owner,
  preparer: preparer,
);

Future<void> _drain() => Future<void>.delayed(Duration.zero);

final class _ControlledWorker {
  final jobs =
      <
        ({
          ForumHtmlBackgroundPreparationInput input,
          Completer<ForumHtmlPreparedRenderDocument> result,
        })
      >[];

  Future<ForumHtmlPreparedRenderDocument> call(
    ForumHtmlBackgroundPreparationInput input,
  ) {
    final result = Completer<ForumHtmlPreparedRenderDocument>();
    jobs.add((input: input, result: result));
    return result.future;
  }

  void complete(int index) =>
      jobs[index].result.complete(jobs[index].input.prepare());
  void fail(int index) =>
      jobs[index].result.completeError(StateError('fixture failure'));
}

final class _CountingCodec implements ForumHtmlFragmentCodec {
  int parseCount = 0;
  final _delegate = const HtmlPackageForumHtmlFragmentCodec();

  @override
  html_dom.DocumentFragment parse(String html) {
    parseCount++;
    return _delegate.parse(html);
  }

  @override
  String serialize(html_dom.DocumentFragment fragment) =>
      _delegate.serialize(fragment);
}

class _SensitivePreparer implements ForumHtmlRenderPreparer {
  int calls = 0;
  bool failNext = false;

  @override
  ForumHtmlPreparedRenderDocument prepare({
    required String html,
    required ForumHtmlReaderPreferences preferences,
    required ForumHtmlThemeContext theme,
    required String sourceId,
    required String? threadId,
    required String? imageCacheOwnerId,
  }) {
    calls++;
    if (failNext) {
      failNext = false;
      throw StateError('fixture synchronous failure');
    }
    return const DefaultForumHtmlRenderPreparer().prepare(
      html: '<p>$html ${preferences.typography.fontScale}</p>',
      preferences: preferences,
      theme: theme,
      sourceId: sourceId,
      threadId: threadId,
      imageCacheOwnerId: imageCacheOwnerId,
    );
  }
}

class _DefaultSubclass extends DefaultForumHtmlRenderPreparer {}

class _RequestResolverSubclass extends DefaultForumImageRequestResolver {
  const _RequestResolverSubclass();
}

final class _InjectedContrast implements RichTextColorContrast {
  const _InjectedContrast();

  @override
  Color composite(Color foreground, Color background) =>
      const FlutterRichTextColorContrast().composite(foreground, background);

  @override
  double contrastRatio(Color first, Color second) =>
      const FlutterRichTextColorContrast().contrastRatio(first, second);
}

final class _RejectImages implements ForumHtmlPreparationImagePolicy {
  const _RejectImages();

  @override
  ForumHtmlPreparedImageResource? prepareInline({
    required Uri url,
    required String? threadId,
    required String? imageCacheOwnerId,
    required int imageIndex,
    double? htmlWidth,
    double? htmlHeight,
    String? alt,
    String? title,
  }) => null;
}

String? _identityUrl(String raw) => raw;

Object _projection(ForumHtmlPreparedRenderDocument document) {
  final stats = document.themeAdaptationStats;
  return {
    'html': document.preparedHtml,
    'source': document.sequence.sourceId,
    'images': [
      for (final image in document.sequence.entries)
        {
          'index': image.index,
          'url': image.url,
          'raw': image.rawSrc,
          'attachment': image.attachmentId,
          'alt': image.alt,
          'title': image.title,
          'width': image.htmlWidth,
          'height': image.htmlHeight,
          'cache': image.cacheKey,
          'resource': _cacheResourceProjection(
            image.resource as CacheForumHtmlPreparedImageResource,
          ),
        },
    ],
    'attachments': document.attachmentIdsByUrl,
    'counts': [
      document.totalImageCount,
      document.skippedStickerCount,
      document.skippedNonNetworkCount,
      document.duplicatedReadableUrlCount,
      document.attachmentTaggedCount,
    ],
    'theme': document.themeSignature,
    'stats': [
      stats.explicitForegroundCount,
      stats.remappedForegroundCount,
      stats.explicitBackgroundCount,
      stats.remappedBackgroundCount,
      stats.semanticFallbackCount,
      stats.unsupportedColorCount,
      stats.concealedTextRangeCount,
      stats.minimumResultContrast,
    ],
  };
}

Object _cacheResourceProjection(CacheForumHtmlPreparedImageResource resource) {
  final spec = resource.spec;
  final request = resource.request;
  return {
    'spec': [
      spec.kind,
      spec.url.toString(),
      spec.referer,
      spec.ownerId,
      spec.ownerType,
      spec.episodeId,
      spec.imageIndex,
      spec.cacheKey,
      spec.retentionClass,
      spec.htmlWidth,
      spec.htmlHeight,
      spec.displayWidth,
      spec.displayHeight,
      spec.alt,
      spec.title,
      spec.protected,
      spec.allowReaderOpen,
    ],
    'request': [
      request.cacheKey,
      request.sourceUrl,
      request.referer,
      request.ownerType,
      request.ownerId,
      request.role,
      request.episodeId,
      request.imageIndex,
      request.protected,
      request.retentionClass,
    ],
  };
}

const _equivalenceHtml =
    '<!-- preserved metadata -->'
    '<font size="5" color="black" style="font-weight:bold">正文🙂</font>'
    '<div class="quote"><blockquote>引用正文</blockquote></div>'
    '<span style="background-color:white;color:white">隐藏文字</span>'
    '<span style="color:red!important;color:blue">https://example.com/正文</span>'
    '<div class="showcollapse_box" id="fold"><div class="showcollapse_title">标题</div>'
    '<div class="showcollapse_content">折叠正文<br>下一行</div></div>'
    '<img id="aimg_9" src="data/attachment/forum/page.jpg" width="120" height="80" '
    'alt="样本" title="图片">'
    '<img id="aimg_9" src="https://bbs.yamibo.com/data/attachment/forum/page.jpg">';

const _lightTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFFAFAFA),
  foreground: Color(0xFF202020),
  link: Color(0xFF1565C0),
  quoteSurface: Color(0xFFF0F0F0),
  quoteForeground: Color(0xFF303030),
  codeSurface: Color(0xFFEDEDED),
  codeForeground: Color(0xFF202020),
);

const _darkTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.dark,
  surface: Color(0xFF15171A),
  foreground: Color(0xFFE3E3E3),
  link: Color(0xFF90CAF9),
  quoteSurface: Color(0xFF24272B),
  quoteForeground: Color(0xFFD1D1D1),
  codeSurface: Color(0xFF24272B),
  codeForeground: Color(0xFFE3E3E3),
);
