import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/data/reply_image_picker.dart';
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
        '网络异常，请稍后重试',
      );
      expect((await draftRepository.loadDraft(args.identity))?.message, '失败也要保留');
    });

    test('build prunes drafts and tolerates prune failure', () async {
      final draftRepository = _MemoryReplyDraftRepository()
        ..throwOnPrune = true;
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        replyComposerControllerProvider(args).future,
      );

      expect(draftRepository.pruneCallCount, 1);
      expect(state.message, isEmpty);
    });

    test('restored draft flag is true when draft exists', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final args = _threadArgs(tid: '572063');
      await draftRepository.saveDraft(
        ReplyDraftSnapshot(
          identity: args.identity,
          message: '旧草稿',
          useSignature: true,
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

      expect(state.restoredDraft, isTrue);
    });

    test('pickImages adds local image attachments in picker order', () async {
      final imagePicker = _FakeReplyImagePicker(
        images: const [
          ReplyPickedImage(
            path: '/gallery/first.jpg',
            fileName: 'first.jpg',
            mimeType: 'image/jpeg',
            originalIndex: 0,
          ),
          ReplyPickedImage(
            path: '/gallery/second.png',
            fileName: 'second.png',
            mimeType: 'image/png',
            originalIndex: 1,
          ),
        ],
      );
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(imagePicker: imagePicker);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);

      await container
          .read(replyComposerControllerProvider(args).notifier)
          .pickImages();

      final state = container.read(replyComposerControllerProvider(args)).value!;
      expect(imagePicker.pickCallCount, 1);
      expect(state.imageAttachments, hasLength(2));
      expect(state.imageAttachments.map((item) => item.fileName), [
        'first.jpg',
        'second.png',
      ]);
      expect(
        state.imageAttachments.map((item) => item.status),
        [
          ReplyImageAttachmentStatus.local,
          ReplyImageAttachmentStatus.local,
        ],
      );
      expect(state.message, isEmpty);
    });

    test('pickImages cancellation does not change state or draft', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final imagePicker = _FakeReplyImagePicker();
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(
        draftRepository: draftRepository,
        imagePicker: imagePicker,
      );
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );
      controller.updateMessage('正文');

      await controller.pickImages();

      final state = container.read(replyComposerControllerProvider(args)).value!;
      expect(state.imageAttachments, isEmpty);
      expect(state.message, '正文');
      expect(await draftRepository.loadDraft(args.identity), isNull);
    });

    test('pickImages exposes picker error', () async {
      final imagePicker = _FakeReplyImagePicker(
        error: const ReplyImagePickerException('failed'),
      );
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(imagePicker: imagePicker);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);

      await container
          .read(replyComposerControllerProvider(args).notifier)
          .pickImages();

      expect(
        container
            .read(replyComposerControllerProvider(args))
            .value
            ?.imageUploadError,
        '选择图片失败，请重试',
      );
    });

    test('pickImages does not run while preparing post reply', () async {
      final imagePicker = _FakeReplyImagePicker(
        images: const [
          ReplyPickedImage(
            path: '/gallery/first.jpg',
            fileName: 'first.jpg',
            mimeType: 'image/jpeg',
            originalIndex: 0,
          ),
        ],
      );
      final args = _postArgs();
      final container = _buildContainer(imagePicker: imagePicker);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);

      await container
          .read(replyComposerControllerProvider(args).notifier)
          .pickImages();

      expect(imagePicker.pickCallCount, 0);
      expect(
        container
            .read(replyComposerControllerProvider(args))
            .value
            ?.imageAttachments,
        isEmpty,
      );
    });

    test('duplicate submit while submitting does not call repository twice', () async {
      final completer = Completer<ApiResult<ReplySubmissionResult>>();
      final replyRepository = _FakeReplyRepository(asyncResult: completer.future);
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(replyRepository: replyRepository);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );
      controller.updateMessage('提交内容');

      final first = controller.submit();
      final second = await controller.submit();
      completer.complete(
        const ApiSuccess<ReplySubmissionResult>(
          ReplySubmissionResult(message: '回复成功'),
        ),
      );
      await first;

      expect(second.sent, isFalse);
      expect(replyRepository.sentDrafts, hasLength(1));
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

    test('post reply restores post draft and prepares reference', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final replyRepository = _FakeReplyRepository();
      final args = _postArgs();
      await draftRepository.saveDraft(
        ReplyDraftSnapshot(
          identity: args.identity,
          message: '楼层草稿',
          useSignature: false,
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

      final initialState = await container.read(
        replyComposerControllerProvider(args).future,
      );
      expect(initialState.message, '楼层草稿');
      expect(initialState.useSignature, isFalse);

      await _drainMicrotasks();
      final preparedState = container.read(
        replyComposerControllerProvider(args),
      ).value;
      expect(replyRepository.prepareCallCount, 1);
      expect(preparedState?.preparation?.reference.noticeTrimStr, '[quote]引用[/quote]');
    });

    test('post reply submit passes prepared reference fields', () async {
      final replyRepository = _FakeReplyRepository();
      final args = _postArgs();
      final container = _buildContainer(replyRepository: replyRepository);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      await _drainMicrotasks();
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );

      controller.updateMessage('回复楼层');
      final result = await controller.submit();

      expect(result.sent, isTrue);
      final draft = replyRepository.sentDrafts.single;
      expect(draft.formHash, 'prepared-formhash');
      expect(draft.repPid, '41554317');
      expect(draft.repPost, '41554317');
      expect(draft.noticeAuthor, 'notice-token');
      expect(draft.noticeTrimStr, '[quote]引用[/quote]');
      expect(draft.noticeAuthorMsg, '引用正文');
    });

    test('post reply preparation failure disables submit and keeps draft', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final replyRepository = _FakeReplyRepository(
        preparationResult: const ApiFailure<ReplyPreparation>(
          ApiError(type: ApiErrorType.parse, message: '表单解析失败'),
        ),
      );
      final args = _postArgs();
      final container = _buildContainer(
        draftRepository: draftRepository,
        replyRepository: replyRepository,
      );
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      await _drainMicrotasks();
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );
      controller.updateMessage('失败也保留');

      final result = await controller.submit();

      expect(result.sent, isFalse);
      expect(replyRepository.sentDrafts, isEmpty);
      await controller.flushDraft();
      expect((await draftRepository.loadDraft(args.identity))?.message, '失败也保留');
    });
  });
}

ReplyComposerArgs _threadArgs({required String tid}) {
  return ReplyComposerArgs(
    target: ReplyTarget.thread(fid: '33', tid: tid),
  );
}

ReplyComposerArgs _postArgs() {
  final uri = Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=572063&repquote=41554317&mobile=2',
  );
  return ReplyComposerArgs(
    target: ReplyTarget.post(
      fid: '33',
      tid: '572063',
      pid: '41554317',
      sourceUri: uri,
    ),
    replyFormUri: uri,
  );
}

ProviderContainer _buildContainer({
  ReplyDraftRepository? draftRepository,
  ReplyRepository? replyRepository,
  ReplyImagePicker? imagePicker,
}) {
  return ProviderContainer(
    overrides: [
      replyDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryReplyDraftRepository(),
      ),
      replyRepositoryProvider.overrideWithValue(
        replyRepository ?? _FakeReplyRepository(),
      ),
      replyImagePickerProvider.overrideWithValue(
        imagePicker ?? _FakeReplyImagePicker(),
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

Future<void> _drainMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _MemoryReplyDraftRepository implements ReplyDraftRepository {
  final Map<String, ReplyDraftSnapshot> _drafts = <String, ReplyDraftSnapshot>{};
  bool throwOnPrune = false;
  int pruneCallCount = 0;

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
  Future<ReplyDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    pruneCallCount += 1;
    if (throwOnPrune) {
      throw StateError('prune failed');
    }
    return ReplyDraftPruneResult(
      removedCount: 0,
      keptCount: _drafts.length,
    );
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

class _FakeReplyImagePicker implements ReplyImagePicker {
  _FakeReplyImagePicker({
    this.images = const <ReplyPickedImage>[],
    this.error,
  });

  final List<ReplyPickedImage> images;
  final ReplyImagePickerException? error;
  int pickCallCount = 0;

  @override
  Future<List<ReplyPickedImage>> pickImagesInOrder() async {
    pickCallCount += 1;
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return images;
  }
}

class _FakeReplyRepository implements ReplyRepository {
  _FakeReplyRepository({
    ApiResult<ReplySubmissionResult>? result,
    this.asyncResult,
    ApiResult<ReplyPreparation>? preparationResult,
  }) : result =
            result ??
            const ApiSuccess<ReplySubmissionResult>(
              ReplySubmissionResult(message: '回复成功'),
            ),
        preparationResult =
            preparationResult ??
            const ApiSuccess<ReplyPreparation>(
              ReplyPreparation(
                target: ReplyTarget.post(
                  fid: '33',
                  tid: '572063',
                  pid: '41554317',
                ),
                reference: ReplyReference(
                  formHash: 'prepared-formhash',
                  noticeAuthor: 'notice-token',
                  noticeTrimStr: '[quote]引用[/quote]',
                  noticeAuthorMsg: '引用正文',
                  repPid: '41554317',
                  repPost: '41554317',
                ),
              ),
            );

  final ApiResult<ReplySubmissionResult> result;
  final Future<ApiResult<ReplySubmissionResult>>? asyncResult;
  final ApiResult<ReplyPreparation> preparationResult;
  final List<ReplyDraft> sentDrafts = <ReplyDraft>[];
  int prepareCallCount = 0;

  @override
  Future<ApiResult<ReplySubmissionResult>> sendReply({
    required ReplyDraft draft,
  }) async {
    sentDrafts.add(draft);
    final asyncResult = this.asyncResult;
    if (asyncResult != null) {
      return asyncResult;
    }
    return result;
  }

  @override
  Future<ApiResult<ReplyPreparation>> preparePostReply({
    required Uri replyFormUri,
  }) async {
    prepareCallCount += 1;
    return preparationResult;
  }
}
