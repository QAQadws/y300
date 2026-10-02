import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_visit_recorder.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_history_visit_observer.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_navigation_fixture.dart';

void main() {
  testWidgets(
    'records the first displayed success once across refresh and paging',
    (tester) async {
      final host = _Host();
      await host.pump(tester);
      expect(host.history.drafts, isEmpty);
      host.details.succeed(0);
      await tester.pumpAndSettle();
      expect(find.text('article body', findRichText: true), findsOneWidget);
      expect(host.history.drafts, hasLength(1));
      final controller = tester
          .widget<BlogHistoryVisitObserver>(
            find.byType(BlogHistoryVisitObserver),
          )
          .controller;
      final refresh = controller.refresh();
      await tester.pump();
      host.details.succeed(1, title: 'Updated article');
      await refresh;
      await tester.pumpAndSettle();
      final paging = controller.selectCommentPage(2);
      await tester.pump();
      host.details.succeed(2);
      await paging;
      await tester.pumpAndSettle();
      expect(host.history.drafts, hasLength(1));
      expect(host.history.drafts.single.page, isNull);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push<void>(_overlay()));
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(host.history.drafts, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed reads do not record and a successful retry does', (
    tester,
  ) async {
    final host = _Host();
    await host.pump(tester);
    host.details.fail(0);
    await tester.pumpAndSettle();
    expect(host.history.drafts, isEmpty);
    final controller = tester
        .widget<BlogHistoryVisitObserver>(find.byType(BlogHistoryVisitObserver))
        .controller;
    final retry = controller.refresh();
    host.details.succeed(1);
    await retry;
    await tester.pumpAndSettle();
    expect(host.history.drafts, hasLength(1));
  });

  testWidgets(
    'covered pending reads do not record until a visible read succeeds',
    (tester) async {
      final host = _Host();
      await host.pump(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push<void>(_overlay()));
      await tester.pumpAndSettle();
      host.details.succeed(0, title: 'Hidden late result');
      await tester.pumpAndSettle();
      expect(host.history.drafts, isEmpty);
      navigator.pop();
      await tester.pump();
      await tester.pump();
      host.details.succeed(1, title: 'Visible result');
      await tester.pumpAndSettle();
      expect(host.history.drafts.single.title, 'Visible result');
    },
  );

  testWidgets(
    'closed routes ignore late reads and reopening records a new visit',
    (tester) async {
      final host = _Host();
      await host.pump(tester, home: const Scaffold(body: Text('home fixture')));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push<void>(_detailRoute()));
      await tester.pump();
      navigator.pop();
      await tester.pumpAndSettle();
      host.details.succeed(0, title: 'Closed result');
      await tester.pumpAndSettle();
      expect(host.history.drafts, isEmpty);

      for (var visit = 0; visit < 2; visit++) {
        unawaited(navigator.push<void>(_detailRoute()));
        await tester.pump();
        host.details.succeed(visit + 1);
        await tester.pumpAndSettle();
        expect(host.history.drafts, hasLength(visit + 1));
        navigator.pop();
        await tester.pumpAndSettle();
      }
      expect(host.history.drafts.first.target, host.history.drafts.last.target);
    },
  );

  testWidgets(
    'a route covered before the history callback waits until it returns',
    (tester) async {
      final host = _Host();
      await host.pump(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      host.details.succeed(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(navigator.push<void>(_overlay()));
      });
      await tester.pump();
      await tester.pumpAndSettle();
      expect(host.history.drafts, isEmpty);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(host.history.drafts, hasLength(1));
      expect(host.details.queries, hasLength(1));
    },
  );

  testWidgets(
    'an account switch before the frame callback rejects its old snapshot',
    (tester) async {
      final host = _Host();
      await host.pump(tester);
      host.details.succeed(0, title: 'Old frame');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        host.switchAccount('303');
      });
      await tester.pump();
      expect(host.history.drafts, isEmpty);
      await tester.pump();
      await tester.pump();
      host.details.succeed(1, title: 'New frame');
      await tester.pumpAndSettle();
      expect(host.history.drafts.single.title, 'New frame');
    },
  );

  testWidgets(
    'account generations reject old data without resetting route deduplication',
    (tester) async {
      final host = _Host();
      await host.pump(tester);
      host.switchAccount('303');
      await tester.pump();
      await tester.pump();
      host.details.succeed(0, title: 'Old account');
      host.details.succeed(1, title: 'Current account');
      await tester.pumpAndSettle();
      expect(host.history.drafts.single.title, 'Current account');

      host.switchAccount('101');
      await tester.pump();
      await tester.pump();
      host.details.succeed(2, title: 'Original account reloaded');
      await tester.pumpAndSettle();
      expect(host.history.drafts, hasLength(1));
      expect(find.text('Original account reloaded'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed history write never changes reading or retries on rebuild',
    (tester) async {
      final host = _Host()..history.fail = true;
      await host.pump(tester);
      host.details.succeed(0);
      await tester.pumpAndSettle();
      expect(find.text('article body', findRichText: true), findsOneWidget);
      expect(host.history.drafts, hasLength(1));
      final controller = tester
          .widget<BlogHistoryVisitObserver>(
            find.byType(BlogHistoryVisitObserver),
          )
          .controller;
      final refresh = controller.refresh();
      host.details.succeed(1);
      await refresh;
      await tester.pumpAndSettle();
      expect(host.history.drafts, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful empty body records without a browser navigation capability',
    (tester) async {
      final host = _Host(navigationAvailable: false);
      await host.pump(tester);
      host.details.succeed(0, bodyHtml: '');
      await tester.pumpAndSettle();
      expect(host.history.drafts, hasLength(1));
      expect(host.history.drafts.single.canonicalUri, isNull);
    },
  );
}

const _detailPage = ProfileBlogDetailPage(
  ownerUserId: '202',
  blogId: '11',
  initialPage: 2,
);

MaterialPageRoute<void> _detailRoute() =>
    MaterialPageRoute<void>(builder: (_) => _detailPage);

MaterialPageRoute<void> _overlay() => MaterialPageRoute<void>(
  builder: (_) => const Scaffold(body: Text('overlay fixture')),
);

class _Host {
  _Host({this.navigationAvailable = true});

  final bool navigationAvailable;
  final details = _Details();
  final history = _Recorder();
  final navigation = BlogNavigationFixture();
  late final ProviderContainer container;

  List<Override> _overrides(String actor) => [
    blogAccountIdProvider.overrideWithValue(actor),
    userBlogDetailRepositoryProvider.overrideWithValue(details),
    userBlogNavigationProvider.overrideWithValue(
      navigationAvailable ? navigation : null,
    ),
    historyVisitRecorderProvider.overrideWithValue(history),
    forumImageRefererProvider.overrideWithValue('https://example.test/'),
  ];

  Future<void> pump(WidgetTester tester, {Widget home = _detailPage}) async {
    container = ProviderContainer(overrides: _overrides('101'));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(home: home),
      ),
    );
  }

  void switchAccount(String actor) =>
      container.updateOverrides(_overrides(actor));
}

class _Recorder implements HistoryVisitRecorder {
  final drafts = <HistoryVisitDraft>[];
  bool fail = false;

  @override
  Future<void> record(HistoryVisitDraft draft) async {
    drafts.add(draft);
    if (fail) throw StateError('history fixture failure');
  }
}

typedef _Read =
    DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>;

class _Details implements UserBlogDetailRepository {
  final requests = <Completer<_Read>>[];
  final queries = <UserBlogDetailQuery>[];
  @override
  final capabilities = UserBlogDetailSourceCapabilities(
    values: DataCapabilitySet.supported(UserBlogDetailCapability.values),
  );

  @override
  Future<_Read> load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) {
    queries.add(query);
    final request = Completer<_Read>();
    requests.add(request);
    return request.future;
  }

  void succeed(
    int index, {
    String title = 'Article title',
    String bodyHtml = '<p>article body</p>',
  }) {
    final query = queries[index];
    requests[index].complete(
      DataReadSuccess(
        data: UserBlogDetailData(
          ownerUserId: query.ownerUserId,
          blogId: query.blogId,
          title: title,
          authorName: 'Article author',
          bodyHtml: bodyHtml,
          commentPagination: UserBlogPagination(
            currentPage: query.page,
            totalPages: 3,
            hasNext: query.page < 3,
            hasPrevious: query.page > 1,
          ),
          comments: const [],
        ),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      ),
    );
  }

  void fail(int index) => requests[index].complete(
    const DataReadFailure(
      kind: DataReadFailureKind.business,
      code: 'user_blog_private',
      diagnosticMessage: 'private fixture',
    ),
  );
}
