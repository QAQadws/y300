import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/messages/presentation/message_feed_controller.dart';
import 'package:y300/features/messages/presentation/widgets/conversation_history_loader.dart';

import '../support/message_test_repository.dart';

void main() {
  late MessageTestRepository repository;
  late MessageFeedController<ForumPrivateMessagePage> controller;
  late ScrollController scroll;
  late ScrollController nestedScroll;
  const listKey = Key('conversation-scroll');
  const nestedKey = Key('html-scroll');

  setUp(() {
    repository = MessageTestRepository();
    scroll = ScrollController();
    nestedScroll = ScrollController();
    controller = MessageFeedController<ForumPrivateMessagePage>(
      initialPage: 0,
      load: (page, cancellation) => repository.loadMessages(
        ForumPrivateMessageQuery.conversation(
          target: const ForumConversationTarget.direct('20'),
          page: page,
          cancellation: cancellation,
        ),
      ),
      nextPage: (data) => data.hasPrevious ? data.page - 1 : null,
      mergeMore: (_, next) => next,
    );
    controller.value = const MessageFeedState(
      data: ForumPrivateMessagePage(
        items: [],
        count: 80,
        page: 4,
        perPage: 20,
        currentUserId: '10',
      ),
    );
  });

  tearDown(() {
    controller.dispose();
    scroll.dispose();
    nestedScroll.dispose();
  });

  Future<void> pumpLoader(WidgetTester tester, {bool nested = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: ConversationHistoryLoader(
                controller: controller,
                child: ListView.builder(
                  key: listKey,
                  controller: scroll,
                  reverse: true,
                  itemExtent: 80,
                  itemCount: 20,
                  itemBuilder: (_, index) => nested && index == 0
                      ? ListView.builder(
                          key: nestedKey,
                          controller: nestedScroll,
                          scrollDirection: Axis.horizontal,
                          itemExtent: 100,
                          itemCount: 10,
                          itemBuilder: (_, index) => Text('Column $index'),
                        )
                      : Text('Message $index'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dragNearHistory(WidgetTester tester) async {
    scroll.jumpTo(scroll.position.maxScrollExtent - 250);
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(listKey), const Offset(0, 150));
    await tester.pumpAndSettle();
  }

  testWidgets('nested HTML scrolling never requests conversation history', (
    tester,
  ) async {
    await pumpLoader(tester, nested: true);
    await tester.drag(find.byKey(nestedKey), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(
      nestedScroll.position.maxScrollExtent - nestedScroll.offset,
      lessThanOrEqualTo(160),
    );
    expect(scroll.offset, 0);
    expect(repository.reads, isEmpty);
  });

  testWidgets('programmatic jumps and animations do not request history', (
    tester,
  ) async {
    await pumpLoader(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent - 100);
    await tester.pumpAndSettle();
    final move = scroll.animateTo(
      scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    await move;
    expect(repository.reads, isEmpty);
  });

  testWidgets(
    'one held gesture loads at most one page even after it completes',
    (tester) async {
      await pumpLoader(tester);
      scroll.jumpTo(scroll.position.maxScrollExtent - 250);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(listKey)),
      );
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(repository.reads, hasLength(1));
      expect(repository.reads.single.query.page, 3);
      repository.reads.single.result.complete(
        messageTestPage([messageTestItem('41')], page: 3, count: 80),
      );
      await tester.pump();
      expect(controller.value.isBusy, isFalse);
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(repository.reads, hasLength(1));
      await gesture.up();
      await tester.pumpAndSettle();

      await dragNearHistory(tester);
      expect(repository.reads, hasLength(2));
      expect(repository.reads.last.query.page, 2);
      repository.reads.last.result.complete(
        messageTestPage([messageTestItem('21')], page: 2, count: 80),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pagination failure stops automatic retries across new gestures',
    (tester) async {
      await pumpLoader(tester);
      await dragNearHistory(tester);
      expect(repository.reads, hasLength(1));
      repository.reads.single.result.complete(
        const DataReadFailure(
          kind: DataReadFailureKind.network,
          code: 'fixture',
          diagnosticMessage: 'fixture',
        ),
      );
      await tester.pump();
      expect(controller.value.failedOperation, MessageFeedOperation.more);
      await dragNearHistory(tester);
      await dragNearHistory(tester);
      expect(repository.reads, hasLength(1));
      expect(controller.hasMore, isTrue);
    },
  );

  testWidgets('a scheduled history request is discarded after disposal', (
    tester,
  ) async {
    await pumpLoader(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent - 100);
    await tester.pumpAndSettle();
    final context = tester.element(find.byKey(listKey));
    // Dispatch without advancing a frame so disposal precedes the queued read.
    UserScrollNotification(
      metrics: scroll.position,
      context: context,
      direction: ScrollDirection.reverse,
    ).dispatch(context);
    ScrollUpdateNotification(
      metrics: scroll.position,
      context: context,
      scrollDelta: 1,
    ).dispatch(context);
    expect(repository.reads, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(repository.reads, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
