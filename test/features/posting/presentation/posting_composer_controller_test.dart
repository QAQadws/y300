import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/composer_providers.dart';
import 'package:y300/features/composer_shared/data/composer_upload_notification_service.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_editor_mode.dart';
import 'package:y300/features/posting/data/new_thread_repository.dart';
import 'package:y300/features/posting/data/posting_form_metadata_repository.dart';
import 'package:y300/features/posting/data/posting_providers.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/models/posting_target.dart';
import 'package:y300/features/posting/presentation/posting_composer_controller.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';

part 'posting_composer_controller_test_fakes.dart';

void main() {
  group('PostingComposerController', () {
    test('build loads metadata via microtask after initial state', () async {
      final metadataRepository = _FakeMetadataRepository.success(
        _metadataWithTypes(typeRequired: false),
      );
      final args = _args();
      final container = _buildContainer(
        metadataRepository: metadataRepository,
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);

      final initial = await container.read(
        postingComposerControllerProvider(args).future,
      );
      expect(initial.isLoadingMetadata, isTrue);
      expect(initial.metadata, isNull);
      expect(initial.subject, isEmpty);

      await _drain();
      final state = container
          .read(postingComposerControllerProvider(args))
          .value!;
      expect(state.isLoadingMetadata, isFalse);
      expect(state.metadata?.formHash, 'fh');
      expect(state.metadata?.threadTypes, hasLength(2));
      expect(metadataRepository.callCount, 1);
    });

    test('metadata failure exposes error and retry refetches', () async {
      final metadataRepository = _FakeMetadataRepository.failure(
        const ApiError(type: ApiErrorType.network, message: '网络挂了'),
      );
      final args = _args();
      final container = _buildContainer(
        metadataRepository: metadataRepository,
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);

      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final failed = container
          .read(postingComposerControllerProvider(args))
          .value!;
      expect(failed.isLoadingMetadata, isFalse);
      expect(failed.metadataError, '网络挂了');
      expect(failed.metadata, isNull);

      metadataRepository.queueSuccess(_metadataWithTypes(typeRequired: false));
      await container
          .read(postingComposerControllerProvider(args).notifier)
          .retryLoadMetadata();
      final retried = container
          .read(postingComposerControllerProvider(args))
          .value!;
      expect(retried.isLoadingMetadata, isFalse);
      expect(retried.metadataError, isNull);
      expect(retried.metadata?.formHash, 'fh');
      expect(metadataRepository.callCount, 2);
    });

    test(
      'restored typeid not in metadata is reset to null after metadata load',
      () async {
        final draftRepository = _MemoryDraftRepository();
        final args = _args();
        await draftRepository.saveDraft(
          ComposerDraftSnapshot(
            identity: args.identity,
            message: '正文',
            subject: '老标题',
            useSignature: true,
            updatedAt: DateTime.utc(2026, 6, 8),
            extras: const <String, String>{'typeid': '999'},
          ),
        );
        final metadataRepository = _FakeMetadataRepository.success(
          _metadataWithTypes(typeRequired: false),
        );
        final container = _buildContainer(
          draftRepository: draftRepository,
          metadataRepository: metadataRepository,
        );
        addTearDown(container.dispose);
        final subscription = _keepAlive(container, args);
        addTearDown(subscription.close);

        final initial = await container.read(
          postingComposerControllerProvider(args).future,
        );
        expect(initial.subject, '老标题');
        expect(initial.selectedTypeId, '999');

        await _drain();
        final state = container
            .read(postingComposerControllerProvider(args))
            .value!;
        expect(state.metadata, isNotNull);
        expect(state.selectedTypeId, isNull);
      },
    );
  // PLACEHOLDER_PHASE_4_TESTS_PART_TWO
    test('canSubmit blocks empty subject and required typeid', () async {
      final args = _args();
      final container = _buildContainer(
        metadataRepository: _FakeMetadataRepository.success(
          _metadataWithTypes(typeRequired: true),
        ),
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);

      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final controller = container.read(
        postingComposerControllerProvider(args).notifier,
      );
      controller.updateMessage('正文');
      var state =
          container.read(postingComposerControllerProvider(args)).value!;
      expect(state.canSubmit, isFalse, reason: 'subject 为空');

      controller.updateSubject('我的标题');
      state = container.read(postingComposerControllerProvider(args)).value!;
      expect(state.canSubmit, isFalse, reason: '必选分类未选');

      controller.updateSelectedTypeId('111');
      state = container.read(postingComposerControllerProvider(args)).value!;
      expect(state.canSubmit, isTrue);
    });

    test(
      'submit on required-type forum without typeid blocks repository call',
      () async {
        final newThreadRepository = _FakeNewThreadRepository();
        final args = _args();
        final container = _buildContainer(
          metadataRepository: _FakeMetadataRepository.success(
            _metadataWithTypes(typeRequired: true),
          ),
          newThreadRepository: newThreadRepository,
        );
        addTearDown(container.dispose);
        final subscription = _keepAlive(container, args);
        addTearDown(subscription.close);
        await container.read(postingComposerControllerProvider(args).future);
        await _drain();

        final controller = container.read(
          postingComposerControllerProvider(args).notifier,
        );
        controller.updateSubject('我的标题');
        controller.updateMessage('正文');

        final result = await controller.submit();

        expect(result.sent, isFalse);
        expect(newThreadRepository.submittedPayloads, isEmpty);
        expect(
          container
              .read(postingComposerControllerProvider(args))
              .value
              ?.errorMessage,
          contains('请先选择'),
        );
      },
    );

    test('successful submit deletes draft and clears state', () async {
      final draftRepository = _MemoryDraftRepository();
      final newThreadRepository = _FakeNewThreadRepository();
      final args = _args();
      final container = _buildContainer(
        draftRepository: draftRepository,
        metadataRepository: _FakeMetadataRepository.success(
          _metadataWithTypes(typeRequired: false),
        ),
        newThreadRepository: newThreadRepository,
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final controller = container.read(
        postingComposerControllerProvider(args).notifier,
      );
      controller.updateSubject('标题');
      controller.updateMessage('正文');
      controller.updateSelectedTypeId('111');
      controller.updateAllowNoticeAuthor(true);
      await controller.flushDraft();

      // 草稿落盘后 subject + extras 都被持久化。
      final stored = await draftRepository.loadDraft(args.identity);
      expect(stored?.subject, '标题');
      expect(stored?.extras['typeid'], '111');
      expect(stored?.extras['allowNoticeAuthor'], '1');

      final result = await controller.submit();

      expect(result.sent, isTrue);
      expect(result.tid, '900001');
      expect(result.pid, '910001');
      expect(newThreadRepository.submittedPayloads, hasLength(1));
      expect(newThreadRepository.submittedPayloads.single.subject, '标题');
      expect(newThreadRepository.submittedPayloads.single.message, '正文');
      expect(newThreadRepository.submittedPayloads.single.typeid, '111');

      final state =
          container.read(postingComposerControllerProvider(args)).value!;
      expect(state.subject, isEmpty);
      expect(state.message, isEmpty);
      expect(state.selectedTypeId, isNull);
      expect(state.allowNoticeAuthor, isFalse);
      expect(await draftRepository.loadDraft(args.identity), isNull);
    });

    test('failed submit keeps draft with subject and extras', () async {
      final draftRepository = _MemoryDraftRepository();
      final newThreadRepository = _FakeNewThreadRepository(
        result: const ApiFailure<NewThreadSubmissionResult>(
          ApiError(
            type: ApiErrorType.business,
            code: 'post_flood_ctrl',
            message: '发帖过快',
          ),
        ),
      );
      final args = _args();
      final container = _buildContainer(
        draftRepository: draftRepository,
        metadataRepository: _FakeMetadataRepository.success(
          _metadataWithTypes(typeRequired: false),
        ),
        newThreadRepository: newThreadRepository,
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final controller = container.read(
        postingComposerControllerProvider(args).notifier,
      );
      controller.updateSubject('标题');
      controller.updateMessage('正文');
      controller.updateSelectedTypeId('222');

      final result = await controller.submit();

      expect(result.sent, isFalse);
      expect(
        container
            .read(postingComposerControllerProvider(args))
            .value
            ?.errorMessage,
        '发帖过于频繁，请稍后再试',
      );
      final saved = await draftRepository.loadDraft(args.identity);
      expect(saved?.subject, '标题');
      expect(saved?.message, '正文');
      expect(saved?.extras['typeid'], '222');
    });

    test(
      'pickImages uploads attaches aid into message and submit ships uploaded aid',
      () async {
        final imagePicker = _FakeImagePicker(
          images: const [
            ComposerPickedImage(
              path: '/gallery/first.jpg',
              fileName: 'first.jpg',
              mimeType: 'image/jpeg',
              originalIndex: 0,
            ),
          ],
        );
        final uploadCoordinator = _FakeUploadCoordinator(
          events: [
            ComposerImageUploadEvent.uploaded(
              localId: '',
              current: 1,
              total: 1,
              uploadedImage: ComposerUploadedImage(
                localId: '',
                aid: '777',
                // 用 now() 避免 24h 过期策略把附件清掉，与 reply 测试同样的做法。
                uploadedAt: DateTime.now(),
              ),
            ),
            const ComposerImageUploadEvent.completed(total: 1),
          ],
        );
        final newThreadRepository = _FakeNewThreadRepository();
        final args = _args();
        final container = _buildContainer(
          metadataRepository: _FakeMetadataRepository.success(
            _metadataWithTypes(typeRequired: false),
          ),
          newThreadRepository: newThreadRepository,
          imagePicker: imagePicker,
          imageUploadCoordinator: uploadCoordinator,
        );
        addTearDown(container.dispose);
        final subscription = _keepAlive(container, args);
        addTearDown(subscription.close);
        await container.read(postingComposerControllerProvider(args).future);
        await _drain();

        final controller = container.read(
          postingComposerControllerProvider(args).notifier,
        );
        controller.updateSubject('标题');
        controller.updateMessage('正文');
        await controller.pickImages();
        await _drain();

        final state =
            container.read(postingComposerControllerProvider(args)).value!;
        expect(state.message, '正文\n[attach]777[/attach]');
        expect(state.imageAttachments.single.aid, '777');

        final result = await controller.submit();
        expect(result.sent, isTrue);
        expect(
          newThreadRepository.submittedPayloads.single.uploadedAttachmentAids,
          ['777'],
        );
      },
    );

    test('legacy reply draft restored as reply does not bleed into new thread',
        () async {
      // 老 reply 草稿（无 kind / subject / extras）和新 newthread 草稿在同一个
      // SharedPreferences 命名空间下应该各自独立——身份 key 不同就不会互相覆盖。
      final draftRepository = _MemoryDraftRepository();
      final replyArgs = const ComposerDraftIdentity.thread(
        fid: '33',
        tid: '572063',
      );
      await draftRepository.saveDraft(
        ComposerDraftSnapshot(
          identity: replyArgs,
          message: '回复草稿',
          useSignature: false,
          updatedAt: DateTime.utc(2026, 6, 8),
        ),
      );

      final args = _args();
      final container = _buildContainer(
        draftRepository: draftRepository,
        metadataRepository: _FakeMetadataRepository.success(
          _metadataWithTypes(typeRequired: false),
        ),
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        postingComposerControllerProvider(args).future,
      );

      expect(state.message, isEmpty);
      expect(state.subject, isEmpty);
      expect(state.selectedTypeId, isNull);
      // reply 草稿没动。
      final replyDraft = await draftRepository.loadDraft(replyArgs);
      expect(replyDraft?.message, '回复草稿');
    });

    test('switchMode does not reset subject or selected typeid', () async {
      final args = _args();
      final container = _buildContainer(
        metadataRepository: _FakeMetadataRepository.success(
          _metadataWithTypes(typeRequired: false),
        ),
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final controller = container.read(
        postingComposerControllerProvider(args).notifier,
      );
      controller.updateSubject('标题');
      controller.updateSelectedTypeId('111');
      controller.updateMessage('[b]源码[/b]');
      controller.switchMode(ComposerEditorMode.preview);

      final state =
          container.read(postingComposerControllerProvider(args)).value!;
      expect(state.mode, ComposerEditorMode.preview);
      expect(state.subject, '标题');
      expect(state.selectedTypeId, '111');
      expect(state.message, '[b]源码[/b]');
    });

    test('canSubmit blocks when subject or message exceeds metadata limits',
        () async {
      final args = _args();
      final metadata = _metadataWithLengthLimits(
        maxSubjectLength: 5,
        maxMessageLength: 10,
      );
      final container = _buildContainer(
        metadataRepository: _FakeMetadataRepository.success(metadata),
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final controller = container.read(
        postingComposerControllerProvider(args).notifier,
      );
      controller.updateSubject('在限内');
      controller.updateMessage('正文不超长');

      var state =
          container.read(postingComposerControllerProvider(args)).value!;
      expect(state.canSubmit, isTrue);

      controller.updateSubject('这个标题太长会被拒绝');
      state = container.read(postingComposerControllerProvider(args)).value!;
      expect(state.canSubmit, isFalse, reason: '标题超出 maxSubjectLength=5');

      controller.updateSubject('短标题');
      controller.updateMessage('这条正文超过版块的字数限制了哈哈');
      state = container.read(postingComposerControllerProvider(args)).value!;
      expect(state.canSubmit, isFalse, reason: '正文超出 maxMessageLength=10');
    });

    test(
      'preflight returns over-limit message when subject exceeds threshold',
      () async {
        final newThreadRepository = _FakeNewThreadRepository();
        final args = _args();
        final container = _buildContainer(
          metadataRepository: _FakeMetadataRepository.success(
            _metadataWithLengthLimits(maxSubjectLength: 5),
          ),
          newThreadRepository: newThreadRepository,
        );
        addTearDown(container.dispose);
        final subscription = _keepAlive(container, args);
        addTearDown(subscription.close);
        await container.read(postingComposerControllerProvider(args).future);
        await _drain();

        final controller = container.read(
          postingComposerControllerProvider(args).notifier,
        );
        controller.updateSubject('六个字符的标题');
        controller.updateMessage('正文');

        final result = await controller.submit();

        expect(result.sent, isFalse);
        expect(newThreadRepository.submittedPayloads, isEmpty);
        expect(
          container
              .read(postingComposerControllerProvider(args))
              .value
              ?.errorMessage,
          contains('标题超出版块上限'),
        );
      },
    );

  });
}
