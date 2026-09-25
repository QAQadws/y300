import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';
import 'package:yamibo_forum_client/src/adapters/thread_detail_handoff_coordinator.dart';

import '../fixtures/thread_post_navigation_fixtures.dart';

void main() {
  final config = ForumClientConfig(
    siteOrigin: Uri.parse('https://bbs.example.test'),
    apiOrigin: Uri.parse('https://api.example.test/mobile/index.php'),
    userAgent: 'mobile-fixture',
    desktopUserAgent: 'desktop-fixture',
  );
  const query = ThreadPostLocationQuery(tid: '100', pid: '200');

  test(
    'cold findpost hands the parsed detail to the matching source once',
    () async {
      final network = _RecordingNetwork(config.siteOrigin);
      final factory = ForumClientAdapterFactory(
        config: config,
        network: network,
        cookieStore: MemoryForumCookieStore(),
        sessionStore: MemoryForumSessionStore(),
      );
      final locator = factory.createThreadPostLocator();
      final detail =
          factory.createHtmlThreadDetail() as ThreadDetailHandoffReader;

      final located = (await locator.locate(query)).dataOrNull!;
      expect(located.detailHandoff, isNotNull);
      final reused = await detail.consumeHandoff(
        located.detailHandoff!,
        tid: '100',
        pid: '200',
        page: 3,
      );
      expect(reused?.dataOrNull?.posts.single.pid, '200');
      expect(network.operations, ['thread.post.locate']);
      expect(
        await detail.consumeHandoff(
          located.detailHandoff!,
          tid: '100',
          pid: '200',
          page: 3,
        ),
        isNull,
      );
      expect(network.operations, ['thread.post.locate']);

      // Subsequent ordinary reads still use the normal source, not a persisted
      // pid-to-page mapping or a replayable handoff.
      await factory.createHtmlThreadDetail().getThreadDetail(
        tid: '100',
        page: 3,
      );
      expect(network.operations, ['thread.post.locate', 'thread.detail.html']);
    },
  );

  test('warm snapshot does not override a newly located detail', () async {
    final network = _RecordingNetwork(config.siteOrigin);
    final factory = ForumClientAdapterFactory(
      config: config,
      network: network,
      cookieStore: MemoryForumCookieStore(),
      sessionStore: MemoryForumSessionStore(),
      snapshotStore: MemoryForumSnapshotStore(),
    );
    final detail = factory.createHtmlThreadDetail();
    await detail.getThreadDetail(tid: '100', page: 3);
    final located = (await factory.createThreadPostLocator().locate(
      query,
    )).dataOrNull!;
    final reused = await (detail as ThreadDetailHandoffReader).consumeHandoff(
      located.detailHandoff!,
      tid: '100',
      pid: '200',
      page: 3,
    );
    expect(reused?.dataOrNull?.posts.single.pid, '200');
    expect(network.operations, ['thread.detail.html', 'thread.post.locate']);
  });

  test('default reverse-order redirect can hand off its target page', () async {
    final network = _RecordingNetwork(
      config.siteOrigin,
      defaultReverseOrder: true,
    );
    final factory = ForumClientAdapterFactory(
      config: config,
      network: network,
      cookieStore: MemoryForumCookieStore(),
      sessionStore: MemoryForumSessionStore(),
    );
    final located = (await factory.createThreadPostLocator().locate(
      query,
    )).dataOrNull!;
    final detail =
        factory.createHtmlThreadDetail() as ThreadDetailHandoffReader;
    final reused = await detail.consumeHandoff(
      located.detailHandoff!,
      tid: '100',
      pid: '200',
      page: 3,
    );
    expect(reused?.dataOrNull?.posts.single.pid, '200');
    expect(network.operations, ['thread.post.locate']);
  });

  test(
    'mismatched target, view, and source cannot consume the handoff',
    () async {
      final network = _RecordingNetwork(config.siteOrigin);
      final cookies = MemoryForumCookieStore();
      final sessions = MemoryForumSessionStore();
      final factory = ForumClientAdapterFactory(
        config: config,
        network: network,
        cookieStore: cookies,
        sessionStore: sessions,
      );
      final detail =
          factory.createHtmlThreadDetail() as ThreadDetailHandoffReader;
      Future<ThreadDetailHandoff> locate() async =>
          (await factory.createThreadPostLocator().locate(
            query,
          )).dataOrNull!.detailHandoff!;

      for (final mismatch in <(String, String, int, ThreadDetailQuery)>[
        ('101', '200', 3, const ThreadDetailQuery()),
        ('100', '201', 3, const ThreadDetailQuery()),
        ('100', '200', 2, const ThreadDetailQuery()),
        ('100', '200', 3, const ThreadDetailQuery(authorId: '10')),
        ('100', '200', 3, const ThreadDetailQuery(reverseOrder: true)),
      ]) {
        expect(
          await detail.consumeHandoff(
            await locate(),
            tid: mismatch.$1,
            pid: mismatch.$2,
            page: mismatch.$3,
            query: mismatch.$4,
          ),
          isNull,
        );
      }
      final foreign =
          ForumClientAdapterFactory(
                config: config,
                network: network,
                cookieStore: cookies,
                sessionStore: sessions,
              ).createHtmlThreadDetail()
              as ThreadDetailHandoffReader;
      expect(
        await foreign.consumeHandoff(
          await locate(),
          tid: '100',
          pid: '200',
          page: 3,
        ),
        isNull,
      );
      expect(
        network.operations.every((value) => value == 'thread.post.locate'),
        isTrue,
      );
    },
  );

  test('Cookie, account, and cache generation changes reject reuse', () async {
    final network = _RecordingNetwork(config.siteOrigin);
    final cookies = MemoryForumCookieStore();
    final sessions = MemoryForumSessionStore();
    final factory = ForumClientAdapterFactory(
      config: config,
      network: network,
      cookieStore: cookies,
      sessionStore: sessions,
    );
    final detail = factory.createHtmlThreadDetail();
    Future<ThreadDetailHandoff> locate() async =>
        (await factory.createThreadPostLocator().locate(
          query,
        )).dataOrNull!.detailHandoff!;
    Future<void> rejected(ThreadDetailHandoff handoff) async {
      expect(
        await (detail as ThreadDetailHandoffReader).consumeHandoff(
          handoff,
          tid: '100',
          pid: '200',
          page: 3,
        ),
        isNull,
      );
    }

    final cookieHandoff = await locate();
    await cookies.merge(config.siteOrigin, {'auth': 'changed'});
    await rejected(cookieHandoff);

    final accountHandoff = await locate();
    await sessions.merge(
      ForumSessionSnapshot(
        isLoggedIn: true,
        userId: '10',
        username: 'Alice',
        formhash: '',
        updatedAt: DateTime.utc(2026),
        source: 'test',
      ),
    );
    await rejected(accountHandoff);

    final staleHandoff = await locate();
    await (detail as ThreadReadInvalidation).invalidatePendingReads('100');
    await rejected(staleHandoff);
  });

  test(
    'handoff expires after 60 seconds and never survives an unstable request',
    () async {
      final cookies = MemoryForumCookieStore();
      final sessions = MemoryForumSessionStore();
      var now = DateTime.utc(2026);
      final coordinator = ThreadDetailHandoffCoordinator(
        siteOrigin: config.siteOrigin,
        cookies: cookies,
        sessions: sessions,
        now: () => now,
      );
      final parsed = ThreadDetailHtmlParser(
        siteOrigin: config.siteOrigin,
      ).parse(mobilePostLocationHtml, fallbackTid: '100', fallbackPage: 3);
      final before = await coordinator.capture('100');
      final handoff = await coordinator.issue(
        boundary: before,
        tid: '100',
        pid: '200',
        page: 3,
        detail: parsed,
      );
      now = now.add(const Duration(seconds: 61));
      expect(
        await coordinator.consume(
          handoff!,
          tid: '100',
          pid: '200',
          page: 3,
          query: const ThreadDetailQuery(),
        ),
        isNull,
      );
      final changing = await coordinator.capture('100');
      await cookies.merge(config.siteOrigin, {'auth': 'new'});
      expect(
        await coordinator.issue(
          boundary: changing,
          tid: '100',
          pid: '200',
          page: 3,
          detail: parsed,
        ),
        isNull,
      );
    },
  );

  test('unconfirmed page identity never issues a handoff', () async {
    final network = _RecordingNetwork(config.siteOrigin, finalPage: 2);
    final factory = ForumClientAdapterFactory(
      config: config,
      network: network,
      cookieStore: MemoryForumCookieStore(),
      sessionStore: MemoryForumSessionStore(),
    );
    final located = (await factory.createThreadPostLocator().locate(
      query,
    )).dataOrNull!;
    expect(located.page, 3);
    expect(located.detailHandoff, isNull);
  });
}

final class _RecordingNetwork implements ForumClientNetwork {
  _RecordingNetwork(
    this.origin, {
    this.finalPage = 3,
    this.defaultReverseOrder = false,
  });

  final Uri origin;
  final int finalPage;
  final bool defaultReverseOrder;
  final List<String> operations = <String>[];

  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    operations.add(request.context.operation);
    return ForumTransportSuccess(
      ForumResponse<Object?>(
        uri: defaultReverseOrder
            ? origin.resolve(
                '/forum.php?mod=viewthread&tid=100&page=$finalPage&ordertype=1',
              )
            : origin.resolve('/thread-100-$finalPage-1.html'),
        statusCode: 200,
        headers: const {},
        body: mobilePostLocationHtml,
      ),
    );
  }
}
