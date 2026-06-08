import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/reply/data/reply_draft_repository.dart';
import 'package:y300/features/reply/data/reply_image_picker.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/data/reply_upload_notification_service.dart';
import 'package:y300/features/reply/data/sticker_picker_preferences_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/domain/services/reply_draft_attachment_sanitizer.dart';
import 'package:y300/features/reply/domain/services/reply_image_upload_coordinator.dart';
import 'package:y300/features/reply/presentation/bbcode/forum_bbcode_renderer.dart';
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
    expect(
      find.byKey(const Key('reply-composer-sticker-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-message-input')), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-use-signature-switch')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-image-button')), findsOneWidget);
    expect(find.byKey(const Key('reply-composer-send-button')), findsOneWidget);
  });

  testWidgets('ReplyComposerPage places image action before send action', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    final imageCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-image-button')),
    );
    final sendCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-send-button')),
    );

    expect(imageCenter.dx, lessThan(sendCenter.dx));
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
    expect(find.text('已恢复未发送草稿'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('reply-composer-use-signature-switch')),
    );
    expect(switchTile.value, isFalse);
  });

  testWidgets('ReplyComposerPage restores uploaded image attachment queue', (
    tester,
  ) async {
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository();
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

    await tester.pumpWidget(
      _buildPage(args: args, draftRepository: draftRepository),
    );
    await tester.pump();

    expect(find.byKey(const Key('reply-composer-image-queue')), findsOneWidget);
    expect(find.text('image-1.jpg'), findsOneWidget);
    expect(find.textContaining('已上传'), findsOneWidget);
  });

  testWidgets('ReplyComposerPage previews restored uploaded local image', (
    tester,
  ) async {
    const path = 'E:/test/reply/restored.png';
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository();
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
            localPath: path,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _buildPage(args: args, draftRepository: draftRepository),
    );
    await tester.pump();
    await tester.tap(find.text('预览'));
    await tester.pump();

    final previewImage = tester.widget<_TestAttachPreviewImage>(
      find.byKey(const Key('reply-bbcode-preview-attach-123456')),
    );
    expect(previewImage.file.path, path);
    expect(find.textContaining('[attach]123456[/attach]', findRichText: true),
        findsNothing);
  });

  testWidgets('ReplyComposerPage omits expired restored image attachment', (
    tester,
  ) async {
    final args = _threadArgs();
    final draftRepository = _MemoryReplyDraftRepository(
      now: () => DateTime.utc(2026, 6, 8, 12),
    );
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
            uploadedAt: DateTime.utc(2026, 6, 7, 12),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _buildPage(args: args, draftRepository: draftRepository),
    );
    await tester.pump();

    expect(find.byKey(const Key('reply-composer-image-queue')), findsNothing);
    expect(find.textContaining('[attach]123456[/attach]'), findsNothing);
    expect(find.text('正文'), findsOneWidget);
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
      _buildLauncher(
        replyRepository: replyRepository,
        onResult: (result) {
          poppedResult = result;
        },
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
      _buildLauncher(replyRepository: replyRepository),
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

  testWidgets('ReplyComposerPage inserts sticker code at cursor position', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage(stickerGroups: _stickerGroups));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '前后',
    );
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.selection = const TextSelection.collapsed(offset: 1);

    await tester.tap(find.byKey(const Key('reply-composer-sticker-button')));
    await tester.pumpAndSettle();
    expect(find.text('貓貓蟲'), findsOneWidget);
    expect(find.text('{:9_656:}'), findsNothing);
    await tester.tap(find.byKey(const Key('reply-sticker-item-{:9_656:}')));
    await tester.pumpAndSettle();

    expect(find.text('前{:9_656:}后'), findsOneWidget);
  });

  testWidgets('ReplyComposerPage previews inserted sticker as asset image', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage(stickerGroups: _stickerGroups));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '{:9_656:}',
    );
    await tester.pump();
    await tester.tap(find.text('预览'));
    await tester.pump();

    expect(
      find.byKey(const Key('reply-bbcode-preview-sticker-{:9_656:}')),
      findsOneWidget,
    );
    expect(find.textContaining('{:9_656:}', findRichText: true), findsNothing);
  });

  testWidgets('ReplyComposerPage submits raw sticker code', (tester) async {
    final replyRepository = _FakeReplyRepository(
      result: const ApiSuccess<ReplySubmissionResult>(
        ReplySubmissionResult(message: '回复发布成功'),
      ),
    );

    await tester.pumpWidget(
      _buildLauncher(
        replyRepository: replyRepository,
        stickerGroups: _stickerGroups,
      ),
    );

    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '表情{:9_656:}',
    );
    await tester.pump();
    await tester.tap(find.text('预览'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(replyRepository.sentDrafts.single.message, '表情{:9_656:}');
  });

  testWidgets('ReplyComposerPage shows post reply preparation banner', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage(args: _postArgs()));
    await tester.pump();
    await tester.pump();

    expect(find.text('回复楼层'), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-reference-banner')),
      findsOneWidget,
    );
    expect(find.textContaining('引用正文'), findsOneWidget);
  });

  testWidgets('ReplyComposerPage shows post preparation failure and retry', (
    tester,
  ) async {
    final replyRepository = _FakeReplyRepository(
      preparationResult: const ApiFailure<ReplyPreparation>(
        ApiError(type: ApiErrorType.parse, message: '表单解析失败'),
      ),
    );

    await tester.pumpWidget(
      _buildPage(args: _postArgs(), replyRepository: replyRepository),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('reply-composer-preparation-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reply-composer-retry-prepare-button')),
      findsOneWidget,
    );
    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('reply-composer-send-button')),
    );
    expect(sendButton.onPressed, isNull);
  });

  testWidgets('ReplyComposerPage disables image button while preparing post', (
    tester,
  ) async {
    final preparationCompleter = Completer<ApiResult<ReplyPreparation>>();
    await tester.pumpWidget(
      _buildPage(
        args: _postArgs(),
        replyRepository: _FakeReplyRepository(
          asyncPreparationResult: preparationCompleter.future,
        ),
      ),
    );
    await tester.pump();

    final imageButton = tester.widget<IconButton>(
      find.byKey(const Key('reply-composer-image-button')),
    );
    expect(imageButton.onPressed, isNull);
    preparationCompleter.complete(
      const ApiSuccess<ReplyPreparation>(
        ReplyPreparation(
          target: ReplyTarget.post(
            fid: '33',
            tid: '572063',
            pid: '41554317',
          ),
          reference: ReplyReference(),
        ),
      ),
    );
  });

  testWidgets('ReplyComposerPage shows picked image queue', (tester) async {
    await tester.pumpWidget(
      _buildPage(
        imagePicker: _FakeReplyImagePicker(
          images: const [
            ReplyPickedImage(
              path: '/gallery/first.jpg',
              fileName: 'first.jpg',
              mimeType: 'image/jpeg',
              originalIndex: 0,
            ),
          ],
        ),
        imageUploadCoordinator: _FakeReplyImageUploadCoordinator(
          events: [
            ReplyImageUploadEvent.started(
              localId: '',
              current: 1,
              total: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reply-composer-image-button')));
    await tester.pump();

    expect(find.byKey(const Key('reply-composer-image-queue')), findsOneWidget);
    expect(find.text('first.jpg'), findsOneWidget);
    expect(find.textContaining('image/jpeg'), findsOneWidget);
    expect(find.textContaining('上传中'), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-image-upload-progress')),
      findsOneWidget,
    );
    expect(find.text('第 1/1 张'), findsOneWidget);
  });

  testWidgets('ReplyComposerPage uploads image and appends attach code', (
    tester,
  ) async {
    final replyRepository = _FakeReplyRepository();
    await tester.pumpWidget(
      _buildPage(
        replyRepository: replyRepository,
        imagePicker: _FakeReplyImagePicker(
          images: const [
            ReplyPickedImage(
              path: '/gallery/first.jpg',
              fileName: 'first.jpg',
              mimeType: 'image/jpeg',
              originalIndex: 0,
            ),
          ],
        ),
        imageUploadCoordinator: _FakeReplyImageUploadCoordinator(
          events: [
            ReplyImageUploadEvent.uploaded(
              localId: '',
              current: 1,
              total: 1,
              uploadedImage: ReplyUploadedImage(
                localId: '',
                aid: '123456',
                uploadedAt: DateTime.utc(2026, 6, 8),
              ),
            ),
            const ReplyImageUploadEvent.completed(total: 1),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '正文',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reply-composer-image-button')));
    await tester.pump();
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, '正文\n[attach]123456[/attach]');
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(
      replyRepository.sentDrafts.single.message,
      '正文\n[attach]123456[/attach]',
    );
  });

  testWidgets(
    'ReplyComposerPage previews uploaded image and submits raw attach code',
    (tester) async {
      const path = 'E:/test/reply/uploaded.png';
      final replyRepository = _FakeReplyRepository();
      await tester.pumpWidget(
        _buildPage(
          replyRepository: replyRepository,
          imagePicker: _FakeReplyImagePicker(
            images: [
              ReplyPickedImage(
                path: path,
                fileName: 'uploaded.png',
                mimeType: 'image/png',
                originalIndex: 0,
              ),
            ],
          ),
          imageUploadCoordinator: _FakeReplyImageUploadCoordinator(
            events: [
              ReplyImageUploadEvent.uploaded(
                localId: '',
                current: 1,
                total: 1,
                uploadedImage: ReplyUploadedImage(
                  localId: '',
                  aid: '123456',
                  uploadedAt: DateTime.utc(2026, 6, 8),
                ),
              ),
              const ReplyImageUploadEvent.completed(total: 1),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('reply-composer-message-input')),
        '正文',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('reply-composer-image-button')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('预览'));
      await tester.pump();

      expect(
        find.byKey(const Key('reply-bbcode-preview-attach-123456')),
        findsOneWidget,
      );
      expect(find.textContaining('[attach]123456[/attach]', findRichText: true),
          findsNothing);

      await tester.tap(find.text('源码'));
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.controller.text, '正文\n[attach]123456[/attach]');
      await tester.tap(find.text('预览'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reply-composer-send-button')));
      await tester.pumpAndSettle();

      expect(
        replyRepository.sentDrafts.single.message,
        '正文\n[attach]123456[/attach]',
      );
    },
  );

  testWidgets('ReplyComposerPage shows upload failure without changing message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildPage(
        imagePicker: _FakeReplyImagePicker(
          images: const [
            ReplyPickedImage(
              path: '/gallery/first.jpg',
              fileName: 'first.jpg',
              mimeType: 'image/jpeg',
              originalIndex: 0,
            ),
          ],
        ),
        imageUploadCoordinator: _FakeReplyImageUploadCoordinator(
          events: [
            ReplyImageUploadEvent.failed(
              localId: '',
              current: 1,
              total: 1,
              errorMessage: '图片上传失败',
            ),
            const ReplyImageUploadEvent.completed(total: 1),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '正文',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reply-composer-image-button')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('上传失败'), findsWidgets);
    expect(find.text('正文'), findsOneWidget);
    expect(find.textContaining('[attach]'), findsNothing);
  });

  testWidgets('ReplyComposerPage submits post reply with reference fields', (
    tester,
  ) async {
    final replyRepository = _FakeReplyRepository();
    await tester.pumpWidget(
      _buildPage(args: _postArgs(), replyRepository: replyRepository),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '楼层回复',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    final draft = replyRepository.sentDrafts.single;
    expect(draft.formHash, 'prepared-formhash');
    expect(draft.noticeTrimStr, '[quote]引用[/quote]');
    expect(draft.repPost, '41554317');
  });

  testWidgets('ReplyComposerPage confirms leaving with unsent input', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildLauncher(draftRepository: _MemoryReplyDraftRepository()),
    );
    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '未发送内容',
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('保存草稿并离开？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reply-composer-continue-edit-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reply-composer-message-input')), findsOneWidget);
  });

  testWidgets('ReplyComposerPage saves draft and leaves after confirmation', (
    tester,
  ) async {
    final draftRepository = _MemoryReplyDraftRepository();
    await tester.pumpWidget(_buildLauncher(draftRepository: draftRepository));
    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '离开前保存',
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reply-composer-save-leave-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-reply-composer-page')), findsOneWidget);
    expect((await draftRepository.loadDraft(_threadArgs().identity))?.message, '离开前保存');
  });

  testWidgets('ReplyComposerPage leaves without confirmation for empty input', (
    tester,
  ) async {
    await tester.pumpWidget(_buildLauncher());
    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('保存草稿并离开？'), findsNothing);
    expect(find.byKey(const Key('open-reply-composer-page')), findsOneWidget);
  });

  testWidgets('ReplyComposerPage successful submit does not show leave confirm', (
    tester,
  ) async {
    final replyRepository = _FakeReplyRepository(
      result: const ApiSuccess<ReplySubmissionResult>(
        ReplySubmissionResult(message: '回复发布成功'),
      ),
    );
    await tester.pumpWidget(_buildLauncher(replyRepository: replyRepository));
    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '提交内容',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(find.text('保存草稿并离开？'), findsNothing);
    expect(find.byKey(const Key('open-reply-composer-page')), findsOneWidget);
  });
}

Widget _buildPage({
  ReplyComposerArgs? args,
  ReplyDraftRepository? draftRepository,
  ReplyRepository? replyRepository,
  ReplyImagePicker? imagePicker,
  ReplyImageUploadCoordinator? imageUploadCoordinator,
  List<StickerGroup> stickerGroups = const [],
}) {
  return ProviderScope(
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
      replyImageUploadCoordinatorProvider.overrideWithValue(
        imageUploadCoordinator ?? _FakeReplyImageUploadCoordinator(),
      ),
      replyUploadNotificationServiceProvider.overrideWithValue(
        _FakeReplyUploadNotificationService(),
      ),
      forumBbCodeRendererProvider.overrideWithValue(_testRenderer),
      stickerGroupsProvider.overrideWith((_) async => stickerGroups),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        _FakeStickerPickerPreferencesRepository(),
      ),
      stickerPickerLastGroupIdProvider.overrideWith((ref) {
        return ref
            .read(stickerPickerPreferencesRepositoryProvider)
            .loadLastGroupId();
      }),
    ],
    child: MaterialApp(
      home: ReplyComposerPage(args: args ?? _threadArgs()),
    ),
  );
}

Widget _buildLauncher({
  ReplyDraftRepository? draftRepository,
  ReplyRepository? replyRepository,
  List<StickerGroup> stickerGroups = const [],
  ValueChanged<ReplyComposerResult>? onResult,
}) {
  return ProviderScope(
    overrides: [
      replyDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryReplyDraftRepository(),
      ),
      replyRepositoryProvider.overrideWithValue(
        replyRepository ?? _FakeReplyRepository(),
      ),
      replyImagePickerProvider.overrideWithValue(_FakeReplyImagePicker()),
      replyImageUploadCoordinatorProvider.overrideWithValue(
        _FakeReplyImageUploadCoordinator(),
      ),
      replyUploadNotificationServiceProvider.overrideWithValue(
        _FakeReplyUploadNotificationService(),
      ),
      forumBbCodeRendererProvider.overrideWithValue(_testRenderer),
      stickerGroupsProvider.overrideWith((_) async => stickerGroups),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        _FakeStickerPickerPreferencesRepository(),
      ),
      stickerPickerLastGroupIdProvider.overrideWith((ref) {
        return ref
            .read(stickerPickerPreferencesRepositoryProvider)
            .loadLastGroupId();
      }),
    ],
    child: MaterialApp(
      home: _ReplyComposerLauncher(onResult: onResult ?? ((_) {})),
    ),
  );
}

const _stickerGroups = [
  StickerGroup(
    id: 'bugcat',
    title: '貓貓蟲',
    stickers: [
      StickerItem(
        code: '{:9_656:}',
        assetPath: 'assets/stickers/bugcat/Capoo16.gif',
        rawCodePattern: '{:9_656:}',
      ),
    ],
  ),
];

ReplyComposerArgs _threadArgs() {
  return const ReplyComposerArgs(
    target: ReplyTarget.thread(fid: '33', tid: '572063'),
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
  _MemoryReplyDraftRepository({
    DateTime Function()? now,
  }) : _now = now;

  final Map<String, ReplyDraftSnapshot> _drafts = <String, ReplyDraftSnapshot>{};
  final DateTime Function()? _now;
  static const ReplyDraftAttachmentSanitizer _sanitizer =
      ReplyDraftAttachmentSanitizer();

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
    final draft = _drafts[identity.storageKey];
    final now = _now;
    if (draft == null || now == null) {
      return draft;
    }
    final result = _sanitizer.sanitize(
      message: draft.message,
      imageAttachments: draft.imageAttachments,
      now: now(),
    );
    final sanitized = ReplyDraftSnapshot(
      identity: draft.identity,
      message: result.message,
      useSignature: draft.useSignature,
      updatedAt: draft.updatedAt,
      imageAttachments: result.imageAttachments,
    );
    if (sanitized.isEmpty) {
      _drafts.remove(identity.storageKey);
      return null;
    }
    _drafts[identity.storageKey] = sanitized;
    return sanitized;
  }

  @override
  Future<ReplyDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
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

ReplyImageAttachment _uploadedAttachment({
  required String localId,
  required String aid,
  required DateTime uploadedAt,
  String? localPath,
}) {
  return ReplyImageAttachment(
    localId: localId,
    localPath: localPath ?? '/gallery/$localId.jpg',
    fileName: '$localId.jpg',
    mimeType: 'image/jpeg',
    order: 0,
    status: ReplyImageAttachmentStatus.uploaded,
    aid: aid,
    uploadedAt: uploadedAt,
  );
}

final _testRenderer = FlutterBbCodeForumRenderer(
  attachImageBuilder: _buildTestAttachPreviewImage,
  attachFileExists: _testAttachFileExists,
);

Widget _buildTestAttachPreviewImage(File file, Key key) {
  return _TestAttachPreviewImage(file: file, key: key);
}

bool _testAttachFileExists(File file) {
  return !file.path.contains('/missing/');
}

class _TestAttachPreviewImage extends StatelessWidget {
  const _TestAttachPreviewImage({
    super.key,
    required this.file,
  });

  final File file;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 28, height: 28);
  }
}

class _FakeStickerPickerPreferencesRepository
    implements StickerPickerPreferencesRepository {
  String? lastGroupId;

  @override
  Future<String?> loadLastGroupId() async {
    return lastGroupId;
  }

  @override
  Future<void> saveLastGroupId(String groupId) async {
    lastGroupId = groupId;
  }
}

class _FakeReplyImagePicker implements ReplyImagePicker {
  _FakeReplyImagePicker({
    this.images = const <ReplyPickedImage>[],
  });

  final List<ReplyPickedImage> images;

  @override
  Future<List<ReplyPickedImage>> pickImagesInOrder() async {
    return images;
  }
}

class _FakeReplyImageUploadCoordinator implements ReplyImageUploadCoordinator {
  _FakeReplyImageUploadCoordinator({
    this.events = const <ReplyImageUploadEvent>[],
  });

  final List<ReplyImageUploadEvent> events;

  @override
  void cancel() {}

  @override
  Stream<ReplyImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ReplyImageAttachment> attachments,
  }) async* {
    for (final event in events) {
      if (event.type == ReplyImageUploadEventType.completed) {
        yield ReplyImageUploadEvent.completed(total: event.total);
        continue;
      }
      final localId = event.localId.isNotEmpty
          ? event.localId
          : attachments[
                  (event.current - 1).clamp(0, attachments.length - 1).toInt()]
              .localId;
      yield switch (event.type) {
        ReplyImageUploadEventType.started => ReplyImageUploadEvent.started(
            localId: localId,
            current: event.current,
            total: event.total,
          ),
        ReplyImageUploadEventType.progress => ReplyImageUploadEvent.progress(
            localId: localId,
            current: event.current,
            total: event.total,
            progress: event.progress ?? 0,
          ),
        ReplyImageUploadEventType.uploaded => ReplyImageUploadEvent.uploaded(
            localId: localId,
            current: event.current,
            total: event.total,
            uploadedImage: ReplyUploadedImage(
              localId: localId,
              aid: event.uploadedImage!.aid,
              uploadedAt: event.uploadedImage!.uploadedAt,
            ),
          ),
        ReplyImageUploadEventType.failed => ReplyImageUploadEvent.failed(
            localId: localId,
            current: event.current,
            total: event.total,
            errorMessage: event.errorMessage ?? '图片上传失败',
          ),
        ReplyImageUploadEventType.completed => ReplyImageUploadEvent.completed(
            total: event.total,
          ),
      };
    }
  }
}

class _FakeReplyUploadNotificationService
    implements ReplyUploadNotificationService {
  @override
  Future<void> clear() async {}

  @override
  Future<void> showFailure({
    required int failedCount,
    required int total,
  }) async {}

  @override
  Future<void> showProgress({
    required int current,
    required int total,
  }) async {}
}

class _FakeReplyRepository implements ReplyRepository {
  _FakeReplyRepository({
    ApiResult<ReplySubmissionResult>? result,
    ApiResult<ReplyPreparation>? preparationResult,
    this.asyncPreparationResult,
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
  final ApiResult<ReplyPreparation> preparationResult;
  final Future<ApiResult<ReplyPreparation>>? asyncPreparationResult;
  final List<ReplyDraft> sentDrafts = <ReplyDraft>[];

  @override
  Future<ApiResult<ReplySubmissionResult>> sendReply({
    required ReplyDraft draft,
  }) async {
    sentDrafts.add(draft);
    return result;
  }

  @override
  Future<ApiResult<ReplyPreparation>> preparePostReply({
    required Uri replyFormUri,
  }) async {
    final asyncPreparationResult = this.asyncPreparationResult;
    if (asyncPreparationResult != null) {
      return asyncPreparationResult;
    }
    return preparationResult;
  }
}
