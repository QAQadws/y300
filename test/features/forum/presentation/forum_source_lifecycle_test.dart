import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/forum/presentation/forum_display_controller.dart';
import 'package:y300/features/forum/presentation/forum_display_page.dart';

import '../../../test_support/localized_test_app.dart';

typedef _DisplayResult =
    DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the same forum page consumes an assembled replacement source', (
    tester,
  ) async {
    final repository = _DisplayRepository(
      (query) async => _success(query, 'Fixture alternate source'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yamiboForumSourceProfileProvider.overrideWithValue(
            _profile('fixture', repository),
          ),
        ],
        child: const LocalizedTestApp(
          home: ForumDisplayPage(fid: '2', initialPage: 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ForumDisplayPage), findsOneWidget);
    expect(find.byKey(const Key('forum-display-list')), findsOneWidget);
    expect(find.text('Fixture alternate source'), findsWidgets);
    expect(repository.queries.single.page, 3);
    expect(tester.takeException(), isNull);
  });

  test(
    'changing the source discards a late refresh from the old source',
    () async {
      final delayed = Completer<_DisplayResult>();
      final oldRepository = _DisplayRepository(
        (query) => query.page == 2
            ? delayed.future
            : Future.value(_success(query, 'Old initial')),
      );
      final newRepository = _DisplayRepository(
        (query) async => _success(query, 'New source'),
      );
      var profile = _profile('old_fixture', oldRepository);
      final container = ProviderContainer(
        overrides: [
          yamiboForumSourceProfileProvider.overrideWith((ref) => profile),
        ],
      );
      addTearDown(container.dispose);
      const args = ForumDisplayArgs(fid: '2');
      final provider = forumDisplayControllerProvider(args);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final oldScope = container.read(yamiboForumSourceScopeProvider);
      final pending = container.read(provider.notifier).loadPageNumber(2);

      profile = _profile('new_fixture', newRepository);
      container.invalidate(yamiboForumSourceProfileProvider);
      await container.read(provider.future);
      expect(oldScope.isCurrent, isFalse);
      delayed.complete(_success(oldRepository.queries.last, 'Late old source'));
      await pending;

      expect(container.read(provider).requireValue.title, 'New source');
      expect(container.read(provider).requireValue.currentPage, 1);
    },
  );

  test('an account change cannot publish the preceding account page', () async {
    final sessions = YamiboSessionStore();
    _signIn(sessions, '100');
    final delayed = Completer<_DisplayResult>();
    final repository = _DisplayRepository(
      (query) => query.page == 2
          ? delayed.future
          : Future.value(
              _success(query, 'Account ${sessions.readCurrent()!.uid}'),
            ),
    );
    final container = ProviderContainer(
      overrides: [
        yamiboSessionStoreProvider.overrideWithValue(sessions),
        yamiboForumSourceProfileProvider.overrideWithValue(
          _profile('fixture', repository),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = forumDisplayControllerProvider(
      const ForumDisplayArgs(fid: '2'),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final oldScope = container.read(yamiboForumSourceScopeProvider);
    final pending = container.read(provider.notifier).loadPageNumber(2);

    _signIn(sessions, '200');
    await container.read(provider.future);
    expect(oldScope.isCurrent, isFalse);
    delayed.complete(_success(repository.queries[1], 'Late account 100'));
    await pending;

    expect(container.read(provider).requireValue.title, 'Account 200');
    expect(container.read(yamiboForumSourceScopeProvider).accountId, '200');
  });

  test('the newest pagination request wins within the same source', () async {
    final delayed = Completer<_DisplayResult>();
    final repository = _DisplayRepository(
      (query) => query.page == 2
          ? delayed.future
          : Future.value(_success(query, 'Page ${query.page}')),
    );
    final container = ProviderContainer(
      overrides: [
        yamiboForumSourceProfileProvider.overrideWithValue(
          _profile('fixture', repository),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = forumDisplayControllerProvider(
      const ForumDisplayArgs(fid: '2'),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    final pending = controller.loadPageNumber(2);
    await controller.loadPageNumber(3);
    delayed.complete(_success(repository.queries[1], 'Late page 2'));
    await pending;
    expect(container.read(provider).requireValue.currentPage, 3);
    expect(container.read(provider).requireValue.title, 'Page 3');
  });
}

Y300ForumSourceProfile _profile(String id, ForumDisplayRepository repository) =>
    Y300ForumSourceProfile(
      id: id,
      revision: 1,
      createOverrides: (_) => ForumClientSourcePlan(forumDisplay: repository),
    );

void _signIn(YamiboSessionStore store, String uid) => store.saveExtracted(
  YamiboSessionSnapshot(
    isLoggedIn: true,
    uid: uid,
    username: 'Fixture $uid',
    formhash: '',
    updatedAt: DateTime(2026),
    source: 'fixture',
  ),
);

_DisplayResult _success(ForumDisplayQuery query, String title) =>
    DataReadSuccess(
      data: ForumDisplayData(
        fid: query.fid,
        forumName: title,
        currentPage: query.page,
        perPage: 20,
        totalThreads: 0,
        threads: const [],
      ),
      capabilities: ForumDisplaySourceCapabilities.full.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );

class _DisplayRepository implements ForumDisplayRepository {
  _DisplayRepository(this.load);
  final Future<_DisplayResult> Function(ForumDisplayQuery) load;
  final queries = <ForumDisplayQuery>[];
  @override
  ForumDisplaySourceCapabilities get capabilities =>
      ForumDisplaySourceCapabilities.full;
  @override
  Future<_DisplayResult> getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    queries.add(query);
    return load(query);
  }
}
