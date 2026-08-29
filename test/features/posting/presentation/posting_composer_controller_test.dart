import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_insertion_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_failure_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_kind.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_state_patch.dart';
import 'package:y300/features/posting/data/providers/posting_providers.dart';
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
      final container = _buildContainer(metadataRepository: metadataRepository);
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
      expect(state.metadata?.fid, '33');
      expect(state.metadata?.threadTypes, hasLength(2));
      expect(metadataRepository.callCount, 1);
    });

    test('metadata failure exposes error and retry refetches', () async {
      final metadataRepository = _FakeMetadataRepository.failure(
        const DataReadFailure<
          ThreadCreationPreparation,
          ThreadCreationCapabilities
        >(
          kind: DataReadFailureKind.network,
          diagnosticMessage: 'test_network_failure',
        ),
      );
      final args = _args();
      final container = _buildContainer(metadataRepository: metadataRepository);
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);

      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final failed = container
          .read(postingComposerControllerProvider(args))
          .value!;
      expect(failed.isLoadingMetadata, isFalse);
      expect(
        failed.metadataFailure,
        isA<ComposerOperationFailure>()
            .having(
              (failure) => failure.code,
              'code',
              ComposerOperationFailureCode.postingMetadataLoad,
            )
            .having(
              (failure) => failure.detail,
              'detail',
              'test_network_failure',
            ),
      );
      expect(failed.metadata, isNull);

      metadataRepository.queueSuccess(_metadataWithTypes(typeRequired: false));
      await container
          .read(postingComposerControllerProvider(args).notifier)
          .retryLoadMetadata();
      final retried = container
          .read(postingComposerControllerProvider(args))
          .value!;
      expect(retried.isLoadingMetadata, isFalse);
      expect(retried.metadataFailure, isNull);
      expect(retried.metadata?.fid, '33');
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
      var state = container
          .read(postingComposerControllerProvider(args))
          .value!;
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
        final threadCreationCommand = _FakeThreadCreationCommand();
        final args = _args();
        final container = _buildContainer(
          metadataRepository: _FakeMetadataRepository.success(
            _metadataWithTypes(typeRequired: true),
          ),
          threadCreationCommand: threadCreationCommand,
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
        expect(threadCreationCommand.submissions, isEmpty);
        expect(
          container
              .read(postingComposerControllerProvider(args))
              .value
              ?.failure,
          isA<ComposerValidationFailure>().having(
            (failure) => failure.code,
            'code',
            ComposerValidationFailureCode.typeRequired,
          ),
        );
      },
    );

    test('successful submit deletes draft and clears state', () async {
      final draftRepository = _MemoryDraftRepository();
      final threadCreationCommand = _FakeThreadCreationCommand();
      final args = _args();
      final container = _buildContainer(
        draftRepository: draftRepository,
        metadataRepository: _FakeMetadataRepository.success(
          _metadataWithTypes(typeRequired: false),
        ),
        threadCreationCommand: threadCreationCommand,
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
      expect(threadCreationCommand.submissions, hasLength(1));
      expect(threadCreationCommand.submissions.single.subject, '标题');
      expect(threadCreationCommand.submissions.single.message, '正文');
      expect(threadCreationCommand.submissions.single.typeId, '111');

      final state = container
          .read(postingComposerControllerProvider(args))
          .value!;
      expect(state.subject, isEmpty);
      expect(state.message, isEmpty);
      expect(state.selectedTypeId, isNull);
      expect(state.allowNoticeAuthor, isFalse);
      expect(await draftRepository.loadDraft(args.identity), isNull);
    });

    test(
      'resetDraft clears posting fields while preserving signature and metadata',
      () async {
        final draftRepository = _MemoryDraftRepository();
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
        await container.read(postingComposerControllerProvider(args).future);
        await _drain();
        final controller = container.read(
          postingComposerControllerProvider(args).notifier,
        );

        controller.toggleUseSignature(false);
        controller.updateSubject('标题');
        controller.updateMessage('正文');
        controller.updateSelectedTypeId('111');
        controller.updateAllowNoticeAuthor(true);
        controller.updateBbCodeOff(true);
        controller.updateSmileyOff(true);
        controller.updateParseUrlOff(true);
        controller.updateTags(const <String>['百合']);
        controller.updateSpecial(NewThreadSpecial.poll);
        controller.updatePollOptions(const <String>['A', 'B']);
        await controller.flushDraft();

        expect(await draftRepository.loadDraft(args.identity), isNotNull);
        expect(
          container
              .read(postingComposerControllerProvider(args))
              .value
              ?.hasDraftContent,
          isTrue,
        );

        await controller.resetDraft();

        final state = container
            .read(postingComposerControllerProvider(args))
            .value!;
        expect(state.subject, isEmpty);
        expect(state.message, isEmpty);
        expect(state.selectedTypeId, isNull);
        expect(state.allowNoticeAuthor, isFalse);
        expect(state.bbCodeOff, isFalse);
        expect(state.smileyOff, isFalse);
        expect(state.parseUrlOff, isFalse);
        expect(state.tags, isEmpty);
        expect(state.special, NewThreadSpecial.normal);
        expect(state.poll, isNull);
        expect(state.useSignature, isFalse);
        expect(state.metadata, isNotNull);
        expect(state.hasDraftContent, isFalse);
        expect(await draftRepository.loadDraft(args.identity), isNull);
      },
    );

    test('failed submit keeps draft with subject and extras', () async {
      final draftRepository = _MemoryDraftRepository();
      final threadCreationCommand = _FakeThreadCreationCommand(
        result: const DataCommandRejected<ThreadCreationReceipt>(
          DataCommandFailure(
            kind: DataCommandFailureKind.validation,
            retryPolicy: DataCommandRetryPolicy.explicitOnly,
            code: 'post_flood_ctrl',
            diagnosticMessage: 'test_rate_limited',
          ),
        ),
      );
      final args = _args();
      final container = _buildContainer(
        draftRepository: draftRepository,
        metadataRepository: _FakeMetadataRepository.success(
          _metadataWithTypes(typeRequired: false),
        ),
        threadCreationCommand: threadCreationCommand,
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
        container.read(postingComposerControllerProvider(args)).value?.failure,
        isA<ComposerSubmissionFailure>()
            .having(
              (failure) => failure.code,
              'code',
              ComposerSubmissionFailureCode.rateLimited,
            )
            .having((failure) => failure.kind, 'kind', ComposerKind.newThread),
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
        final threadCreationCommand = _FakeThreadCreationCommand();
        final args = _args();
        final container = _buildContainer(
          metadataRepository: _FakeMetadataRepository.success(
            _metadataWithTypes(typeRequired: false),
          ),
          threadCreationCommand: threadCreationCommand,
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
        await _drain();

        final state = container
            .read(postingComposerControllerProvider(args))
            .value!;
        expect(state.message, '正文\n[attach]777[/attach]\n');
        expect(state.imageAttachments.single.aid, '777');

        final result = await controller.submit();
        expect(result.sent, isTrue);
        expect(threadCreationCommand.submissions.single.attachmentIds, ['777']);
      },
    );

    test(
      'legacy reply draft restored as reply does not bleed into new thread',
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
      },
    );

    test(
      'canSubmit blocks when subject or message exceeds metadata limits',
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

        var state = container
            .read(postingComposerControllerProvider(args))
            .value!;
        expect(state.canSubmit, isTrue);

        controller.updateSubject('这个标题太长会被拒绝');
        state = container.read(postingComposerControllerProvider(args)).value!;
        expect(state.canSubmit, isFalse, reason: '标题超出 maxSubjectLength=5');

        controller.updateSubject('短标题');
        controller.updateMessage('这条正文超过版块的字数限制了哈哈');
        state = container.read(postingComposerControllerProvider(args)).value!;
        expect(state.canSubmit, isFalse, reason: '正文超出 maxMessageLength=10');
      },
    );

    test(
      'preflight returns over-limit message when subject exceeds threshold',
      () async {
        final threadCreationCommand = _FakeThreadCreationCommand();
        final args = _args();
        final container = _buildContainer(
          metadataRepository: _FakeMetadataRepository.success(
            _metadataWithLengthLimits(maxSubjectLength: 5),
          ),
          threadCreationCommand: threadCreationCommand,
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
        expect(threadCreationCommand.submissions, isEmpty);
        expect(
          container
              .read(postingComposerControllerProvider(args))
              .value
              ?.failure,
          isA<ComposerValidationFailure>()
              .having(
                (failure) => failure.code,
                'code',
                ComposerValidationFailureCode.subjectTooLong,
              )
              .having((failure) => failure.limit, 'limit', 5),
        );
      },
    );

    // ── tags / special / poll ────────────────────────────────
    test('updateTags writes normalized tags into state and draft', () async {
      final draftRepository = _MemoryDraftRepository();
      final args = _args();
      final container = _buildContainer(
        draftRepository: draftRepository,
        metadataRepository: _FakeMetadataRepository.success(_metadataNoTypes()),
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final controller = container.read(
        postingComposerControllerProvider(args).notifier,
      );
      // 草稿落盘时 ComposerDraftSnapshot.isEmpty 同时看 subject/message/附件，
      // 全空时 memory repo 会把草稿删了。这里给一条最低限的标题 + 正文，让
      // 测试焦点回到"tags 能否被持久化"。
      controller.updateSubject('标题');
      controller.updateMessage('正文');
      controller.updateTags(['  百合 ', '百合', '动画', '']);
      await controller.flushDraft();

      final state = container
          .read(postingComposerControllerProvider(args))
          .value!;
      expect(state.tags, ['百合', '动画']);

      final stored = await draftRepository.loadDraft(args.identity);
      expect(stored?.extras['tags'], '百合,动画');
    });

    test('updateSpecial to poll seeds an empty draft and persists', () async {
      final draftRepository = _MemoryDraftRepository();
      final args = _args();
      final container = _buildContainer(
        draftRepository: draftRepository,
        metadataRepository: _FakeMetadataRepository.success(_metadataNoTypes()),
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final controller = container.read(
        postingComposerControllerProvider(args).notifier,
      );
      // 必须先有 subject / message，否则 isEmpty 草稿不会落盘。
      controller.updateSubject('投票');
      controller.updateMessage('说明');
      controller.updateSpecial(NewThreadSpecial.poll);
      await controller.flushDraft();

      final state = container
          .read(postingComposerControllerProvider(args))
          .value!;
      expect(state.special, NewThreadSpecial.poll);
      expect(state.poll, isNotNull);

      final stored = await draftRepository.loadDraft(args.identity);
      expect(stored?.extras['special'], 'poll');
    });

    test(
      'poll preflight blocks submit when fewer than 2 valid options',
      () async {
        final threadCreationCommand = _FakeThreadCreationCommand();
        final args = _args();
        final container = _buildContainer(
          metadataRepository: _FakeMetadataRepository.success(
            _metadataNoTypes(),
          ),
          threadCreationCommand: threadCreationCommand,
        );
        addTearDown(container.dispose);
        final subscription = _keepAlive(container, args);
        addTearDown(subscription.close);
        await container.read(postingComposerControllerProvider(args).future);
        await _drain();

        final controller = container.read(
          postingComposerControllerProvider(args).notifier,
        );
        controller.updateSubject('投票');
        controller.updateMessage('说明');
        controller.updateSpecial(NewThreadSpecial.poll);
        controller.updatePollOptions(['只有一个']);

        final result = await controller.submit();
        expect(result.sent, isFalse);
        expect(threadCreationCommand.submissions, isEmpty);
        expect(
          result.failure,
          isA<ComposerValidationFailure>().having(
            (failure) => failure.code,
            'code',
            ComposerValidationFailureCode.pollTooFewOptions,
          ),
        );
      },
    );

    test('poll submit forwards normalized payload', () async {
      final threadCreationCommand = _FakeThreadCreationCommand();
      final args = _args();
      final container = _buildContainer(
        metadataRepository: _FakeMetadataRepository.success(_metadataNoTypes()),
        threadCreationCommand: threadCreationCommand,
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);
      await container.read(postingComposerControllerProvider(args).future);
      await _drain();

      final controller = container.read(
        postingComposerControllerProvider(args).notifier,
      );
      controller.updateSubject('投票标题');
      controller.updateMessage('正文');
      controller.updateSpecial(NewThreadSpecial.poll);
      controller.updatePollOptions(['  A ', '', 'B', 'C']);
      controller.updatePollMultiple(true);
      controller.updatePollMaxChoices(2);
      controller.updatePollExpirationDays(7);
      controller.updatePollOvert(true);

      final result = await controller.submit();
      expect(result.sent, isTrue);

      final payload = threadCreationCommand.submissions.single;
      expect(payload.kind, ThreadCreationKind.poll);
      expect(payload.poll, isNotNull);
      expect(payload.poll!.options, ['A', 'B', 'C']);
      expect(payload.poll!.maximumChoices, 2);
      expect(payload.poll!.expirationDays, 7);
      expect(payload.poll!.publicVoters, isTrue);

      // 成功后业务字段被 reset。
      final state = container
          .read(postingComposerControllerProvider(args))
          .value!;
      expect(state.special, NewThreadSpecial.normal);
      expect(state.poll, isNull);
      expect(state.tags, isEmpty);
    });

    test('restored poll draft re-enters poll mode after relaunch', () async {
      final draftRepository = _MemoryDraftRepository();
      // 模拟"杀进程后重启"：先在仓库里塞一份草稿。
      await draftRepository.saveDraft(
        ComposerDraftSnapshot(
          identity: ComposerDraftIdentity.newThread(fid: '33'),
          message: '说明',
          subject: '投票',
          useSignature: true,
          updatedAt: DateTime.now(),
          extras: const <String, String>{
            'special': 'poll',
            'pollOptions': 'A\nB',
            'pollMultiple': '1',
            'pollMaxChoices': '2',
            'tags': '百合,动画',
          },
        ),
      );

      final args = _args();
      final container = _buildContainer(
        draftRepository: draftRepository,
        metadataRepository: _FakeMetadataRepository.success(_metadataNoTypes()),
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);

      final state = await container.read(
        postingComposerControllerProvider(args).future,
      );
      expect(state.subject, '投票');
      expect(state.message, '说明');
      expect(state.tags, ['百合', '动画']);
      expect(state.special, NewThreadSpecial.poll);
      expect(state.poll, isNotNull);
      expect(state.poll!.options, ['A', 'B']);
      expect(state.poll!.multiple, isTrue);
      expect(state.poll!.maxChoices, 2);
    });

    // 漏转发任何一个字段都会让基类的通用流程静默失效。
    test('applyPatch forwards every ComposerStatePatch field', () async {
      final args = _args();
      final container = _buildContainer(
        metadataRepository: _FakeMetadataRepository.success(_metadataNoTypes()),
      );
      addTearDown(container.dispose);
      final subscription = _keepAlive(container, args);
      addTearDown(subscription.close);

      final initial = await container.read(
        postingComposerControllerProvider(args).future,
      );
      final controller = container.read(
        postingComposerControllerProvider(args).notifier,
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
          imageAttachments: const [
            ComposerImageAttachment(
              localId: 'local-1',
              localPath: '/tmp/a.png',
              fileName: 'a.png',
              mimeType: 'image/png',
              order: 0,
              status: ComposerImageAttachmentStatus.local,
            ),
          ],
          isUploadingImages: true,
          imageUploadCurrent: 2,
          imageUploadTotal: 3,
          messageRevision: 7,
          lastMessageMutation: mutation,
          pendingAttachmentAids: const ['888'],
          pendingAttachmentNotice: ComposerPendingAttachmentNotice(
            code: ComposerPendingAttachmentNoticeCode.readyToReinsert,
            count: 1,
          ),
          failure: ComposerSubmissionFailure(
            code: ComposerSubmissionFailureCode.unknown,
            kind: ComposerKind.newThread,
            detail: '错误',
          ),
          imageUploadFailure: ComposerImageUploadFailure(
            code: ComposerImageUploadFailureCode.unknown,
            detail: '上传错误',
          ),
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
      expect(
        applied.pendingAttachmentNotice?.code,
        ComposerPendingAttachmentNoticeCode.readyToReinsert,
      );
      expect(applied.failure?.detail, '错误');
      expect(applied.imageUploadFailure?.detail, '上传错误');

      final cleared = controller.applyPatch(
        applied,
        const ComposerStatePatch(
          clearFailure: true,
          clearImageUploadFailure: true,
          clearLastMessageMutation: true,
          clearPendingAttachmentNotice: true,
        ),
      );

      expect(cleared.failure, isNull);
      expect(cleared.imageUploadFailure, isNull);
      expect(cleared.lastMessageMutation, isNull);
      expect(cleared.pendingAttachmentNotice, isNull);
    });
  });
}
