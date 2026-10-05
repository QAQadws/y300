import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart' as forum;
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/core/network/yamibo_forum_client_host_adapters.dart';
import 'package:y300/core/network/yamibo_forum_source_cache.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo_forum_home_cache_owner.dart';
import 'package:y300/features/cache/data/services/document_cache_service.dart';
import 'package:y300/features/cache/data/services/parsed_snapshot_cache_service.dart';
import 'package:y300/core/persistence/app_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('only registered profiles resolve and scope boot reads stay local', () {
    final catalog = Y300ForumSourceCatalog(const [
      Y300ForumSourceProfile.parsing,
    ]);
    expect(catalog.resolve('parsing'), same(Y300ForumSourceProfile.parsing));
    expect(() => catalog.resolve('unavailable'), throwsStateError);
    final sessions = YamiboSessionStore();
    final container = ProviderContainer.test(
      overrides: [yamiboSessionStoreProvider.overrideWithValue(sessions)],
    );
    final initial = container.read(yamiboForumSourceScopeProvider);
    expect(initial.accountId, 'unverified');
    expect(initial.isCurrent, isTrue);
    sessions.saveExtracted(_identity('0'));
    final anonymous = container.read(yamiboForumSourceScopeProvider);
    expect(anonymous.accountId, 'anonymous');
    expect(anonymous.generation, initial.generation + 1);
    expect(initial.cancellation.isCancelled, isTrue);
  });

  test('formhash changes keep flow ownership, account changes cancel it', () {
    final sessions = YamiboSessionStore()..saveExtracted(_identity('42'));
    final runtime = _runtime(sessions);
    final original = runtime.current;
    sessions.saveExtracted(_identity('42', formhash: 'renewed'));
    expect(runtime.current, same(original));
    sessions.saveExtracted(_identity('43'));
    expect(original.isCurrent, isFalse);
    expect(runtime.current.accountId, '43');
    expect(runtime.current.generation, original.generation + 1);
  });

  test(
    'only current remote identity confirmations remember a startup owner',
    () async {
      SharedPreferences.setMockInitialValues({});
      final site = Uri.parse('https://bbs.example.invalid');
      final cookies = CookieStore();
      await cookies.saveCookies(site, {'fixture_auth': 'session-42'});
      final owners = Y300ForumHomeCacheOwnerStore(
        cookies: cookies,
        siteUri: site,
      );
      final sessions = YamiboSessionStore();
      final container = ProviderContainer.test(
        overrides: [
          yamiboSessionStoreProvider.overrideWithValue(sessions),
          yamiboForumHomeCacheOwnerStoreProvider.overrideWithValue(owners),
        ],
      );
      final adapter = container.read(yamiboForumSessionStoreProvider);
      await adapter.merge(_packageIdentity('42'));
      expect((await owners.restore(isCurrent: () => true))?.accountId, '42');
      sessions.saveExtracted(_identity('43'));
      await cookies.saveCookies(site, {'fixture_auth': 'session-43'});
      await adapter.merge(_packageIdentity('42'));
      expect(sessions.readCurrent()?.uid, '43');
      expect(await owners.restore(isCurrent: () => true), isNull);
    },
  );

  test(
    'authentication may confirm its own identity but not another flow',
    () async {
      final sessions = YamiboSessionStore();
      final container = ProviderContainer.test(
        overrides: [yamiboSessionStoreProvider.overrideWithValue(sessions)],
      );
      final original = container.read(yamiboForumSessionStoreProvider);
      await original.merge(_packageIdentity('0'));
      await original.merge(_packageIdentity('42'));
      expect(sessions.readCurrent()?.uid, '42');
      sessions.saveExtracted(_identity('43'));
      await original.merge(_packageIdentity('42'));
      await original.clear();
      expect(sessions.readCurrent()?.uid, '43');
    },
  );

  test(
    'account partitions keep snapshots private and reject late writes',
    () async {
      final sessions = YamiboSessionStore()..saveExtracted(_identity('42'));
      final runtime = _runtime(sessions);
      final delegate = forum.MemoryForumSnapshotStore();
      final keys = _keys();
      final descriptor = keys.threadDetailSnapshot(tid: '100', page: 1);
      final oldScope = runtime.current;
      final first = Y300ScopedForumSnapshotStore(delegate, oldScope);
      await first.put(descriptor, 'account-42', _threadCodec, policy: _policy);
      sessions.saveExtracted(_identity('43'));
      final second = Y300ScopedForumSnapshotStore(delegate, runtime.current);
      expect(await second.get(descriptor, _threadCodec), isNull);
      await second.put(descriptor, 'account-43', _threadCodec, policy: _policy);
      await first.put(
        descriptor,
        'late-account-42',
        _threadCodec,
        policy: _policy,
      );
      expect(await first.get(descriptor, _threadCodec), isNull);
      expect((await second.get(descriptor, _threadCodec))?.value, 'account-43');
      sessions.saveExtracted(_identity('42'));
      final returned = Y300ScopedForumSnapshotStore(delegate, runtime.current);
      expect(
        (await returned.get(descriptor, _threadCodec))?.value,
        'account-42',
      );
      expect(runtime.current.generation, oldScope.generation + 2);
    },
  );

  test(
    'new source revisions cannot consume earlier documents or snapshots',
    () async {
      final sessions = YamiboSessionStore()..saveExtracted(_identity('42'));
      final first = _runtime(sessions);
      final revised = _runtime(
        sessions,
        profile: const Y300ForumSourceProfile(id: 'parsing', revision: 2),
      );
      final alternative = _runtime(
        sessions,
        profile: const Y300ForumSourceProfile(id: 'fixture', revision: 1),
      );
      final documents = forum.MemoryForumDocumentStore();
      final snapshots = forum.MemoryForumSnapshotStore();
      final descriptor = _keys().forumHome();
      final snapshot = _keys().forumHomeSnapshot();
      await Y300ScopedForumDocumentStore(
        documents,
        first.current,
      ).put(_document(descriptor, 'first-document'));
      await Y300ScopedForumSnapshotStore(
        snapshots,
        first.current,
      ).put(snapshot, 'first-snapshot', _homeCodec, policy: _policy);
      for (final runtime in [revised, alternative]) {
        expect(
          await Y300ScopedForumDocumentStore(
            documents,
            runtime.current,
          ).get(descriptor),
          isNull,
        );
        expect(
          await Y300ScopedForumSnapshotStore(
            snapshots,
            runtime.current,
          ).get(snapshot, _homeCodec),
          isNull,
        );
      }
    },
  );

  test('only anonymous parsing legacy entries remain compatible', () async {
    final sessions = YamiboSessionStore()..saveExtracted(_identity('0'));
    final runtime = _runtime(sessions);
    final documents = forum.MemoryForumDocumentStore();
    final snapshots = forum.MemoryForumSnapshotStore();
    final keys = _keys();
    final anonymous = keys.forumHome(
      requestProfile: forum.ForumDocumentRequestProfile.anonymous,
    );
    final snapshot = keys.forumHomeSnapshot(
      requestProfile: forum.ForumDocumentRequestProfile.anonymous,
    );
    await documents.put(_document(anonymous, 'legacy-anonymous'));
    await documents.put(_document(keys.forumHome(), 'legacy-authenticated'));
    await snapshots.put(
      snapshot,
      'legacy-snapshot',
      _homeCodec,
      policy: _policy,
    );
    final documentStore = Y300ScopedForumDocumentStore(
      documents,
      runtime.current,
    );
    final snapshotStore = Y300ScopedForumSnapshotStore(
      snapshots,
      runtime.current,
    );
    final cached = await documentStore.get(anonymous);
    expect(cached?.body, 'legacy-anonymous');
    expect(cached?.descriptor, same(anonymous));
    expect(cached?.statusCode, 200);
    final parsed = await snapshotStore.get(snapshot, _homeCodec);
    expect(parsed?.value, 'legacy-snapshot');
    expect(parsed?.descriptor, same(snapshot));
    expect(parsed?.codecVersion, _homeCodec.codecVersion);
    expect(parsed?.parserVersion, _homeCodec.parserVersion);
    expect(parsed?.staleAt, isNotNull);
    sessions.saveExtracted(_identity('42'));
    expect(
      await Y300ScopedForumDocumentStore(
        documents,
        runtime.current,
      ).get(keys.forumHome()),
      isNull,
    );
  });

  test(
    'cold unverified public reads reuse anonymous namespace and legacy entries',
    () async {
      final keys = _keys();
      final anonymousDocument = keys.forumHome(
        requestProfile: forum.ForumDocumentRequestProfile.anonymous,
      );
      final anonymousSnapshot = keys.forumHomeSnapshot(
        requestProfile: forum.ForumDocumentRequestProfile.anonymous,
      );
      for (final legacy in [false, true]) {
        final documents = forum.MemoryForumDocumentStore();
        final snapshots = forum.MemoryForumSnapshotStore();
        final confirmed = _runtime(
          YamiboSessionStore()..saveExtracted(_identity('0')),
        );
        if (legacy) {
          await documents.put(_document(anonymousDocument, 'public-document'));
          await snapshots.put(
            anonymousSnapshot,
            'public-snapshot',
            _homeCodec,
            policy: _policy,
          );
        } else {
          await Y300ScopedForumDocumentStore(
            documents,
            confirmed.current,
          ).put(_document(anonymousDocument, 'public-document'));
          await Y300ScopedForumSnapshotStore(snapshots, confirmed.current).put(
            anonymousSnapshot,
            'public-snapshot',
            _homeCodec,
            policy: _policy,
          );
        }
        // A cold boot has not confirmed identity yet. Cookie resolution can
        // still request an explicit anonymous audience without a remote probe.
        final cold = _runtime(YamiboSessionStore());
        final documentStore = Y300ScopedForumDocumentStore(
          documents,
          cold.current,
        );
        final snapshotStore = Y300ScopedForumSnapshotStore(
          snapshots,
          cold.current,
        );
        expect(
          (await documentStore.get(anonymousDocument))?.body,
          'public-document',
        );
        expect(
          (await snapshotStore.get(anonymousSnapshot, _homeCodec))?.value,
          'public-snapshot',
        );
        await documentStore.put(
          _document(anonymousDocument, 'unverified-write'),
        );
        await snapshotStore.put(
          anonymousSnapshot,
          'unverified-write',
          _homeCodec,
          policy: _policy,
        );
        expect(
          (await documentStore.get(anonymousDocument))?.body,
          'public-document',
        );
        expect(
          (await snapshotStore.get(anonymousSnapshot, _homeCodec))?.value,
          'public-snapshot',
        );
        await documents.put(_document(keys.forumHome(), 'privileged-document'));
        await snapshots.put(
          keys.forumHomeSnapshot(),
          'privileged-snapshot',
          _homeCodec,
          policy: _policy,
        );
        expect(await documentStore.get(keys.forumHome()), isNull);
        expect(
          await snapshotStore.get(keys.forumHomeSnapshot(), _homeCodec),
          isNull,
        );
      }
    },
  );

  test(
    'cold authenticated home reuses its exact cookie owner without verifying session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final site = Uri.parse('https://bbs.example.invalid');
      final cookies = CookieStore();
      await cookies.saveCookies(site, {'fixture_auth': 'session-42'});
      final owners = Y300ForumHomeCacheOwnerStore(
        cookies: cookies,
        siteUri: site,
      );
      await owners.remember(accountId: '42', isCurrent: () => true);
      final documents = forum.MemoryForumDocumentStore();
      final snapshots = forum.MemoryForumSnapshotStore();
      final document = _keys().forumHome();
      final snapshot = _keys().forumHomeSnapshot();
      final previous = _runtime(
        YamiboSessionStore()..saveExtracted(_identity('42')),
      );
      await Y300ScopedForumDocumentStore(
        documents,
        previous.current,
        homeCacheOwners: owners,
      ).put(_document(document, 'account-42-home'));
      await Y300ScopedForumSnapshotStore(
        snapshots,
        previous.current,
        homeCacheOwners: owners,
      ).put(snapshot, 'account-42-snapshot', _homeCodec, policy: _policy);
      final sessions = YamiboSessionStore();
      final cold = _runtime(sessions);
      final coldDocuments = Y300ScopedForumDocumentStore(
        documents,
        cold.current,
        homeCacheOwners: owners,
      );
      final coldSnapshots = Y300ScopedForumSnapshotStore(
        snapshots,
        cold.current,
        homeCacheOwners: owners,
      );
      expect((await coldDocuments.get(document))?.body, 'account-42-home');
      expect(
        (await coldSnapshots.get(snapshot, _homeCodec))?.value,
        'account-42-snapshot',
      );
      expect(sessions.readCurrent(), isNull);
      expect(cold.current.hasVerifiedIdentity, isFalse);
      await coldDocuments.put(_document(document, 'unverified-write'));
      await coldSnapshots.put(
        snapshot,
        'unverified-write',
        _homeCodec,
        policy: _policy,
      );
      expect((await coldDocuments.get(document))?.body, 'account-42-home');
      expect(
        (await coldSnapshots.get(snapshot, _homeCodec))?.value,
        'account-42-snapshot',
      );

      // The startup permission does not extend to other privileged surfaces.
      final thread = _keys().threadDetail(tid: '100', page: 1);
      await Y300ScopedForumDocumentStore(
        documents,
        previous.current,
      ).put(_document(thread, 'private-thread'));
      expect(await coldDocuments.get(thread), isNull);
      final threadSnapshot = _keys().threadDetailSnapshot(tid: '100', page: 1);
      await Y300ScopedForumSnapshotStore(
        snapshots,
        previous.current,
      ).put(threadSnapshot, 'private-thread', _threadCodec, policy: _policy);
      expect(await coldSnapshots.get(threadSnapshot, _threadCodec), isNull);
      final revised = _runtime(
        sessions,
        profile: const Y300ForumSourceProfile(id: 'parsing', revision: 2),
      );
      expect(
        await Y300ScopedForumDocumentStore(
          documents,
          revised.current,
          homeCacheOwners: owners,
        ).get(document),
        isNull,
      );
      await cookies.saveCookies(site, {'fixture_auth': 'session-43'});
      expect(await coldDocuments.get(document), isNull);
      expect(await coldSnapshots.get(snapshot, _homeCodec), isNull);
    },
  );

  test('cold home discards a delayed read after cookies change', () async {
    SharedPreferences.setMockInitialValues({});
    final site = Uri.parse('https://bbs.example.invalid');
    final cookies = CookieStore();
    await cookies.saveCookies(site, {'fixture_auth': 'session-42'});
    final owners = Y300ForumHomeCacheOwnerStore(
      cookies: cookies,
      siteUri: site,
    );
    await owners.remember(accountId: '42', isCurrent: () => true);
    final cold = _runtime(YamiboSessionStore());
    final delegate = _DelayedDocumentStore();
    final descriptor = _keys().forumHome();
    final read = Y300ScopedForumDocumentStore(
      delegate,
      cold.current,
      homeCacheOwners: owners,
    ).get(descriptor);
    await delegate.started.future;
    await cookies.saveCookies(site, {'fixture_auth': 'session-43'});
    delegate.result.complete(_document(descriptor, 'account-42-home'));
    expect(await read, isNull);
  });

  test(
    'unverified session does not read or persist privileged cache',
    () async {
      final runtime = _runtime(YamiboSessionStore());
      final delegate = forum.MemoryForumDocumentStore();
      final descriptor = _keys().forumHome();
      final store = Y300ScopedForumDocumentStore(delegate, runtime.current);
      await store.put(_document(descriptor, 'unverified'));
      expect(await store.get(descriptor), isNull);
      final scoped = forum.ForumDocumentDescriptor(
        cacheKey: runtime.current.cacheKey(descriptor.cacheKey),
        ownerType: descriptor.ownerType,
        ownerId: descriptor.ownerId,
        sourceUri: descriptor.sourceUri,
        requestProfile: descriptor.requestProfile,
      );
      expect(await delegate.get(scoped), isNull);
    },
  );

  test(
    'cache reads completing after an account change are discarded',
    () async {
      final sessions = YamiboSessionStore()..saveExtracted(_identity('42'));
      final runtime = _runtime(sessions);
      final descriptor = _keys().forumHome();
      final delayed = _DelayedDocumentStore();
      final store = Y300ScopedForumDocumentStore(delayed, runtime.current);
      final pending = store.get(descriptor);
      sessions.saveExtracted(_identity('43'));
      delayed.result.complete(_document(descriptor, 'late-cache'));
      expect(await pending, isNull);
    },
  );

  test(
    'writes awaiting local DB readiness cannot overwrite a returning account',
    () async {
      final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
      addTearDown(db.close);
      final ready = Completer<Database>();
      final sessions = YamiboSessionStore()..saveExtracted(_identity('42'));
      final runtime = _runtime(sessions);
      final oldScope = runtime.current;
      final document = _keys().forumHome();
      final snapshot = _keys().forumHomeSnapshot();
      final oldDocuments = Y300ScopedForumDocumentStore(
        Y300ForumDocumentStoreAdapter(
          LocalDocumentCacheService(ready.future),
          isCurrent: () => oldScope.isCurrent,
        ),
        oldScope,
      );
      final oldSnapshots = Y300ScopedForumSnapshotStore(
        Y300ForumSnapshotStoreAdapter(
          LocalParsedSnapshotCacheService(ready.future),
          isCurrent: () => oldScope.isCurrent,
        ),
        oldScope,
      );
      final pendingDocument = oldDocuments.put(
        _document(document, 'old-document'),
      );
      final pendingSnapshot = oldSnapshots.put(
        snapshot,
        'old-snapshot',
        _homeCodec,
        policy: _policy,
      );
      sessions.saveExtracted(_identity('43'));
      sessions.saveExtracted(_identity('42'));
      final newScope = runtime.current;
      final currentDocuments = Y300ScopedForumDocumentStore(
        Y300ForumDocumentStoreAdapter(
          LocalDocumentCacheService(Future.value(db)),
          isCurrent: () => newScope.isCurrent,
        ),
        newScope,
      );
      final currentSnapshots = Y300ScopedForumSnapshotStore(
        Y300ForumSnapshotStoreAdapter(
          LocalParsedSnapshotCacheService(Future.value(db)),
          isCurrent: () => newScope.isCurrent,
        ),
        newScope,
      );
      await currentDocuments.put(_document(document, 'current-document'));
      await currentSnapshots.put(
        snapshot,
        'current-snapshot',
        _homeCodec,
        policy: _policy,
      );
      ready.complete(db);
      await Future.wait([pendingDocument, pendingSnapshot]);
      expect((await currentDocuments.get(document))?.body, 'current-document');
      expect(
        (await currentSnapshots.get(snapshot, _homeCodec))?.value,
        'current-snapshot',
      );
    },
  );

  test(
    'cache descriptors retain owner identities and document relationships',
    () async {
      final sessions = YamiboSessionStore()..saveExtracted(_identity('42'));
      final runtime = _runtime(sessions);
      final delegate = _RecordingSnapshotStore();
      final descriptor = _keys().threadDetailSnapshot(tid: '100', page: 3);
      await Y300ScopedForumSnapshotStore(
        delegate,
        runtime.current,
      ).put(descriptor, 'thread', _threadCodec, policy: _policy);
      expect(delegate.descriptor?.ownerType, descriptor.ownerType);
      expect(delegate.descriptor?.ownerId, descriptor.ownerId);
      expect(delegate.descriptor?.snapshotType, descriptor.snapshotType);
      expect(
        delegate.descriptor?.cacheKey,
        runtime.current.cacheKey(descriptor.cacheKey),
      );
      expect(
        delegate.descriptor?.sourceDocumentKey,
        runtime.current.cacheKey(descriptor.sourceDocumentKey!),
      );
    },
  );
}

Y300ForumSourceRuntime _runtime(
  YamiboSessionStore sessions, {
  Y300ForumSourceProfile profile = Y300ForumSourceProfile.parsing,
}) {
  final runtime = Y300ForumSourceRuntime(profile: profile, sessions: sessions);
  addTearDown(runtime.dispose);
  return runtime;
}

YamiboSessionSnapshot _identity(String uid, {String formhash = 'fixture'}) =>
    YamiboSessionSnapshot(
      isLoggedIn: uid != '0',
      uid: uid,
      username: uid == '0' ? '' : 'fixture',
      formhash: formhash,
      updatedAt: DateTime.utc(2026),
      source: 'auth:profile',
    );

forum.ForumCacheKeyCanonicalizer _keys() => forum.ForumCacheKeyCanonicalizer(
  siteOrigin: Uri.parse('https://bbs.example.invalid'),
);

forum.ForumCachedDocument _document(
  forum.ForumDocumentDescriptor descriptor,
  String body,
) => forum.ForumCachedDocument(
  descriptor: descriptor,
  body: body,
  fetchedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  statusCode: 200,
  contentType: 'text/html',
);

const _policy = forum.ForumSnapshotPolicy(
  freshFor: Duration(minutes: 5),
  keepStaleFor: Duration(days: 1),
);
const _threadCodec = _StringCodec('thread.detail');
const _homeCodec = _StringCodec('forum.home');

final class _StringCodec implements forum.ForumSnapshotCodec<String> {
  const _StringCodec(this.snapshotType);
  @override
  int get codecVersion => 2;
  @override
  int get parserVersion => 3;
  @override
  final String snapshotType;
  @override
  String decode(Object? json) => json as String;
  @override
  Object? encode(String value) => value;
  @override
  bool canDecodeVersion({
    required int codecVersion,
    required int parserVersion,
  }) =>
      codecVersion == this.codecVersion && parserVersion == this.parserVersion;
}

forum.ForumSessionSnapshot _packageIdentity(String uid) =>
    forum.ForumSessionSnapshot(
      isLoggedIn: uid != '0',
      userId: uid,
      username: uid == '0' ? '' : 'fixture',
      formhash: 'fixture',
      updatedAt: DateTime.utc(2026),
      source: 'auth:profile',
    );

final class _DelayedDocumentStore implements forum.ForumDocumentStore {
  final result = Completer<forum.ForumCachedDocument?>();
  final started = Completer<void>();
  @override
  Future<forum.ForumCachedDocument?> get(
    forum.ForumDocumentDescriptor descriptor,
  ) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  Future<void> put(forum.ForumCachedDocument document) async {}
  @override
  Future<void> touch(
    forum.ForumDocumentDescriptor descriptor,
    DateTime accessedAt,
  ) async {}
}

final class _RecordingSnapshotStore implements forum.ForumSnapshotStore {
  forum.ForumSnapshotDescriptor? descriptor;
  @override
  Future<forum.ForumCachedSnapshot<T>?> get<T>(
    forum.ForumSnapshotDescriptor descriptor,
    forum.ForumSnapshotCodec<T> codec,
  ) async => null;
  @override
  Future<void> put<T>(
    forum.ForumSnapshotDescriptor descriptor,
    T value,
    forum.ForumSnapshotCodec<T> codec, {
    required forum.ForumSnapshotPolicy policy,
  }) async {
    this.descriptor = descriptor;
  }

  @override
  Future<void> touch(
    forum.ForumSnapshotDescriptor descriptor,
    DateTime accessedAt,
  ) async {}
}
