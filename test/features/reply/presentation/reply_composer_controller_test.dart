import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/reply/data/providers/reply_providers.dart';
import 'package:y300/features/reply/data/repositories/reply_repository.dart';
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
    });

    test('restores draft image attachment queue on build', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final args = _threadArgs(tid: '572063');
      await draftRepository.saveDraft(
        ReplyDraftSnapshot(
          identity: args.identity,
          message: '正文\n[attach]123456[/attach]',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 8),
          imageAttachments: [
            _uploadedAttachment(
              localId: 'image-1',
              aid: '123456',
              uploadedAt: DateTime.utc(2026, 6, 8, 10),
            ),
          ],
        ),
      );
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        replyComposerControllerProvider(args).future,
      );

      expect(state.message, '正文\n[attach]123456[/attach]');
      expect(state.imageAttachments, hasLength(1));
      expect(state.imageAttachments.single.localId, 'image-1');
      expect(
        state.imageAttachments.single.status,
        ReplyImageAttachmentStatus.uploaded,
      );
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

    test('new draft uses the device signature default', () async {
      final preferencesRepository = _MemoryComposerPreferencesRepository(
        preferences: const ComposerPreferences(
          defaultSurface: ComposerSurfacePreference.quill,
          newDraftUseSignature: false,
        ),
      );
      final args = _threadArgs(tid: '572064');
      final container = _buildContainer(
        preferencesRepository: preferencesRepository,
      );
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        replyComposerControllerProvider(args).future,
      );

      expect(state.restoredDraft, isFalse);
      expect(state.useSignature, isFalse);
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

    test('flushDraft saves uploaded attachment metadata', () async {
      final draftRepository = _MemoryReplyDraftRepository();
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
      final uploadCoordinator = _FakeReplyImageUploadCoordinator(
        events: [
          ComposerImageUploadEvent.uploaded(
            localId: '',
            current: 1,
            total: 1,
            uploadedImage: ReplyUploadedImage(
              localId: '',
              aid: '123456',
              uploadedAt: DateTime.utc(2026, 6, 8, 10),
            ),
          ),
          const ComposerImageUploadEvent.completed(total: 1),
        ],
      );
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(
        draftRepository: draftRepository,
        imagePicker: imagePicker,
        imageUploadCoordinator: uploadCoordinator,
      );
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );

      await controller.pickImages(
        insertionAnchor: const ComposerInsertionAnchor(
          baseRevision: 0,
          selection: ComposerSelection(start: 0, end: 0),
          mode: ComposerEditorMode.source,
        ),
      );
      await _drainMicrotasks();
      await controller.flushDraft();

      final saved = await draftRepository.loadDraft(args.identity);
      expect(saved?.message, '[attach]123456[/attach]\n');
      expect(saved?.imageAttachments, hasLength(1));
      expect(saved?.imageAttachments.single.aid, '123456');
      expect(
        saved?.imageAttachments.single.uploadedAt,
        DateTime.utc(2026, 6, 8, 10),
      );
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
        container
            .read(replyComposerControllerProvider(args))
            .value
            ?.errorMessage,
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

    test('submit sanitizes expired attachments before sending', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final replyRepository = _FakeReplyRepository();
      final args = _threadArgs(tid: '572063');
      await draftRepository.saveDraft(
        ReplyDraftSnapshot(
          identity: args.identity,
          message: '正文\n[attach]123456[/attach]',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 8),
          imageAttachments: [
            _uploadedAttachment(
              localId: 'expired',
              aid: '123456',
              uploadedAt: DateTime.now().subtract(const Duration(hours: 24)),
            ),
          ],
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

      final result = await container
          .read(replyComposerControllerProvider(args).notifier)
          .submit();

      expect(result.sent, isTrue);
      expect(replyRepository.sentDrafts.single.message, '正文');
      expect(replyRepository.sentDrafts.single.uploadedAttachmentAids, isEmpty);
      final state = container.read(replyComposerControllerProvider(args)).value;
      expect(state?.imageAttachments, isEmpty);
    });

    test(
      'submit binds uploaded attachment aid when attach code remains',
      () async {
        final draftRepository = _MemoryReplyDraftRepository();
        final replyRepository = _FakeReplyRepository();
        final args = _threadArgs(tid: '572063');
        await draftRepository.saveDraft(
          ReplyDraftSnapshot(
            identity: args.identity,
            message: '正文\n[attach]123456[/attach]',
            useSignature: true,
            updatedAt: DateTime.utc(2026, 6, 8),
            imageAttachments: [
              _uploadedAttachment(
                localId: 'image-1',
                aid: '123456',
                uploadedAt: DateTime.now(),
              ),
            ],
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

        final result = await container
            .read(replyComposerControllerProvider(args).notifier)
            .submit();

        expect(result.sent, isTrue);
        expect(replyRepository.sentDrafts.single.uploadedAttachmentAids, [
          '123456',
        ]);
      },
    );

    test(
      'submit skips uploaded attachment aid when attach code is removed',
      () async {
        final draftRepository = _MemoryReplyDraftRepository();
        final replyRepository = _FakeReplyRepository();
        final args = _threadArgs(tid: '572063');
        await draftRepository.saveDraft(
          ReplyDraftSnapshot(
            identity: args.identity,
            message: '正文',
            useSignature: true,
            updatedAt: DateTime.utc(2026, 6, 8),
            imageAttachments: [
              _uploadedAttachment(
                localId: 'image-1',
                aid: '123456',
                uploadedAt: DateTime.now(),
              ),
            ],
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

        final result = await container
            .read(replyComposerControllerProvider(args).notifier)
            .submit();

        expect(result.sent, isTrue);
        expect(
          replyRepository.sentDrafts.single.uploadedAttachmentAids,
          isEmpty,
        );
      },
    );

    test('submit skips non-uploaded attachment statuses', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final replyRepository = _FakeReplyRepository();
      final args = _threadArgs(tid: '572063');
      await draftRepository.saveDraft(
        ReplyDraftSnapshot(
          identity: args.identity,
          message: '正文\n[attach]123[/attach]\n[attach]456[/attach]',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 8),
          imageAttachments: [
            _attachmentWithStatus(
              localId: 'local',
              aid: '123',
              status: ReplyImageAttachmentStatus.local,
            ),
            _attachmentWithStatus(
              localId: 'failed',
              aid: '456',
              status: ReplyImageAttachmentStatus.failed,
            ),
          ],
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

      final result = await container
          .read(replyComposerControllerProvider(args).notifier)
          .submit();

      expect(result.sent, isTrue);
      expect(replyRepository.sentDrafts.single.uploadedAttachmentAids, isEmpty);
    });

    test(
      'submit binds multiple uploaded aids by attach code source order',
      () async {
        final draftRepository = _MemoryReplyDraftRepository();
        final replyRepository = _FakeReplyRepository();
        final args = _threadArgs(tid: '572063');
        await draftRepository.saveDraft(
          ReplyDraftSnapshot(
            identity: args.identity,
            message: '[attach]222[/attach]\n正文\n[attach]111[/attach]',
            useSignature: true,
            updatedAt: DateTime.utc(2026, 6, 8),
            imageAttachments: [
              _uploadedAttachment(
                localId: 'first',
                aid: '111',
                uploadedAt: DateTime.now(),
              ),
              _uploadedAttachment(
                localId: 'second',
                aid: '222',
                uploadedAt: DateTime.now(),
              ),
            ],
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

        final result = await container
            .read(replyComposerControllerProvider(args).notifier)
            .submit();

        expect(result.sent, isTrue);
        expect(replyRepository.sentDrafts.single.uploadedAttachmentAids, [
          '222',
          '111',
        ]);
      },
    );

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
        container
            .read(replyComposerControllerProvider(args))
            .value
            ?.errorMessage,
        '网络异常，请稍后重试',
      );
      expect(
        (await draftRepository.loadDraft(args.identity))?.message,
        '失败也要保留',
      );
    });

    test('failed submit keeps uploaded attachment draft metadata', () async {
      final draftRepository = _MemoryReplyDraftRepository();
      final replyRepository = _FakeReplyRepository(
        result: const ApiFailure<ReplySubmissionResult>(
          ApiError(type: ApiErrorType.network, message: '网络失败'),
        ),
      );
      final args = _threadArgs(tid: '572063');
      await draftRepository.saveDraft(
        ReplyDraftSnapshot(
          identity: args.identity,
          message: '正文\n[attach]123456[/attach]',
          useSignature: true,
          updatedAt: DateTime.utc(2026, 6, 8),
          imageAttachments: [
            _uploadedAttachment(
              localId: 'image-1',
              aid: '123456',
              uploadedAt: DateTime.now(),
            ),
          ],
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

      final result = await container
          .read(replyComposerControllerProvider(args).notifier)
          .submit();

      expect(result.sent, isFalse);
      expect(replyRepository.sentDrafts.single.uploadedAttachmentAids, [
        '123456',
      ]);
      final saved = await draftRepository.loadDraft(args.identity);
      expect(saved?.message, '正文\n[attach]123456[/attach]');
      expect(saved?.imageAttachments, hasLength(1));
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

    test(
      'pickImages uploads selected images and appends attach codes',
      () async {
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
        final uploadCoordinator = _FakeReplyImageUploadCoordinator(
          events: [
            ComposerImageUploadEvent.started(localId: '', current: 1, total: 2),
            ComposerImageUploadEvent.uploaded(
              localId: '',
              current: 1,
              total: 2,
              uploadedImage: ReplyUploadedImage(
                localId: '',
                aid: '111',
                uploadedAt: DateTime.utc(2026, 6, 8),
              ),
            ),
            ComposerImageUploadEvent.started(localId: '', current: 2, total: 2),
            ComposerImageUploadEvent.uploaded(
              localId: '',
              current: 2,
              total: 2,
              uploadedImage: ReplyUploadedImage(
                localId: '',
                aid: '222',
                uploadedAt: DateTime.utc(2026, 6, 8),
              ),
            ),
            const ComposerImageUploadEvent.completed(total: 2),
          ],
        );
        final args = _threadArgs(tid: '572063');
        final container = _buildContainer(
          imagePicker: imagePicker,
          imageUploadCoordinator: uploadCoordinator,
        );
        addTearDown(container.dispose);
        final subscription = _keepComposerAlive(container, args);
        addTearDown(subscription.close);
        await container.read(replyComposerControllerProvider(args).future);

        final controller = container.read(
          replyComposerControllerProvider(args).notifier,
        );
        await controller.pickImages(
          insertionAnchor: const ComposerInsertionAnchor(
            baseRevision: 0,
            selection: ComposerSelection(start: 0, end: 0),
            mode: ComposerEditorMode.source,
          ),
        );
        await _drainMicrotasks();

        final state = container
            .read(replyComposerControllerProvider(args))
            .value!;
        expect(imagePicker.pickCallCount, 1);
        expect(state.imageAttachments, hasLength(2));
        expect(state.imageAttachments.map((item) => item.fileName), [
          'first.jpg',
          'second.png',
        ]);
        expect(state.imageAttachments.map((item) => item.status), [
          ReplyImageAttachmentStatus.uploaded,
          ReplyImageAttachmentStatus.uploaded,
        ]);
        expect(state.message, '[attach]111[/attach]\n[attach]222[/attach]\n');
      },
    );

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

      final state = container
          .read(replyComposerControllerProvider(args))
          .value!;
      expect(state.imageAttachments, isEmpty);
      expect(state.message, '正文');
      expect(await draftRepository.loadDraft(args.identity), isNull);
    });

    test(
      'pickImages marks failed upload and keeps failed aid out of message',
      () async {
        final imagePicker = _FakeReplyImagePicker(
          images: const [
            ReplyPickedImage(
              path: '/gallery/first.jpg',
              fileName: 'first.jpg',
              mimeType: 'image/jpeg',
              originalIndex: 0,
            ),
            ReplyPickedImage(
              path: '/gallery/second.jpg',
              fileName: 'second.jpg',
              mimeType: 'image/jpeg',
              originalIndex: 1,
            ),
          ],
        );
        final uploadCoordinator = _FakeReplyImageUploadCoordinator(
          events: [
            ComposerImageUploadEvent.failed(
              localId: '',
              current: 1,
              total: 2,
              errorMessage: '第一张失败',
            ),
            ComposerImageUploadEvent.uploaded(
              localId: '',
              current: 2,
              total: 2,
              uploadedImage: ReplyUploadedImage(
                localId: '',
                aid: '222',
                uploadedAt: DateTime.utc(2026, 6, 8),
              ),
            ),
            const ComposerImageUploadEvent.completed(total: 2),
          ],
        );
        final args = _threadArgs(tid: '572063');
        final container = _buildContainer(
          imagePicker: imagePicker,
          imageUploadCoordinator: uploadCoordinator,
        );
        addTearDown(container.dispose);
        final subscription = _keepComposerAlive(container, args);
        addTearDown(subscription.close);
        await container.read(replyComposerControllerProvider(args).future);

        final controller = container.read(
          replyComposerControllerProvider(args).notifier,
        );
        await controller.pickImages(
          insertionAnchor: const ComposerInsertionAnchor(
            baseRevision: 0,
            selection: ComposerSelection(start: 0, end: 0),
            mode: ComposerEditorMode.source,
          ),
        );
        await _drainMicrotasks();

        final state = container
            .read(replyComposerControllerProvider(args))
            .value!;
        expect(state.imageAttachments.map((attachment) => attachment.status), [
          ReplyImageAttachmentStatus.failed,
          ReplyImageAttachmentStatus.uploaded,
        ]);
        expect(state.message, '[attach]222[/attach]\n');
        expect(state.imageUploadError, '第一张失败');
      },
    );

    test('pickImages does not run while upload is active', () async {
      final uploadCompleter = Completer<void>();
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
      final uploadCoordinator = _FakeReplyImageUploadCoordinator(
        events: const [
          ComposerImageUploadEvent.started(localId: '', current: 1, total: 1),
        ],
        holdUntil: uploadCompleter.future,
      );
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer(
        imagePicker: imagePicker,
        imageUploadCoordinator: uploadCoordinator,
      );
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);
      await container.read(replyComposerControllerProvider(args).future);

      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );
      unawaited(controller.pickImages());
      await _drainMicrotasks();
      await controller.pickImages();
      uploadCompleter.complete();

      expect(imagePicker.pickCallCount, 1);
    });

    test('pickImages exposes picker error', () async {
      final imagePicker = _FakeReplyImagePicker(
        error: const ComposerImagePickerException('failed'),
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

    test(
      'duplicate submit while submitting does not call repository twice',
      () async {
        final completer = Completer<ApiResult<ReplySubmissionResult>>();
        final replyRepository = _FakeReplyRepository(
          asyncResult: completer.future,
        );
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
      },
    );

    test('submit sends BBCode source message unchanged', () async {
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
      final preparedState = container
          .read(replyComposerControllerProvider(args))
          .value;
      expect(replyRepository.prepareCallCount, 1);
      expect(
        preparedState?.preparation?.reference.noticeTrimStr,
        '[quote]引用[/quote]',
      );
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

    test(
      'post reply preparation failure disables submit and keeps draft',
      () async {
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
        expect(
          (await draftRepository.loadDraft(args.identity))?.message,
          '失败也保留',
        );
      },
    );

    // 漏转发任何一个字段都会让基类的通用流程静默失效。
    test('applyPatch forwards every ComposerStatePatch field', () async {
      final args = _threadArgs(tid: '572063');
      final container = _buildContainer();
      addTearDown(container.dispose);
      final subscription = _keepComposerAlive(container, args);
      addTearDown(subscription.close);

      final initial = await container.read(
        replyComposerControllerProvider(args).future,
      );
      final controller = container.read(
        replyComposerControllerProvider(args).notifier,
      );

      final mutation = ComposerTextMutation(
        previousSource: '旧',
        nextSource: '新',
        replacedSelection: const ComposerSelection(start: 0, end: 1),
        resultSelection: const ComposerSelection(start: 1, end: 1),
        revision: 9,
      );
      final applied = controller.applyPatch(
        initial,
        ComposerStatePatch(
          message: '新正文',
          useSignature: false,
          isSubmitting: true,
          restoredDraft: true,
          imageAttachments: [
            _attachmentWithStatus(
              localId: 'local-1',
              status: ComposerImageAttachmentStatus.local,
              aid: '',
            ),
          ],
          isUploadingImages: true,
          imageUploadCurrent: 2,
          imageUploadTotal: 3,
          messageRevision: 7,
          lastMessageMutation: mutation,
          pendingAttachmentAids: const ['888'],
          pendingAttachmentMessage: '待插入',
          errorMessage: '错误',
          imageUploadError: '上传错误',
        ),
      );

      expect(applied.message, '新正文');
      expect(applied.useSignature, isFalse);
      expect(applied.isSubmitting, isTrue);
      expect(applied.restoredDraft, isTrue);
      expect(applied.imageAttachments.single.localId, 'local-1');
      expect(applied.isUploadingImages, isTrue);
      expect(applied.imageUploadCurrent, 2);
      expect(applied.imageUploadTotal, 3);
      expect(applied.messageRevision, 7);
      expect(applied.lastMessageMutation, same(mutation));
      expect(applied.pendingAttachmentAids, ['888']);
      expect(applied.pendingAttachmentMessage, '待插入');
      expect(applied.errorMessage, '错误');
      expect(applied.imageUploadError, '上传错误');

      final cleared = controller.applyPatch(
        applied,
        const ComposerStatePatch(
          clearErrorMessage: true,
          clearImageUploadError: true,
          clearLastMessageMutation: true,
          clearPendingAttachmentMessage: true,
        ),
      );

      expect(cleared.errorMessage, isNull);
      expect(cleared.imageUploadError, isNull);
      expect(cleared.lastMessageMutation, isNull);
      expect(cleared.pendingAttachmentMessage, isNull);
    });
  });
}

ReplyImageAttachment _uploadedAttachment({
  required String localId,
  required String aid,
  required DateTime uploadedAt,
}) {
  return _attachmentWithStatus(
    localId: localId,
    aid: aid,
    status: ReplyImageAttachmentStatus.uploaded,
    uploadedAt: uploadedAt,
  );
}

ReplyImageAttachment _attachmentWithStatus({
  required String localId,
  required String aid,
  required ReplyImageAttachmentStatus status,
  DateTime? uploadedAt,
}) {
  return ReplyImageAttachment(
    localId: localId,
    localPath: '/gallery/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: status,
    aid: aid,
    uploadedAt: uploadedAt,
  );
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
  ComposerDraftRepository? draftRepository,
  ComposerPreferencesRepository? preferencesRepository,
  ReplyRepository? replyRepository,
  ComposerImagePicker? imagePicker,
  ComposerImageUploadCoordinator? imageUploadCoordinator,
}) {
  return ProviderContainer(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryReplyDraftRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        preferencesRepository ?? _MemoryComposerPreferencesRepository(),
      ),
      replyRepositoryProvider.overrideWithValue(
        replyRepository ?? _FakeReplyRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(
        imagePicker ?? _FakeReplyImagePicker(),
      ),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        imageUploadCoordinator ?? _FakeReplyImageUploadCoordinator(),
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

Future<void> _drainMicrotasks({int rounds = 4}) async {
  for (var index = 0; index < rounds; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _MemoryComposerPreferencesRepository
    implements ComposerPreferencesRepository {
  _MemoryComposerPreferencesRepository({ComposerPreferences? preferences})
    : preferences = preferences ?? ComposerPreferences.defaults();

  ComposerPreferences preferences;

  @override
  Future<ComposerPreferences> load() async => preferences;

  @override
  Future<void> save(ComposerPreferences preferences) async {
    this.preferences = preferences;
  }
}

class _MemoryReplyDraftRepository implements ComposerDraftRepository {
  final Map<String, ComposerDraftSnapshot> _drafts =
      <String, ComposerDraftSnapshot>{};
  bool throwOnPrune = false;
  int pruneCallCount = 0;

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    _drafts.remove(identity.storageKey);
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    return _drafts.values
        .where(
          (draft) => draft.identity.fid == fid && draft.identity.tid == tid,
        )
        .toList(growable: false);
  }

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    return _drafts[identity.storageKey];
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    pruneCallCount += 1;
    if (throwOnPrune) {
      throw StateError('prune failed');
    }
    return ComposerDraftPruneResult(removedCount: 0, keptCount: _drafts.length);
  }

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    if (draft.isEmpty) {
      _drafts.remove(draft.identity.storageKey);
      return;
    }
    _drafts[draft.identity.storageKey] = draft;
  }
}

class _FakeReplyImagePicker implements ComposerImagePicker {
  _FakeReplyImagePicker({
    this.images = const <ComposerPickedImage>[],
    this.error,
  });

  final List<ComposerPickedImage> images;
  final ComposerImagePickerException? error;
  int pickCallCount = 0;

  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async {
    pickCallCount += 1;
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return images;
  }
}

class _FakeReplyImageUploadCoordinator
    implements ComposerImageUploadCoordinator {
  _FakeReplyImageUploadCoordinator({
    this.events = const <ComposerImageUploadEvent>[],
    this.holdUntil,
  });

  final List<ComposerImageUploadEvent> events;
  final Future<void>? holdUntil;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) async* {
    for (var index = 0; index < events.length; index += 1) {
      if (cancelled) {
        return;
      }
      final event = events[index];
      if (event.type == ComposerImageUploadEventType.completed) {
        yield ComposerImageUploadEvent.completed(total: event.total);
        continue;
      }
      final localId = event.localId.isNotEmpty
          ? event.localId
          : attachments[(event.current - 1)
                    .clamp(0, attachments.length - 1)
                    .toInt()]
                .localId;
      yield _eventWithLocalId(event, localId);
    }
    final holdUntil = this.holdUntil;
    if (holdUntil != null) {
      await holdUntil;
    }
  }

  ComposerImageUploadEvent _eventWithLocalId(
    ComposerImageUploadEvent event,
    String localId,
  ) {
    return switch (event.type) {
      ComposerImageUploadEventType.started => ComposerImageUploadEvent.started(
        localId: localId,
        current: event.current,
        total: event.total,
      ),
      ComposerImageUploadEventType.progress =>
        ComposerImageUploadEvent.progress(
          localId: localId,
          current: event.current,
          total: event.total,
          progress: event.progress ?? 0,
        ),
      ComposerImageUploadEventType.uploaded =>
        ComposerImageUploadEvent.uploaded(
          localId: localId,
          current: event.current,
          total: event.total,
          uploadedImage: ComposerUploadedImage(
            localId: localId,
            aid: event.uploadedImage!.aid,
            uploadedAt: event.uploadedImage!.uploadedAt,
          ),
        ),
      ComposerImageUploadEventType.failed => ComposerImageUploadEvent.failed(
        localId: localId,
        current: event.current,
        total: event.total,
        errorMessage: event.errorMessage ?? '上传失败',
      ),
      ComposerImageUploadEventType.completed =>
        ComposerImageUploadEvent.completed(total: event.total),
    };
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
