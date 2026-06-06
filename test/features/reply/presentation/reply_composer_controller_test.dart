import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_controller.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';

void main() {
  group('ReplyComposerController', () {
    test('restores thread draft on build', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final args = _threadArgs(tid: '572063');
      await draftRepository.saveDraft(
        ReplyDraftSnapshot(
          identity: args.identity,
          message: '恢复的草稿',
          useSignature: false,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        replyComposerControllerProvider(args).future,
      );

      expect(state.message, '恢复的草稿');
      expect(state.useSignature, isFalse);
      expect(state.mode, ReplyComposerMode.source);
    });

    test('different thread does not reuse draft', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      await draftRepository.saveDraft(
        ReplyDraftSnapshot(
          identity: ReplyDraftIdentity.thread(fid: '33', tid: '572063'),
          message: '旧帖子草稿',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      final args = _threadArgs(tid: '572064');
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        replyComposerControllerProvider(args).future,
      );

      expect(state.message, isEmpty);
    });

    test('flushDraft saves latest message and signature state', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );

      controller.updateMessage('新的草稿');
      controller.toggleUseSignature(false);
      await controller.flushDraft();

      final saved = await draftRepository.loadDraft(args.identity);
      expect(saved?.message, '新的草稿');
      expect(saved?.useSignature, isFalse);
    });

    test('empty input does not submit', () async {
      final replyRepository = _FakeReplyRepository();
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(replyRepository: replyRepository);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);

      final result = await container
          .read(replyComposerControllerProvider(args).notifier)
          .submit();

      expect(result.sent, isFalse);
      expect(replyRepository.sentDrafts, isEmpty);
      expect(
        container.read(replyComposerControllerProvider(args)).value?.errorMessage,
        contains('请输入回复内容'),
      );
    });

    test('successful submit sends draft and deletes saved draft', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final replyRepository = _FakeReplyRepository(
        result: const ApiSuccess<ReplySubmissionResult>(
          ReplySubmissionResult(message: '回复发布成功'),
        ),
      );
      final args = _threadArgs(tid: '572063');
      await draftRepository.saveDraft(
        ReplyDraftSnapshot(
          identity: args.identity,
          message: '旧草稿',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      final container = _buildContainer(
        draftRepository: draftRepository,
        replyRepository: replyRepository,
      );
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );
      controller.updateMessage('提交内容');
      controller.toggleUseSignature(false);

      final result = await controller.submit();

      expect(result.sent, isTrue);
      expect(replyRepository.sentDrafts, hasLength(1));
      expect(replyRepository.sentDrafts.single.fid, '33');
      expect(replyRepository.sentDrafts.single.tid, '572063');
      expect(replyRepository.sentDrafts.single.message, '提交内容');
      expect(replyRepository.sentDrafts.single.useSignature, isFalse);
      expect(await draftRepository.loadDraft(args.identity), isNull);
    });

    test('failed submit keeps draft and exposes error', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final replyRepository = _FakeReplyRepository(
        result: const ApiFailure<ReplySubmissionResult>(
          ApiError(type: ApiErrorType.network, message: '网络失败'),
        ),
      );
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(
        draftRepository: draftRepository,
        replyRepository: replyRepository,
      );
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );
      controller.updateMessage('失败也要保留');

      final result = await controller.submit();

      expect(result.sent, isFalse);
      expect(
        container.read(replyComposerControllerProvider(args)).value?.errorMessage,
        '网络失败',
      );
      expect((await draftRepository.loadDraft(args.identity))?.message, '失败也要保留');
    });

    test('switchMode updates mode without changing message or signature', () async {
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer();
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );

      controller.updateMessage('[b]源码[/b]');
      controller.toggleUseSignature(false);
      controller.switchMode(ReplyComposerMode.preview);

      final state = container.read(replyComposerControllerProvider(args)).value;
      expect(state?.mode, ReplyComposerMode.preview);
      expect(state?.message, '[b]源码[/b]');
      expect(state?.useSignature, isFalse);
    });

    test('submit sends source message while in preview mode', () async {
      final replyRepository = _FakeReplyRepository();
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(replyRepository: replyRepository);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );

      controller.updateMessage('[quote]源码内容[/quote]');
      controller.switchMode(ReplyComposerMode.preview);
      final result = await controller.submit();

      expect(result.sent, isTrue);
      expect(replyRepository.sentDrafts.single.message, '[quote]源码内容[/quote]');
    });
  });
}

ReplyComposerArgs _threadArgs({required String tid}) {
  return ReplyComposerArgs(
    target: ReplyTarget.thread(fid: '33', tid: tid),
  );
}

ProviderContainer _buildContainer({
  ReplyDraftRepository? draftRepository,
  ReplyRepository? replyRepository,
}) {
  return ProviderContainer(
    overrides: [
      replyDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryReplyDraftRepository(),
      ),
      replyRepositoryProvider.overrideWithValue(
        replyRepository ?? _FakeReplyRepository(),
      ),
    ],
  );
}

ProviderSubscription<AsyncValue<ReplyComposerState>> _keepComposerAlive(
  ProviderContainer container,
  ReplyComposerArgs args,
) {
  return container.listen<AsyncValue<ReplyComposerState>>(
    replyComposerControllerProvider(args),
    (_, _) {},
  );
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
