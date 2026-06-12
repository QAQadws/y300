import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/composer_shared/data/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/composer_providers.dart';
import 'package:y300/features/composer_shared/data/composer_upload_notification_service.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_controller_base.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_editor_mode.dart';
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
      final controller = container
          .read(_testControllerProvider(args).notifier);

      controller.updateMessage('正文');
      // 防抖中尚未落盘
      expect(await draftRepository.loadDraft(args.identity), isNull);

      await controller.flushDraft();

      expect((await draftRepository.loadDraft(args.identity))?.message, '正文');
    });

    test('switchMode switches editor mode without touching draft', () async {
      final draftRepository = _MemoryDraftRepository();
      final args = _TestArgs(fid: '33', tid: '572063');
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container
          .read(_testControllerProvider(args).notifier);

      controller.switchMode(ComposerEditorMode.preview);

      expect(
        container.read(_testControllerProvider(args)).value?.mode,
        ComposerEditorMode.preview,
      );
      // 切换模式不应触发草稿保存
      expect(await draftRepository.loadDraft(args.identity), isNull);
    });

    test('image upload event flow appends attach code and saves draft', () async {
      final draftRepository = _MemoryDraftRepository();
      final imagePicker = _FakeImagePicker(images: const [
        ComposerPickedImage(
          path: '/gallery/first.jpg',
          fileName: 'first.jpg',
          mimeType: 'image/jpeg',
          originalIndex: 0,
        ),
      ]);
      final coordinator = _FakeUploadCoordinator(events: [
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
      ]);
      final args = _TestArgs(fid: '33', tid: '572063');
      final container = _buildContainer(
        draftRepository: draftRepository,
        imagePicker: imagePicker,
        imageUploadCoordinator: coordinator,
      );
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container
          .read(_testControllerProvider(args).notifier);

      await controller.pickImages();
      await _drain();
      await controller.flushDraft();

      final state = container.read(_testControllerProvider(args)).value!;
      expect(state.message, '[attach]789[/attach]');
      expect(state.imageAttachments.single.aid, '789');
      expect(state.imageAttachments.single.status,
          ComposerImageAttachmentStatus.uploaded);
      final saved = await draftRepository.loadDraft(args.identity);
      expect(saved?.imageAttachments.single.aid, '789');
    });

    test('preflight failure short-circuits submit and does not call performSubmit',
        () async {
      final args = _TestArgs(fid: '33', tid: '572063');
      final container = _buildContainer();
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container
          .read(_testControllerProvider(args).notifier);

      // 默认 preflight：message 为空 → 返回 '请输入内容'
      final result = await controller.submit();

      expect(result.sent, isFalse);
      expect(controller.performSubmitCallCount, 0);
      expect(
        container.read(_testControllerProvider(args)).value?.errorMessage,
        '请输入内容',
      );
    });

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
      final controller = container
          .read(_testControllerProvider(args).notifier);

      controller.updateMessage('提交内容');
      controller.outcome =
          const ComposerSubmissionOutcome.success(message: '完成');
      final result = await controller.submit();

      expect(result.sent, isTrue);
      expect(result.message, '完成');
      expect(controller.performSubmitCallCount, 1);
      final state = container.read(_testControllerProvider(args)).value!;
      expect(state.message, isEmpty);
      expect(state.imageAttachments, isEmpty);
      expect(await draftRepository.loadDraft(args.identity), isNull);
    });

    test('failed submit preserves draft and writes errorMessage', () async {
      final draftRepository = _MemoryDraftRepository();
      final args = _TestArgs(fid: '33', tid: '572063');
      final container = _buildContainer(draftRepository: draftRepository);
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container
          .read(_testControllerProvider(args).notifier);

      controller.updateMessage('失败也要保留');
      controller.outcome =
          const ComposerSubmissionOutcome.failure(errorMessage: '网络异常');
      final result = await controller.submit();

      expect(result.sent, isFalse);
      expect(result.message, '网络异常');
      expect(
        container.read(_testControllerProvider(args)).value?.errorMessage,
        '网络异常',
      );
      final saved = await draftRepository.loadDraft(args.identity);
      expect(saved?.message, '失败也要保留');
    });

    test('duplicate submit while submitting does not call performSubmit twice',
        () async {
      final args = _TestArgs(fid: '33', tid: '572063');
      final container = _buildContainer();
      addTearDown(container.dispose);
      _keepAlive(container, args);
      await container.read(_testControllerProvider(args).future);
      final controller = container
          .read(_testControllerProvider(args).notifier);
      final completer = Completer<ComposerSubmissionOutcome>();
      controller.outcomeFuture = completer.future;
      controller.updateMessage('提交内容');

      final first = controller.submit();
      final second = await controller.submit();
      completer
          .complete(const ComposerSubmissionOutcome.success(message: 'ok'));
      await first;

      expect(controller.performSubmitCallCount, 1);
      expect(second.sent, isFalse);
    });
  });
}

/// 占位：本测试目前只覆盖事件循环驱动的简单流程，不需要伪造 fakeAsync。
