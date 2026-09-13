import 'package:y300/features/thread/presentation/services/thread_post_comment_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/models/comic_comment_models.dart';
import 'package:y300/features/comic/domain/services/comic_comment_loader.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_interaction_controller.dart';
import 'package:y300/features/comic/presentation/controllers/comic_comment_session_controller.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_action_bar.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/reply/presentation/reply_composer_controller.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';
import 'package:y300/features/thread/presentation/services/thread_post_rating_service.dart';
import 'package:y300/l10n/app_localizations.dart';
import '../../../../test_support/localized_test_app.dart';
import '../../data/comic_interaction_fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'empty comments still open the existing thread reply editor and honor its result',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.session.load();
      await fixture.controller.load();
      await tester.pumpWidget(fixture.host());
      await tester.pumpAndSettle();
      final reply = find.byKey(const Key('comic-comment-reply-button'));
      await tester.tap(reply);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final page = tester.widget<ReplyComposerPage>(
        find.byType(ReplyComposerPage),
      );
      expect(page.args.target.tid, '100');
      expect(page.args.target.fid, '33');
      expect(page.args.target.isPostReply, isFalse);
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(fixture.invalidated, isEmpty);
      expect(fixture.comments.calls, 1);
      await tester.tap(reply);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      fixture.navigator.currentState!.pop(const ReplyComposerResult.sent());
      await tester.pumpAndSettle();
      expect(fixture.invalidated, ['100']);
      expect(fixture.comments.calls, 2);
      expect(find.byKey(const Key('comic-comment-action-bar')), findsOneWidget);
    },
  );

  for (final applied in [true, false]) {
    testWidgets(
      'rating reuses the sheet and ${applied ? 'invalidates success' : 'preserves unknown outcome'}',
      (tester) async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        fixture.rating.applied = applied;
        await fixture.controller.load();
        await tester.pumpWidget(fixture.host());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('comic-comment-rate-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('thread-post-rate-sheet')), findsOneWidget);
        expect(fixture.rating.request?.tid, '100');
        expect(fixture.rating.request?.pid, '200');
        await tester.enterText(
          find.byKey(const Key('thread-post-rate-reason-input')),
          '支持作品',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('thread-post-rate-submit-button')),
        );
        await tester.pumpAndSettle();
        expect(fixture.rating.submissions, 1);
        expect(fixture.invalidated, applied ? ['100'] : isEmpty);
        expect(fixture.comments.calls, applied ? 2 : 1);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(ComicCommentActionBar)),
        );
        expect(
          find.text(
            applied
                ? l10n.threadRatingSuccess
                : l10n.threadRatingOutcomeUnknown,
          ),
          findsOneWidget,
        );
      },
    );
  }

  for (final applied in [true, false]) {
    testWidgets(
      'bottom comment targets first floor and respects applied=$applied',
      (tester) async {
        final fixture = _Fixture();
        fixture.comment.applied = applied;
        addTearDown(fixture.dispose);
        await fixture.controller.load();
        await tester.pumpWidget(fixture.host());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('comic-comment-comment-button')));
        await tester.pumpAndSettle();
        expect(fixture.comment.request?.pid, '200');
        expect(fixture.comment.request?.page, 1);
        expect(
          find.byKey(const Key('thread-post-comment-sheet')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('thread-post-comment-message-input')),
          '点评',
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('thread-post-comment-submit-button')),
        );
        await tester.pumpAndSettle();
        expect(fixture.comment.submissions, 1);
        expect(fixture.invalidated, applied ? ['100'] : isEmpty);
        expect(fixture.comments.calls, applied ? 2 : 1);
      },
    );
  }

  testWidgets(
    'loading, unavailable actions, traditional text and large font remain accessible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<ComicInteractionRead>();
      final fixture = _Fixture(ComicInteractionRepository([pending.future]));
      addTearDown(fixture.dispose);
      final load = fixture.controller.load();
      await tester.pumpWidget(
        fixture.host(locale: const Locale('zh', 'TW'), scale: 2, dark: true),
      );
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('comic-comment-rate-button')),
            )
            .onPressed,
        isNull,
      );
      pending.complete(comicInteractionRead(rate: false));
      await load;
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(ComicCommentActionBar)),
      );
      expect(find.text(l10n.comicRatingUnavailable), findsOneWidget);
      expect(find.text(l10n.threadDetailReply), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const Key('comic-comment-reply-button')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _Fixture {
  _Fixture([ComicInteractionRepository? repository]) {
    comments = _Comments(repository ?? ComicInteractionRepository());
    session = ComicCommentSessionController(
      key: const ComicCommentSessionKey(episodeId: 'chapter', sourceTid: '100'),
      loader: comments,
    );
    controller = ComicCommentInteractionController(
      session: session,
      invalidateThread: (tid) async => invalidated.add(tid),
    );
  }
  final navigator = GlobalKey<NavigatorState>();
  late final _Comments comments;
  final rating = _Rating();
  final comment = _Comment();
  final invalidated = <String>[];
  late final ComicCommentSessionController session;
  late final ComicCommentInteractionController controller;
  Widget host({
    Locale locale = const Locale('zh'),
    double scale = 1,
    bool dark = false,
  }) => ProviderScope(
    overrides: [
      threadPostCommentServiceProvider.overrideWithValue(
        ThreadPostCommentService(comment, comment),
      ),
      threadPostRatingServiceProvider.overrideWithValue(
        ThreadPostRatingService(rating, rating),
      ),
      replyComposerControllerProvider.overrideWith2(
        (_) => _PendingReplyController(),
      ),
      stickerGroupsProvider.overrideWith((_) async => []),
    ],
    child: LocalizedTestApp(
      navigatorKey: navigator,
      locale: locale,
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ComicCommentActionBar(
            controller: controller,
            session: session,
          ),
        ),
      ),
    ),
  );
  void dispose() {
    controller.dispose();
    session.dispose();
  }
}

class _Comments extends DefaultComicCommentLoader {
  _Comments(ThreadRepository repository) : super(repository: repository);
  int calls = 0;
  @override
  Future<ComicCommentLoadResult> loadPage({
    required String sourceTid,
    int page = 1,
    ComicCommentCancellationToken? cancellationToken,
  }) {
    calls++;
    return super.loadPage(
      sourceTid: sourceTid,
      page: page,
      cancellationToken: cancellationToken,
    );
  }
}

class _PendingReplyController extends ReplyComposerController {
  _PendingReplyController()
    : super(
        const ReplyComposerArgs(
          target: ReplyTarget.thread(fid: '33', tid: '100'),
        ),
      );
  @override
  Future<ReplyComposerState> build() => Completer<ReplyComposerState>().future;
}

class _Rating
    implements ThreadPostRatingPreparationRepository, ThreadPostRatingCommand {
  ThreadPostRatingPreparationRequest? request;
  int submissions = 0;
  bool applied = true;
  @override
  ThreadPostRatingCapabilities get capabilities => ThreadPostRatingCapabilities(
    values: DataCapabilitySet.supported(ThreadPostRatingCapability.values),
  );
  @override
  Future<
    DataReadResult<ThreadPostRatingPreparation, ThreadPostRatingCapabilities>
  >
  load(ThreadPostRatingPreparationRequest request) async {
    this.request = request;
    return DataReadSuccess(
      data: ThreadPostRatingPreparation(
        tid: request.tid,
        pid: request.pid,
        dimensions: const [
          ThreadPostRatingDimension(
            id: 'score1',
            label: '积分',
            minimum: 0,
            maximum: 5,
            initialScore: 0,
            todayRemaining: 10,
          ),
        ],
        reasonSuggestions: const [],
        notificationPolicy: ThreadPostRatingNotificationPolicy.optional,
        notifyAuthorByDefault: false,
        token: const _Token(),
      ),
      capabilities: capabilities,
      metadata: const DataReadMetadata.network(),
    );
  }

  @override
  Future<DataCommandResult<ThreadPostRatingReceipt>> execute(
    ThreadPostRatingSubmission submission,
  ) async {
    submissions++;
    return applied
        ? DataCommandApplied(
            ThreadPostRatingReceipt(
              tid: submission.preparation.tid,
              pid: submission.preparation.pid,
            ),
          )
        : const DataCommandOutcomeUnknown(
            DataCommandFailure(
              kind: DataCommandFailureKind.timeout,
              retryPolicy: DataCommandRetryPolicy.never,
              diagnosticMessage: 'timeout',
            ),
          );
  }
}

final class _Token implements ThreadPostRatingPreparationToken {
  const _Token();
}

class _Comment
    implements
        ThreadPostCommentPreparationRepository,
        ThreadPostCommentCommand {
  ThreadPostCommentPreparationRequest? request;
  bool applied = true;
  int submissions = 0;
  @override
  ThreadPostCommentCapabilities get capabilities =>
      ThreadPostCommentCapabilities(
        values: DataCapabilitySet.supported(ThreadPostCommentCapability.values),
      );
  @override
  Future<
    DataReadResult<ThreadPostCommentPreparation, ThreadPostCommentCapabilities>
  >
  load(ThreadPostCommentPreparationRequest request) async {
    this.request = request;
    return DataReadSuccess(
      data: ThreadPostCommentPreparation(
        tid: request.tid,
        pid: request.pid,
        maxLength: 200,
        token: const _CommentToken(),
      ),
      capabilities: capabilities,
      metadata: const DataReadMetadata.network(),
    );
  }

  @override
  Future<DataCommandResult<ThreadPostCommentReceipt>> execute(
    ThreadPostCommentSubmission submission,
  ) async {
    submissions++;
    return applied
        ? DataCommandApplied(
            ThreadPostCommentReceipt(
              tid: submission.preparation.tid,
              pid: submission.preparation.pid,
            ),
          )
        : const DataCommandOutcomeUnknown(
            DataCommandFailure(
              kind: DataCommandFailureKind.network,
              code: 'unknown',
              retryPolicy: DataCommandRetryPolicy.explicitOnly,
              diagnosticMessage: 'unknown',
            ),
          );
  }
}

class _CommentToken implements ThreadPostCommentPreparationToken {
  const _CommentToken();
}
