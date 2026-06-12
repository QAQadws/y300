import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/composer_shared/data/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/composer_providers.dart';
import 'package:y300/features/composer_shared/data/composer_upload_notification_service.dart';
import 'package:y300/features/composer_shared/data/sticker_picker_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/posting/data/new_thread_repository.dart';
import 'package:y300/features/posting/data/posting_form_metadata_repository.dart';
import 'package:y300/features/posting/data/posting_providers.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/posting/domain/models/posting_target.dart';
import 'package:y300/features/posting/presentation/posting_composer_page.dart';
import 'package:y300/features/posting/presentation/posting_composer_state.dart';

part 'posting_composer_page_test_fakes.dart';

void main() {
  // PLACEHOLDER_PHASE_5_PAGE_TESTS
  testWidgets('PostingComposerPage shows metadata loading banner first frame',
      (tester) async {
    final completer = Completer<void>();
    final metadataRepository = _FakeMetadataRepository.heldSuccess(
      _metadata(),
      completer.future,
    );

    await tester.pumpWidget(
      _buildPage(metadataRepository: metadataRepository),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('posting-composer-metadata-loading')),
      findsOneWidget,
    );
    expect(find.text('正在加载发帖表单'), findsOneWidget);
    // 加载中时 AppBar 标题回退到"发帖"。
    expect(find.text('发帖'), findsOneWidget);

    // 解开 metadata 拉取，避免悬挂 future。
    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'PostingComposerPage shows AppBar with forum name after metadata load',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            _metadata(forumName: '日常版'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('发帖 — 日常版'), findsOneWidget);
      expect(
        find.byKey(const Key('posting-composer-metadata-loading')),
        findsNothing,
      );
    },
  );

  testWidgets('PostingComposerPage shows metadata error and retries', (
    tester,
  ) async {
    final metadataRepository = _FakeMetadataRepository.failure(
      const ApiError(type: ApiErrorType.network, message: '网络挂了'),
    );

    await tester.pumpWidget(
      _buildPage(metadataRepository: metadataRepository),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-metadata-error')),
      findsOneWidget,
    );
    expect(find.textContaining('网络挂了'), findsOneWidget);

    metadataRepository.queueSuccess(_metadata());
    await tester
        .tap(find.byKey(const Key('posting-composer-metadata-retry-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('posting-composer-metadata-error')),
      findsNothing,
    );
    expect(find.text('发帖 — 日常版'), findsOneWidget);
    expect(metadataRepository.callCount, 2);
  });

  testWidgets(
    'PostingComposerPage send button is disabled when required type is unselected',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            _metadata(typeRequired: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 输入标题 + 正文，但没选分类。
      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '我的标题',
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-message-input')),
        '正文',
      );
      await tester.pump();

      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('posting-composer-send-button')),
      );
      expect(sendButton.onPressed, isNull);

      // 选了分类之后按钮启用。
      await tester.tap(find.byKey(const Key('posting-composer-type-111')));
      await tester.pump();
      final enabledSend = tester.widget<IconButton>(
        find.byKey(const Key('posting-composer-send-button')),
      );
      expect(enabledSend.onPressed, isNotNull);
    },
  );

  testWidgets(
    'PostingComposerPage hides type selector when forum has no thread types',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            _metadata(types: const []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('posting-composer-type-selector')),
        findsNothing,
      );
      // 标题 + 正文非空时，"无分类"逻辑等价 typeid='0'，可以提交。
      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '标题',
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-message-input')),
        '正文',
      );
      await tester.pump();
      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('posting-composer-send-button')),
      );
      expect(sendButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'PostingComposerPage type selector hides "无分类" when type is required',
    (tester) async {
      await tester.pumpWidget(
        _buildPage(
          metadataRepository: _FakeMetadataRepository.success(
            _metadata(typeRequired: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('posting-composer-type-none')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('posting-composer-type-111')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('posting-composer-type-222')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PostingComposerPage uploads picked image and renders attachment queue',
    (tester) async {
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
            // 真实环境下 localId 由 controller 在 pickImages 时生成；fake 里
            // 留空、由 controller 把它替换成 attachments[i].localId 也可，
            // 但 PostingComposerController 的 fake 实现把事件原样转发，所以
            // 这里用 null 兜底——image queue 渲染只看 attachment 自身的 status。
            localId: 'picked-0',
            current: 1,
            total: 1,
            uploadedImage: ComposerUploadedImage(
              localId: 'picked-0',
              aid: '777',
              uploadedAt: DateTime.now(),
            ),
          ),
          const ComposerImageUploadEvent.completed(total: 1),
        ],
      );
      await tester.pumpWidget(
        _buildPage(
          imagePicker: imagePicker,
          imageUploadCoordinator: uploadCoordinator,
          metadataRepository: _FakeMetadataRepository.success(_metadata()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('posting-composer-image-queue')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('posting-composer-image-button')));
      await tester.pumpAndSettle();

      expect(imagePicker.pickCallCount, 1);
      expect(
        find.byKey(const Key('posting-composer-image-queue')),
        findsOneWidget,
      );
      expect(find.text('first.jpg'), findsOneWidget);
    },
  );

  testWidgets('PostingComposerPage submits and pops sent result', (
    tester,
  ) async {
    final newThreadRepository = _FakeNewThreadRepository();
    PostingComposerResult? popped;
    await tester.pumpWidget(
      _buildLauncher(
        newThreadRepository: newThreadRepository,
        metadataRepository: _FakeMetadataRepository.success(_metadata()),
        onResult: (r) => popped = r,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-posting-composer-page')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('posting-composer-subject-input')),
      '标题',
    );
    await tester.enterText(
      find.byKey(const Key('posting-composer-message-input')),
      '正文',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('posting-composer-send-button')));
    await tester.pumpAndSettle();

    expect(newThreadRepository.submittedPayloads, hasLength(1));
    expect(newThreadRepository.submittedPayloads.single.subject, '标题');
    expect(newThreadRepository.submittedPayloads.single.message, '正文');
    expect(popped?.sent, isTrue);
    expect(popped?.tid, '900001');
    expect(popped?.pid, '910001');
  });

  testWidgets(
    'PostingComposerPage confirms leaving with unsent input and saves draft',
    (tester) async {
      final draftRepository = _MemoryDraftRepository();
      await tester.pumpWidget(
        _buildLauncher(
          draftRepository: draftRepository,
          metadataRepository: _FakeMetadataRepository.success(_metadata()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-posting-composer-page')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '草稿标题',
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-message-input')),
        '草稿正文',
      );
      await tester.pump();

      // 触发系统返回——通过 AppBar 上的 back button。
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('保存草稿并离开？'), findsOneWidget);
      await tester
          .tap(find.byKey(const Key('posting-composer-save-leave-button')));
      await tester.pumpAndSettle();

      const identity = ComposerDraftIdentity.newThread(fid: '33');
      final saved = await draftRepository.loadDraft(identity);
      expect(saved?.subject, '草稿标题');
      expect(saved?.message, '草稿正文');
    },
  );

}
