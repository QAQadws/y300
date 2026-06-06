import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';

void main() {
  testWidgets('ReplyComposerPage shows minimal composer UI', (tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    expect(find.text('回复帖子'), findsOneWidget);
    expect(find.text('源码'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.byKey(const Key('reply-composer-mode-switch')), findsOneWidget);
    expect(find.byKey(const Key('reply-composer-message-input')), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-use-signature-switch')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-send-button')), findsOneWidget);
  });

  testWidgets('ReplyComposerPage restores draft into input', (tester) async {
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository();
    await draftRepository.saveDraft(
      ReplyDraftSnapshot(
        identity: args.identity,
        message: '恢复的草稿',
        useSignature: false,
        updatedAt: DateTime.utc(2026, 6, 6),
      ),
    );

    await tester.pumpWidget(
      _buildPage(args: args, draftRepository: draftRepository),
    );
    await tester.pump();

    expect(find.text('恢复的草稿'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('reply-composer-use-signature-switch')),
    );
    expect(switchTile.value, isFalse);
  });

  testWidgets('ReplyComposerPage keeps send disabled for empty input', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('reply-composer-send-button')),
    );
    expect(sendButton.onPressed, isNull);
  });

  testWidgets('ReplyComposerPage switches between source and preview modes', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '[b]粗体内容[/b]',
    );
    await tester.pump();
    await tester.tap(find.text('预览'));
    await tester.pump();

    expect(
      find.byKey(const Key('reply-composer-bbcode-preview-panel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-message-input')), findsNothing);
    expect(find.text('粗体内容', findRichText: true), findsOneWidget);

    await tester.tap(find.text('源码'));
    await tester.pump();

    expect(find.byKey(const Key('reply-composer-message-input')), findsOneWidget);
    expect(find.text('[b]粗体内容[/b]'), findsOneWidget);
  });

  testWidgets('ReplyComposerPage pops sent result after successful submit', (
    tester,
  ) async {
    final replyRepository = _FakeReplyRepository(
      result: const ApiSuccess<ReplySubmissionResult>(
        ReplySubmissionResult(message: '回复发布成功'),
      ),
    );
    ReplyComposerResult? poppedResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replyDraftRepositoryProvider.overrideWithValue(
            _MemoryReplyDraftRepository(),
          ),
          replyRepositoryProvider.overrideWithValue(replyRepository),
        ],
        child: MaterialApp(
          home: _ReplyComposerLauncher(
            onResult: (result) {
              poppedResult = result;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '提交内容',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(replyRepository.sentDrafts.single.message, '提交内容');
    expect(poppedResult?.sent, isTrue);
    expect(poppedResult?.message, '回复发布成功');
  });

  testWidgets('ReplyComposerPage submits source message from preview mode', (
    tester,
  ) async {
    final replyRepository = _FakeReplyRepository(
      result: const ApiSuccess<ReplySubmissionResult>(
        ReplySubmissionResult(message: '回复发布成功'),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replyDraftRepositoryProvider.overrideWithValue(
            _MemoryReplyDraftRepository(),
          ),
          replyRepositoryProvider.overrideWithValue(replyRepository),
        ],
        child: MaterialApp(
          home: _ReplyComposerLauncher(onResult: (_) {}),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '[quote]原始源码[/quote]',
    );
    await tester.pump();
    await tester.tap(find.text('预览'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(replyRepository.sentDrafts.single.message, '[quote]原始源码[/quote]');
  });
}

Widget _buildPage({
  ReplyComposerArgs? args,
  ReplyDraftRepository? draftRepository,
  ReplyRepository? replyRepository,
}) {
  return ProviderScope(
    overrides: [
      replyDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryReplyDraftRepository(),
      ),
      replyRepositoryProvider.overrideWithValue(
        replyRepository ?? _FakeReplyRepository(),
      ),
    ],
    child: MaterialApp(
      home: ReplyComposerPage(args: args ?? _threadArgs()),
    ),
  );
}

ReplyComposerArgs _threadArgs() {
  return const ReplyComposerArgs(
    target: ReplyTarget.thread(fid: '33', tid: '572063'),
  );
}

class _ReplyComposerLauncher extends StatelessWidget {
  const _ReplyComposerLauncher({
    required this.onResult,
  });

  final ValueChanged<ReplyComposerResult> onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('open-reply-composer-page'),
          onPressed: () async {
            final result = await Navigator.of(context).push<ReplyComposerResult>(
              MaterialPageRoute<ReplyComposerResult>(
                builder: (_) => ReplyComposerPage(args: _threadArgs()),
              ),
            );
            if (result != null) {
              onResult(result);
            }
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

class _MemoryReplyDraftRepository implements ReplyDraftRepository {
  final Map<String, ReplyDraftSnapshot> _drafts = <String, ReplyDraftSnapshot>{};

  @override
  Future<void> deleteDraft(ReplyDraftIdentity identity) async {
    _drafts.remove(identity.storageKey);
  }

  @override
  Future<List<ReplyDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    return _drafts.values
        .where((draft) => draft.identity.fid == fid && draft.identity.tid == tid)
        .toList(growable: false);
  }

  @override
  Future<ReplyDraftSnapshot?> loadDraft(ReplyDraftIdentity identity) async {
    return _drafts[identity.storageKey];
  }

  @override
  Future<void> saveDraft(ReplyDraftSnapshot draft) async {
    if (draft.isEmpty) {
      _drafts.remove(draft.identity.storageKey);
      return;
    }
    _drafts[draft.identity.storageKey] = draft;
  }
}

class _FakeReplyRepository implements ReplyRepository {
  _FakeReplyRepository({
    ApiResult<ReplySubmissionResult>? result,
  }) : result =
            result ??
            const ApiSuccess<ReplySubmissionResult>(
              ReplySubmissionResult(message: '回复成功'),
            );

  final ApiResult<ReplySubmissionResult> result;
  final List<ReplyDraft> sentDrafts = <ReplyDraft>[];

  @override
  Future<ApiResult<ReplySubmissionResult>> sendReply({
    required ReplyDraft draft,
  }) async {
    sentDrafts.add(draft);
    return result;
  }
}
