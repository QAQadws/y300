import 'dart:async';
import 'package:test/test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_adapters.dart';

void main() {
  test(
    'mobile HTML reads keep new snapshots when an invalidated response arrives late',
    () async {
      final network = _DeferredNetwork();
      final snapshots = _Snapshots();
      final documents = _Documents();
      final repo = ForumClientAdapterFactory(
        config: ForumClientConfig(
          siteOrigin: Uri.parse('https://example.test'),
          apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
          userAgent: 'test',
          desktopUserAgent: 'test',
        ),
        network: network,
        snapshotStore: snapshots,
        documentStore: documents,
      ).createHtmlThreadDetail();
      final old = repo.getThreadDetail(tid: '100');
      await network.started.future;
      expect(network.requests.single.uri.queryParameters['mobile'], '2');
      await (repo as ThreadReadInvalidation).invalidatePendingReads('100');
      final fresh = await repo.getThreadDetail(tid: '100');
      expect(fresh.dataOrNull!.posts.single.message, contains('fresh'));
      network.old.complete(_html('stale'));
      await old;
      expect(documents.bodies, hasLength(1));
      expect(documents.bodies.single, contains('fresh'));
      expect(snapshots.posts, ['fresh']);
      final cached = await repo.getThreadDetail(tid: '100');
      expect(cached.dataOrNull!.posts.single.message, contains('fresh'));
      expect(network.requests, hasLength(2));
    },
  );
  test('invalidation waits for a cache commit already writing', () async {
    final network = _DeferredNetwork()..old.complete(_html('old'));
    final documents = _Documents(block: true);
    final repo = ForumClientAdapterFactory(
      config: ForumClientConfig(
        siteOrigin: Uri.parse('https://example.test'),
        apiOrigin: Uri.parse('https://example.test/api/mobile/index.php'),
        userAgent: 'test',
        desktopUserAgent: 'test',
      ),
      network: network,
      documentStore: documents,
      snapshotStore: _Snapshots(),
    ).createHtmlThreadDetail();
    final read = repo.getThreadDetail(tid: '100');
    await documents.started.future;
    var invalidated = false;
    final fence = (repo as ThreadReadInvalidation)
        .invalidatePendingReads('100')
        .then((_) => invalidated = true);
    await Future<void>.delayed(Duration.zero);
    expect(invalidated, isFalse);
    documents.release.complete();
    await fence;
    await read;
    expect(invalidated, isTrue);
  });
}

class _DeferredNetwork implements ForumClientNetwork {
  final old = Completer<String>();
  final started = Completer<void>();
  final requests = <ForumRequest>[];
  @override
  Future<ForumTransportResult<ForumResponse<Object?>>> send(
    ForumRequest request,
  ) async {
    requests.add(request);
    if (!started.isCompleted) started.complete();
    final body = requests.length == 1 ? await old.future : _html('fresh');
    return ForumTransportSuccess(
      ForumResponse(
        uri: request.uri,
        statusCode: 200,
        headers: const {},
        body: body,
      ),
    );
  }
}

class _Documents implements ForumDocumentStore {
  _Documents({this.block = false});
  final bool block;
  final started = Completer<void>();
  final release = Completer<void>();
  final bodies = <String>[];
  @override
  Future<ForumCachedDocument?> get(ForumDocumentDescriptor descriptor) async =>
      null;
  @override
  Future<void> put(ForumCachedDocument document) async {
    if (!started.isCompleted) started.complete();
    if (block) await release.future;
    bodies.add(document.body);
  }

  @override
  Future<void> touch(
    ForumDocumentDescriptor descriptor,
    DateTime accessedAt,
  ) async {}
}

class _Snapshots implements ForumSnapshotStore {
  final store = MemoryForumSnapshotStore();
  final posts = <String>[];
  @override
  Future<ForumCachedSnapshot<T>?> get<T>(
    ForumSnapshotDescriptor descriptor,
    ForumSnapshotCodec<T> codec,
  ) => store.get(descriptor, codec);
  @override
  Future<void> put<T>(
    ForumSnapshotDescriptor descriptor,
    T value,
    ForumSnapshotCodec<T> codec, {
    required ForumSnapshotPolicy policy,
  }) async {
    if (value is ThreadDetailData) posts.add(value.posts.single.message);
    await store.put(descriptor, value, codec, policy: policy);
  }

  @override
  Future<void> touch(ForumSnapshotDescriptor descriptor, DateTime accessedAt) =>
      store.touch(descriptor, accessedAt);
}

String _html(String body) =>
    '''
<html><body id="forum"><div class="viewthread">
<h2 class="view_tit">Fixture thread</h2>
<div class="plc" id="pid1"><div class="display pione"><div class="authi"><a href="home.php?mod=space&amp;uid=7">author</a><span class="mtime">today</span></div>
<div class="message">$body</div></div></div>
</div></body></html>
''';
