import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_cache_storage.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_attachment_verification_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_verification_service.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_controller_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_submission_outcome.dart';

part 'composer_controller_base_test_fakes.dart';

final _testControllerProvider = AsyncNotifierProvider.autoDispose
    .family<_TestComposerController, _TestComposerState, _TestArgs>(
      (args) => _TestComposerController(args),
    );

void main() {
  group('ComposerControllerBase', () {
    test('restores message and useSignature from draft snapshot', () async {
      final draftRepository = _MemoryDraftRepository();
      final args = _TestArgs(fid: '33', tid: '572063');
      await draftRepository.saveDraft(
        ComposerDraftSnapshot(
          identity: args.identity,
          message: '上次的草稿',
          useSignature: false,
          updatedAt: DateTime.utc(2026, 6, 8),
        ),
      );
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      _keepAlive(container, args);

      final state = await container.read(_testControllerProvider(args).future);

      expect(state.message, '上次的草稿');
      expect(state.useSignature, isFalse);
      expect(state.restoredDraft, isTrue);
    });

    test('updateMessage saves draft on flush', () async {
      final draftRepository = _MemoryDraftRepository();
      final args = _TestArgs(fid: '33', tid: '572063');
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);

      controller.updateMessage('正文');
      // 防抖中尚未落盘
      expect(await draftRepository.loadDraft(args.identity), isNull);

      await controller.flushDraft();

      expect((await draftRepository.loadDraft(args.identity))?.message, '正文');
    });

    test(
      'resetDraft clears persisted content, preserves signature, and ignores late upload events',
      () async {
        final draftRepository = _MemoryDraftRepository();
        final coordinator = _ControllableUploadCoordinator();
        addTearDown(coordinator.close);
        final args = _TestArgs(fid: '33', tid: '572063');
        final container = _buildContainer(
          draftRepository: draftRepository,
          imagePicker: _FakeImagePicker(
            images: const [
              ComposerPickedImage(
                path: '/gallery/first.jpg',
                fileName: 'first.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: coordinator,
        );
        addTearDown(container.dispose);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );

        controller.toggleUseSignature(false);
        controller.updateMessage('正文');
        final beforeUpload = controller.latestState!;
        await controller.pickImages(
          insertionAnchor: ComposerInsertionAnchor(
            baseRevision: beforeUpload.messageRevision,
            selection: ComposerSelection(
              start: beforeUpload.message.length,
              end: beforeUpload.message.length,
            ),
            mode: ComposerEditorMode.source,
          ),
        );
        coordinator.emitStarted();
        await _drain();
        await controller.flushDraft();

        expect(
          container.read(_testControllerProvider(args)).value?.imageAttachments,
          hasLength(1),
        );
        expect(await draftRepository.loadDraft(args.identity), isNotNull);

        await controller.resetDraft();
        coordinator.emitUploaded(aid: 'late-aid');
        coordinator.emitCompleted();
        await _drain();

        final state = container.read(_testControllerProvider(args)).value!;
        expect(state.message, isEmpty);
        expect(state.imageAttachments, isEmpty);
        expect(state.isUploadingImages, isFalse);
        expect(state.imageUploadCurrent, 0);
        expect(state.imageUploadTotal, 0);
        expect(state.useSignature, isFalse);
        expect(state.restoredDraft, isFalse);
        expect(coordinator.cancelled, isTrue);
        expect(await draftRepository.loadDraft(args.identity), isNull);
      },
    );

    test('image upload event inserts attach code and saves draft', () async {
      final draftRepository = _MemoryDraftRepository();
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
      final coordinator = _FakeUploadCoordinator(
        events: [
          const ComposerImageUploadEvent.started(
            localId: '',
            current: 1,
            total: 1,
          ),
          ComposerImageUploadEvent.uploaded(
            localId: '',
            current: 1,
            total: 1,
            uploadedImage: ComposerUploadedImage(
              localId: '',
              aid: '789',
              uploadedAt: DateTime.utc(2026, 6, 8),
            ),
          ),
          const ComposerImageUploadEvent.completed(total: 1),
        ],
      );
      final args = _TestArgs(fid: '33', tid: '572063');
      final container = _buildContainer(
        draftRepository: draftRepository,
        imagePicker: imagePicker,
        imageUploadCoordinator: coordinator,
      );
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);

      final beforeUpload = container.read(_testControllerProvider(args)).value!;
      await controller.pickImages(
        insertionAnchor: ComposerInsertionAnchor(
          baseRevision: beforeUpload.messageRevision,
          selection: ComposerSelection(
            start: beforeUpload.message.length,
            end: beforeUpload.message.length,
          ),
          mode: ComposerEditorMode.source,
        ),
      );
      await _drain();
      await controller.flushDraft();

      final state = container.read(_testControllerProvider(args)).value!;
      expect(state.message, '[attach]789[/attach]\n');
      expect(
        state.lastMessageMutation?.resultSelection,
        ComposerSelection(
          start: state.message.length,
          end: state.message.length,
        ),
      );
      expect(state.imageAttachments.single.aid, '789');
      expect(
        state.imageAttachments.single.status,
        ComposerImageAttachmentStatus.uploaded,
      );
      final saved = await draftRepository.loadDraft(args.identity);
      expect(saved?.imageAttachments.single.aid, '789');
    });

    test(
      'verification retry preserves attachments uploaded while in flight',
      () async {
        final drafts = _MemoryDraftRepository();
        final args = _TestArgs(fid: '33', tid: '572063');
        final originalAttachment = ComposerImageAttachment(
          localId: 'restored-12',
          localPath: '/gallery/12.jpg',
          fileName: '12.jpg',
          mimeType: 'image/jpeg',
          order: 0,
          status: ComposerImageAttachmentStatus.uploaded,
          aid: '12',
          uploadedAt: DateTime.utc(2026, 8, 3),
        );
        await drafts.saveDraft(
          ComposerDraftSnapshot(
            identity: args.identity,
            message: '[attach]12[/attach]',
            useSignature: true,
            updatedAt: DateTime.utc(2026, 8, 3),
            imageAttachments: [originalAttachment],
          ),
        );
        final verification = _ControllableDraftVerificationService();
        final coordinator = _ControllableUploadCoordinator();
        addTearDown(coordinator.close);
        final container = _buildContainer(
          draftRepository: drafts,
          verificationService: verification,
          imagePicker: _FakeImagePicker(
            images: const [
              ComposerPickedImage(
                path: '/gallery/new.jpg',
                fileName: 'new.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: coordinator,
        );
        addTearDown(container.dispose);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );

        final retry = controller.retryDraftAttachmentVerification();
        await _drain();
        final beforeUpload = controller.latestState!;
        await controller.pickImages(
          insertionAnchor: ComposerInsertionAnchor(
            baseRevision: beforeUpload.messageRevision,
            selection: ComposerSelection(
              start: beforeUpload.message.length,
              end: beforeUpload.message.length,
            ),
            mode: ComposerEditorMode.source,
          ),
        );
        coordinator.emitStarted();
        coordinator.emitUploaded(aid: '99');
        coordinator.emitCompleted();
        await _drain();

        verification.completeRetryWithInvalidAid('12');
        await retry;

        final state = container.read(_testControllerProvider(args)).value!;
        expect(state.message, contains('[attach]12[/attach]'));
        expect(state.message, contains('[attach]99[/attach]'));
        expect(state.imageAttachments.map((item) => item.aid), <String?>['99']);
        expect(state.draftAttachmentVerification.checkedAids, <String>{'12'});
        expect(
          (await drafts.loadDraft(args.identity))?.imageAttachments.single.aid,
          '99',
        );
      },
    );

    test(
      'local attachment delegate applies without mutating root message',
      () async {
        final args = _TestArgs(fid: '33', tid: '572063');
        final container = _buildContainer(
          imagePicker: _FakeImagePicker(
            images: const [
              ComposerPickedImage(
                path: '/gallery/local.jpg',
                fileName: 'local.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: _FakeUploadCoordinator(
            events: [
              const ComposerImageUploadEvent.started(
                localId: '',
                current: 1,
                total: 1,
              ),
              ComposerImageUploadEvent.uploaded(
                localId: '',
                current: 1,
                total: 1,
                uploadedImage: ComposerUploadedImage(
                  localId: '',
                  aid: '792',
                  uploadedAt: DateTime.utc(2026, 8, 2),
                ),
              ),
              const ComposerImageUploadEvent.completed(total: 1),
            ],
          ),
        );
        addTearDown(container.dispose);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );
        controller.updateMessage('根正文');
        List<String>? insertedCodes;

        await controller.pickImages(
          insertionAnchor: ComposerInsertionAnchor(
            // Local revisions are intentionally unrelated to the root tracker.
            baseRevision: 100,
            selection: const ComposerSelection(start: 1, end: 1),
            mode: ComposerEditorMode.quill,
            localAttachmentInsertion: (codes) {
              insertedCodes = codes;
              return ComposerLocalAttachmentInsertionResult.applied;
            },
          ),
        );
        await _drain();

        final state = container.read(_testControllerProvider(args)).value!;
        expect(insertedCodes, ['[attach]792[/attach]']);
        expect(state.message, '根正文');
        expect(state.pendingAttachmentAids, isEmpty);
        expect(state.lastMessageMutation, isNull);
      },
    );

    test(
      'stale local attachment delegate moves uploaded aid to pending',
      () async {
        final args = _TestArgs(fid: '33', tid: '572063');
        final container = _buildContainer(
          imagePicker: _FakeImagePicker(
            images: const [
              ComposerPickedImage(
                path: '/gallery/stale.jpg',
                fileName: 'stale.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: _FakeUploadCoordinator(
            events: [
              const ComposerImageUploadEvent.started(
                localId: '',
                current: 1,
                total: 1,
              ),
              ComposerImageUploadEvent.uploaded(
                localId: '',
                current: 1,
                total: 1,
                uploadedImage: ComposerUploadedImage(
                  localId: '',
                  aid: '793',
                  uploadedAt: DateTime.utc(2026, 8, 2),
                ),
              ),
              const ComposerImageUploadEvent.completed(total: 1),
            ],
          ),
        );
        addTearDown(container.dispose);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );

        await controller.pickImages(
          insertionAnchor: ComposerInsertionAnchor(
            baseRevision: 0,
            selection: const ComposerSelection(start: 0, end: 0),
            mode: ComposerEditorMode.quill,
            localAttachmentInsertion: (_) =>
                ComposerLocalAttachmentInsertionResult.stale,
          ),
        );
        await _drain();

        final state = container.read(_testControllerProvider(args)).value!;
        expect(state.message, isEmpty);
        expect(state.pendingAttachmentAids, ['793']);
      },
    );

    test(
      'upload without an anchor stays pending until a new position is chosen',
      () async {
        final args = _TestArgs(fid: '33', tid: '572063');
        final container = _buildContainer(
          imagePicker: _FakeImagePicker(
            images: const [
              ComposerPickedImage(
                path: '/gallery/pending.jpg',
                fileName: 'pending.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: _FakeUploadCoordinator(
            events: [
              ComposerImageUploadEvent.uploaded(
                localId: '',
                current: 1,
                total: 1,
                uploadedImage: ComposerUploadedImage(
                  localId: '',
                  aid: '790',
                  uploadedAt: DateTime.utc(2026, 6, 8),
                ),
              ),
              const ComposerImageUploadEvent.completed(total: 1),
            ],
          ),
        );
        addTearDown(container.dispose);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );

        await controller.pickImages();
        await _drain();

        final pending = container.read(_testControllerProvider(args)).value!;
        expect(pending.message, isEmpty);
        expect(pending.pendingAttachmentAids, ['790']);

        await controller.insertPendingAttachments(
          ComposerInsertionAnchor(
            baseRevision: pending.messageRevision,
            selection: const ComposerSelection(start: 0, end: 0),
            mode: ComposerEditorMode.source,
          ),
        );

        final inserted = container.read(_testControllerProvider(args)).value!;
        expect(inserted.message, '[attach]790[/attach]\n');
        expect(inserted.pendingAttachmentAids, isEmpty);
        expect(inserted.pendingAttachmentNotice, isNull);
      },
    );

    test('unsafe selection recovery keeps the uploaded aid pending', () async {
      final args = _TestArgs(fid: '33', tid: '572063');
      final coordinator = _ControllableUploadCoordinator();
      addTearDown(coordinator.close);
      final container = _buildContainer(
        imagePicker: _FakeImagePicker(
          images: const [
            ComposerPickedImage(
              path: '/gallery/unsafe.jpg',
              fileName: 'unsafe.jpg',
              mimeType: 'image/jpeg',
              originalIndex: 0,
            ),
          ],
        ),
        imageUploadCoordinator: coordinator,
      );
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);
      controller.updateMessage('你好世界');
      final beforeUpload = controller.latestState!;
      await controller.pickImages(
        insertionAnchor: ComposerInsertionAnchor(
          baseRevision: beforeUpload.messageRevision,
          selection: const ComposerSelection(start: 2, end: 2),
          mode: ComposerEditorMode.source,
        ),
      );
      coordinator.emitStarted();
      await _drain();
      controller.updateMessage('新内容');
      coordinator.emitUploaded(aid: '791');
      coordinator.emitCompleted();
      await _drain();

      final state = container.read(_testControllerProvider(args)).value!;
      expect(state.message, '新内容');
      expect(state.message, isNot(contains('[attach]791[/attach]')));
      expect(state.pendingAttachmentAids, ['791']);
    });

    test(
      'preflight failure short-circuits submit and does not call performSubmit',
      () async {
        final args = _TestArgs(fid: '33', tid: '572063');
        final container = _buildContainer();
        addTearDown(container.dispose);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );

        // 默认 preflight：message 为空 → 返回 '请输入内容'
        final result = await controller.submit();

        expect(result.sent, isFalse);
        expect(controller.performSubmitCallCount, 0);
        expect(
          container.read(_testControllerProvider(args)).value?.failure,
          isA<ComposerValidationFailure>().having(
            (failure) => failure.code,
            'code',
            ComposerValidationFailureCode.contentRequired,
          ),
        );
      },
    );

    test('successful submit clears state and deletes draft', () async {
      final draftRepository = _MemoryDraftRepository();
      final args = _TestArgs(fid: '33', tid: '572063');
      await draftRepository.saveDraft(
        ComposerDraftSnapshot(
          identity: args.identity,
          message: '初始草稿',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
      );
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container.read(_testControllerProvider(args).notifier);

      controller.updateMessage('提交内容');
      controller.outcome = const ComposerSubmissionOutcome.success(
        rawDetail: '完成',
      );
      final result = await controller.submit();

      expect(result.sent, isTrue);
      expect(result.rawSuccessDetail, '完成');
      expect(controller.performSubmitCallCount, 1);
      final state = container.read(_testControllerProvider(args)).value!;
      expect(state.message, isEmpty);
      expect(state.imageAttachments, isEmpty);
      expect(await draftRepository.loadDraft(args.identity), isNull);
    });

    test(
      'successful submit cleans an unpersisted managed image copy',
      () async {
        final cacheStorage = _RecordingUploadCacheStorage();
        final coordinator = _FakeUploadCoordinator(
          events: [
            const ComposerImageUploadEvent.started(
              localId: '',
              current: 1,
              total: 1,
            ),
            ComposerImageUploadEvent.uploaded(
              localId: '',
              current: 1,
              total: 1,
              uploadedImage: ComposerUploadedImage(
                localId: '',
                aid: '789',
                uploadedAt: DateTime.utc(2026, 8, 3),
                cachePath: '/cache/reply_uploads/local/preview.jpg',
              ),
            ),
            const ComposerImageUploadEvent.completed(total: 1),
          ],
        );
        final args = _TestArgs(fid: '33', tid: '572063');
        final container = _buildContainer(
          cacheStorage: cacheStorage,
          imagePicker: _FakeImagePicker(
            images: const [
              ComposerPickedImage(
                path: '/gallery/photo.jpg',
                fileName: 'photo.jpg',
                mimeType: 'image/jpeg',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: coordinator,
        );
        addTearDown(container.dispose);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );

        await controller.pickImages(
          insertionAnchor: const ComposerInsertionAnchor(
            baseRevision: 0,
            selection: ComposerSelection(start: 0, end: 0),
            mode: ComposerEditorMode.source,
          ),
        );
        await _drain();
        controller.outcome = const ComposerSubmissionOutcome.success();

        final result = await controller.submit();

        expect(result.sent, isTrue);
        expect(cacheStorage.deletedPaths, <String>[
          '/cache/reply_uploads/local/preview.jpg',
        ]);
      },
    );

    test(
      'failed submit preserves draft and writes structured failure',
      () async {
        final draftRepository = _MemoryDraftRepository();
        final args = _TestArgs(fid: '33', tid: '572063');
        final container = _buildContainer(draftRepository: draftRepository);
        addTearDown(container.dispose);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );

        controller.updateMessage('失败也要保留');
        controller.outcome = const ComposerSubmissionOutcome.failure(
          failure: ComposerSubmissionFailure(
            code: ComposerSubmissionFailureCode.network,
            kind: ComposerKind.reply,
            detail: '网络异常',
          ),
        );
        final result = await controller.submit();

        expect(result.sent, isFalse);
        expect(
          result.failure,
          isA<ComposerSubmissionFailure>().having(
            (failure) => failure.code,
            'code',
            ComposerSubmissionFailureCode.network,
          ),
        );
        expect(
          container.read(_testControllerProvider(args)).value?.failure,
          same(result.failure),
        );
        final saved = await draftRepository.loadDraft(args.identity);
        expect(saved?.message, '失败也要保留');
      },
    );

    test(
      'duplicate submit while submitting does not call performSubmit twice',
      () async {
        final args = _TestArgs(fid: '33', tid: '572063');
        final container = _buildContainer();
        addTearDown(container.dispose);
        _keepAlive(container, args);
        await container.read(_testControllerProvider(args).future);
        final controller = container.read(
          _testControllerProvider(args).notifier,
        );
        final completer = Completer<ComposerSubmissionOutcome>();
        controller.outcomeFuture = completer.future;
        controller.updateMessage('提交内容');

        final first = controller.submit();
        final second = await controller.submit();
        completer.complete(
          const ComposerSubmissionOutcome.success(rawDetail: 'ok'),
        );
        await first;

        expect(controller.performSubmitCallCount, 1);
        expect(second.sent, isFalse);
      },
    );
  });
}

/// 占位：本测试目前只覆盖事件循环驱动的简单流程，不需要伪造 fakeAsync。
