import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/services/composer_image_picker.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/data/services/composer_upload_notification_service.dart';
import 'package:y300/features/composer_shared/data/repositories/sticker_picker_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/models/composer_attachment_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/composer_shared/domain/models/composer_preferences.dart';
import 'package:y300/features/composer_shared/domain/repositories/composer_preferences_repository.dart';
import 'package:y300/features/composer_shared/domain/services/composer_draft_attachment_sanitizer.dart';
import 'package:y300/features/composer_shared/domain/services/composer_image_upload_coordinator.dart';
import 'package:y300/features/composer_shared/presentation/bbcode/forum_bbcode_renderer.dart';
import 'package:y300/features/reply/data/providers/reply_providers.dart';
import 'package:y300/features/reply/data/repositories/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/reply/presentation/reply_composer_page.dart';
import 'package:y300/features/reply/presentation/reply_composer_state.dart';

void main() {
  testWidgets('ReplyComposerPage builds dark theme chrome', (tester) async {
    await tester.pumpWidget(_buildPage(theme: AppTheme.dark()));
    await tester.pump();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-quill-editor')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-send-button')), findsOneWidget);
  });

  testWidgets('ReplyComposerPage shows minimal composer UI', (tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    expect(find.text('回复帖子'), findsOneWidget);
    expect(find.text('预览'), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-source-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-more-button')), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-sticker-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('reply-composer-format-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-color-button')), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-backcolor-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('reply-composer-link-button')), findsOneWidget);
    expect(find.byKey(const Key('reply-composer-size-button')), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-quote-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-code-button')), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-align-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-message-input')), findsNothing);
    expect(
      find.byKey(const Key('reply-composer-bbcode-preview-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reply-composer-use-signature-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reply-composer-image-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-send-button')), findsOneWidget);
  });

  testWidgets('ReplyComposerPage restores and updates the default surface', (
    tester,
  ) async {
    final preferencesRepository = _FakeComposerPreferencesRepository(
      preferences: const ComposerPreferences(
        defaultSurface: ComposerSurfacePreference.source,
        newDraftUseSignature: true,
      ),
    );
    await tester.pumpWidget(
      _buildPage(preferencesRepository: preferencesRepository),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reply-composer-message-input')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reply-composer-quill-editor')), findsNothing);

    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reply-composer-quill-editor')),
      findsOneWidget,
    );
    expect(
      preferencesRepository.preferences.defaultSurface,
      ComposerSurfacePreference.quill,
    );
  });

  testWidgets('ReplyComposerPage wraps selection with quote BBCode', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();
    await _enterReplySourceText(tester, '前引用后');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 3,
    );

    await tester.tap(find.byKey(const Key('reply-composer-quote-button')));
    await tester.pump();

    expect(editable.controller.text, '前[quote]引用[/quote]后');
  });

  testWidgets('ReplyComposerPage wraps selection from text context menu', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();
    await _enterReplySourceText(tester, '前选中后');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 3,
    );
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();

    expect(find.text('代码'), findsNothing);

    await tester.tap(find.text('引用'));
    await tester.pumpAndSettle();

    expect(editable.controller.text, '前[quote]选中[/quote]后');
  });

  testWidgets('ReplyComposerPage inserts picked backcolor BBCode', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();
    await _openReplySourceEditor(tester);

    await tester.tap(find.byKey(const Key('reply-composer-backcolor-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('reply-composer-backcolor-sheet')),
      findsOneWidget,
    );
    final picker = tester.widget<ColorPicker>(
      find.byKey(const Key('reply-composer-backcolor-picker')),
    );
    picker.onColorChanged(const Color(0xffff33aa));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('reply-composer-backcolor-use-button')),
    );
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, '[backcolor=#ff33aa][/backcolor]');
    expect(editable.controller.selection.baseOffset, 19);
    expect(editable.controller.selection.extentOffset, 19);
  });

  testWidgets('ReplyComposerPage places more action before image and send', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    final moreCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-more-button')),
    );
    final sendCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-send-button')),
    );

    final sourceCenter = tester.getCenter(
      find.byKey(const Key('reply-composer-source-button')),
    );

    expect(sourceCenter.dx, lessThan(moreCenter.dx));
    expect(moreCenter.dx, lessThan(sendCenter.dx));
  });

  testWidgets('ReplyComposerPage keeps Quill toolbar pinned to bottom', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    final scaffoldBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;
    final imageButtonBottom = tester
        .getBottomLeft(find.byKey(const Key('reply-composer-image-button')))
        .dy;

    expect(scaffoldBottom - imageButtonBottom, lessThan(64));
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
    await tester.pump();

    await _openReplySourceEditor(tester);
    final restoredField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    expect(restoredField.controller?.text, '恢复的草稿');
    expect(find.text('已恢复未发送草稿'), findsOneWidget);
    expect(
      find.byKey(const Key('reply-composer-restored-draft-banner')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reply-composer-use-signature-switch')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('reply-composer-more-button')));
    await tester.pumpAndSettle();
    final switchTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('reply-composer-use-signature-switch')),
    );
    expect(switchTile.value, isFalse);
    await tester.tap(
      find.byKey(const Key('reply-composer-use-signature-switch')),
    );
    await tester.pumpAndSettle();
    final toggledSwitchTile = tester.widget<SwitchListTile>(
      find.byKey(const Key('reply-composer-use-signature-switch')),
    );
    expect(toggledSwitchTile.value, isTrue);
  });

  testWidgets('ReplyComposerPage restores uploaded image without fixed queue', (
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

    expect(find.byKey(const Key('reply-composer-image-queue')), findsNothing);
    expect(find.textContaining('已上传'), findsNothing);
    expect(
      find.byKey(const Key('composer-quill-attach-123456')),
      findsOneWidget,
    );
  });

  testWidgets('ReplyComposerPage restores uploaded attach embed', (
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

    expect(
      find.byKey(const Key('composer-quill-attach-123456')),
      findsOneWidget,
    );
    expect(
      find.textContaining('[attach]123456[/attach]', findRichText: true),
      findsNothing,
    );
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
    await _openReplySourceEditor(tester);
    final sanitizedField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    expect(sanitizedField.controller?.text, '正文');
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

  testWidgets('ReplyComposerPage switches source and Quill editor', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pump();

    expect(
      find.byKey(const Key('reply-composer-quill-editor')),
      findsOneWidget,
    );
    await _enterReplySourceText(tester, '[b]粗体内容[/b]');
    await tester.pump();

    expect(
      find.byKey(const Key('reply-composer-bbcode-preview-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reply-composer-message-input')),
      findsOneWidget,
    );
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, '[b]粗体内容[/b]');
    final sourceField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    final decoration = sourceField.decoration;
    expect(decoration?.border, InputBorder.none);
    expect(decoration?.enabledBorder, InputBorder.none);
    expect(decoration?.focusedBorder, InputBorder.none);
    expect(decoration?.disabledBorder, InputBorder.none);
    expect(decoration?.filled, isFalse);
    expect(decoration?.fillColor, isNull);

    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('reply-composer-quill-editor')),
      findsOneWidget,
    );
    expect(find.text('粗体内容', findRichText: true), findsOneWidget);
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
    await _enterReplySourceText(tester, '提交内容');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(replyRepository.sentDrafts.single.message, '提交内容');
    expect(poppedResult?.sent, isTrue);
    expect(poppedResult?.message, '回复发布成功');
  });

  testWidgets('ReplyComposerPage submits raw source message from source mode', (
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
    await _enterReplySourceText(tester, '[quote]原始源码[/quote]');
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
    await _enterReplySourceText(tester, '前后');
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

  testWidgets('ReplyComposerPage shows inserted sticker as Quill embed', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage(stickerGroups: _stickerGroups));
    await tester.pump();
    await _enterReplySourceText(tester, '{:9_656:}');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('composer-quill-sticker-{:9_656:}')),
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
    await _enterReplySourceText(tester, '表情{:9_656:}');
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
      find.descendant(
        of: find.byKey(const Key('reply-composer-image-button')),
        matching: find.byType(IconButton),
      ),
    );
    expect(imageButton.onPressed, isNull);
    preparationCompleter.complete(
      const ApiSuccess<ReplyPreparation>(
        ReplyPreparation(
          target: ReplyTarget.post(fid: '33', tid: '572063', pid: '41554317'),
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
            ComposerImageUploadEvent.started(localId: '', current: 1, total: 1),
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
            ComposerImageUploadEvent.uploaded(
              localId: '',
              current: 1,
              total: 1,
              uploadedImage: ReplyUploadedImage(
                localId: '',
                aid: '123456',
                uploadedAt: DateTime.now(),
              ),
            ),
            const ComposerImageUploadEvent.completed(total: 1),
          ],
        ),
      ),
    );
    await tester.pump();
    await _enterReplySourceText(tester, '正文');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('reply-composer-image-button')));
    await _pumpUntilMessageContains(tester, '[attach]123456[/attach]');
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, '正文\n[attach]123456[/attach]');
    expect(find.byKey(const Key('reply-composer-image-queue')), findsNothing);
    expect(find.text('first.jpg 已上传'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(
      replyRepository.sentDrafts.single.message,
      '正文\n[attach]123456[/attach]',
    );
  });

  testWidgets(
    'ReplyComposerPage shows uploaded image embed and submits raw attach code',
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
              ComposerImageUploadEvent.uploaded(
                localId: '',
                current: 1,
                total: 1,
                uploadedImage: ReplyUploadedImage(
                  localId: '',
                  aid: '123456',
                  uploadedAt: DateTime.now(),
                ),
              ),
              const ComposerImageUploadEvent.completed(total: 1),
            ],
          ),
        ),
      );
      await tester.pump();
      await _enterReplySourceText(tester, '正文');
      await tester.pump();
      await tester.tap(find.byKey(const Key('reply-composer-source-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reply-composer-image-button')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('composer-quill-attach-123456')),
      );
      await tester.pump();

      expect(find.byKey(const Key('reply-composer-image-queue')), findsNothing);
      expect(find.text('uploaded.png 已上传'), findsOneWidget);
      expect(
        find.byKey(const Key('composer-quill-attach-123456')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('composer-quill-attach-image-123456')),
        findsOneWidget,
      );
      final previewImage = tester.widget<_TestAttachPreviewImage>(
        find.byKey(const Key('composer-quill-attach-image-123456')),
      );
      expect(previewImage.file.path, path);
      expect(
        find.textContaining('[attach]123456[/attach]', findRichText: true),
        findsNothing,
      );

      await _openReplySourceEditor(tester);
      final sourceField = tester.widget<TextField>(
        find.byKey(const Key('reply-composer-message-input')),
      );
      expect(sourceField.controller?.text, '正文\n[attach]123456[/attach]');
      await tester.tap(find.byKey(const Key('reply-composer-send-button')));
      await tester.pumpAndSettle();

      expect(
        replyRepository.sentDrafts.single.message,
        '正文\n[attach]123456[/attach]',
      );
    },
  );

  testWidgets(
    'ReplyComposerPage shows upload failure without changing message',
    (tester) async {
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
              ComposerImageUploadEvent.failed(
                localId: '',
                current: 1,
                total: 1,
                errorMessage: '图片上传失败',
              ),
              const ComposerImageUploadEvent.completed(total: 1),
            ],
          ),
        ),
      );
      await tester.pump();
      await _enterReplySourceText(tester, '正文');
      await tester.pump();
      await tester.tap(find.byKey(const Key('reply-composer-source-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reply-composer-image-button')));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('上传失败'), findsWidgets);
      await _openReplySourceEditor(tester);
      final sourceField = tester.widget<TextField>(
        find.byKey(const Key('reply-composer-message-input')),
      );
      expect(sourceField.controller?.text, '正文');
      expect(find.textContaining('[attach]'), findsNothing);
    },
  );

  testWidgets('ReplyComposerPage submits post reply with reference fields', (
    tester,
  ) async {
    final replyRepository = _FakeReplyRepository();
    await tester.pumpWidget(
      _buildPage(args: _postArgs(), replyRepository: replyRepository),
    );
    await tester.pump();
    await tester.pump();
    await _enterReplySourceText(tester, '楼层回复');
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
    await _enterReplySourceText(tester, '未发送内容');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('保存草稿并离开？'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('reply-composer-continue-edit-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('reply-composer-message-input')),
      findsOneWidget,
    );
  });

  testWidgets('ReplyComposerPage saves draft and leaves after confirmation', (
    tester,
  ) async {
    final draftRepository = _MemoryReplyDraftRepository();
    await tester.pumpWidget(_buildLauncher(draftRepository: draftRepository));
    await tester.tap(find.byKey(const Key('open-reply-composer-page')));
    await tester.pumpAndSettle();
    await _enterReplySourceText(tester, '离开前保存');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reply-composer-save-leave-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-reply-composer-page')), findsOneWidget);
    expect(
      (await draftRepository.loadDraft(_threadArgs().identity))?.message,
      '离开前保存',
    );
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

  testWidgets(
    'ReplyComposerPage successful submit does not show leave confirm',
    (tester) async {
      final replyRepository = _FakeReplyRepository(
        result: const ApiSuccess<ReplySubmissionResult>(
          ReplySubmissionResult(message: '回复发布成功'),
        ),
      );
      await tester.pumpWidget(_buildLauncher(replyRepository: replyRepository));
      await tester.tap(find.byKey(const Key('open-reply-composer-page')));
      await tester.pumpAndSettle();
      await _enterReplySourceText(tester, '提交内容');
      await tester.pump();
      await tester.tap(find.byKey(const Key('reply-composer-send-button')));
      await tester.pumpAndSettle();

      expect(find.text('保存草稿并离开？'), findsNothing);
      expect(find.byKey(const Key('open-reply-composer-page')), findsOneWidget);
    },
  );
}

Widget _buildPage({
  ReplyComposerArgs? args,
  ComposerDraftRepository? draftRepository,
  ComposerPreferencesRepository? preferencesRepository,
  ReplyRepository? replyRepository,
  ComposerImagePicker? imagePicker,
  ComposerImageUploadCoordinator? imageUploadCoordinator,
  List<StickerGroup> stickerGroups = const [],
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryReplyDraftRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        preferencesRepository ?? _FakeComposerPreferencesRepository(),
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
      composerUploadNotificationServiceProvider.overrideWithValue(
        _FakeReplyUploadNotificationService(),
      ),
      forumBbCodeRendererProvider.overrideWithValue(_testRenderer),
      stickerGroupsProvider.overrideWith((_) async => stickerGroups),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        _FakeStickerPickerPreferencesRepository(),
      ),
      imageCacheServiceProvider.overrideWithValue(_FailingImageCacheService()),
    ],
    child: MaterialApp(
      theme: theme,
      home: ReplyComposerPage(args: args ?? _threadArgs()),
    ),
  );
}

Future<void> _pumpUntilMessageContains(
  WidgetTester tester,
  String expected, {
  int maxPumps = 12,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump();
    if (find
        .byKey(const Key('reply-composer-message-input'))
        .evaluate()
        .isEmpty) {
      await _openReplySourceEditor(tester);
    }
    final sourceField = tester.widget<TextField>(
      find.byKey(const Key('reply-composer-message-input')),
    );
    if ((sourceField.controller?.text ?? '').contains(expected)) {
      return;
    }
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 12,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _enterReplySourceText(WidgetTester tester, String text) async {
  await _openReplySourceEditor(tester);
  await tester.enterText(
    find.byKey(const Key('reply-composer-message-input')),
    text,
  );
}

Future<void> _openReplySourceEditor(WidgetTester tester) async {
  if (find
      .byKey(const Key('reply-composer-message-input'))
      .evaluate()
      .isNotEmpty) {
    return;
  }
  await tester.tap(find.byKey(const Key('reply-composer-source-button')));
  await tester.pumpAndSettle();
}

Widget _buildLauncher({
  ComposerDraftRepository? draftRepository,
  ReplyRepository? replyRepository,
  List<StickerGroup> stickerGroups = const [],
  ThemeData? theme,
  ValueChanged<ReplyComposerResult>? onResult,
}) {
  return ProviderScope(
    overrides: [
      composerDraftRepositoryProvider.overrideWithValue(
        draftRepository ?? _MemoryReplyDraftRepository(),
      ),
      composerPreferencesRepositoryProvider.overrideWithValue(
        _FakeComposerPreferencesRepository(),
      ),
      replyRepositoryProvider.overrideWithValue(
        replyRepository ?? _FakeReplyRepository(),
      ),
      composerImagePickerProvider.overrideWithValue(_FakeReplyImagePicker()),
      composerImageUploadCoordinatorProvider.overrideWithValue(
        _FakeReplyImageUploadCoordinator(),
      ),
      composerUploadNotificationServiceProvider.overrideWithValue(
        _FakeReplyUploadNotificationService(),
      ),
      forumBbCodeRendererProvider.overrideWithValue(_testRenderer),
      stickerGroupsProvider.overrideWith((_) async => stickerGroups),
      stickerPickerPreferencesRepositoryProvider.overrideWithValue(
        _FakeStickerPickerPreferencesRepository(),
      ),
      imageCacheServiceProvider.overrideWithValue(_FailingImageCacheService()),
    ],
    child: MaterialApp(
      theme: theme,
      home: _ReplyComposerLauncher(onResult: onResult ?? ((_) {})),
    ),
  );
}

final _stickerGroups = [
  StickerGroup(
    id: 'bugcat',
    title: '貓貓蟲',
    stickers: [_sticker(code: '{:9_656:}', imagePath: 'bugcat/Capoo16.gif')],
  ),
];

class _FakeComposerPreferencesRepository
    implements ComposerPreferencesRepository {
  _FakeComposerPreferencesRepository({ComposerPreferences? preferences})
    : preferences = preferences ?? ComposerPreferences.defaults();

  ComposerPreferences preferences;

  @override
  Future<ComposerPreferences> load() async => preferences;

  @override
  Future<void> save(ComposerPreferences preferences) async {
    this.preferences = preferences;
  }
}

StickerItem _sticker({required String code, required String imagePath}) {
  return StickerItem(
    code: code,
    rawCodePattern: code,
    imagePath: imagePath,
    imageUrl: 'https://bbs.yamibo.com/static/image/smiley/$imagePath',
    cacheKey: ImageCacheKeys.remoteSmiley(imagePath),
  );
}

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
  const _ReplyComposerLauncher({required this.onResult});

  final ValueChanged<ReplyComposerResult> onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('open-reply-composer-page'),
          onPressed: () async {
            final result = await Navigator.of(context)
                .push<ReplyComposerResult>(
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

class _MemoryReplyDraftRepository implements ComposerDraftRepository {
  _MemoryReplyDraftRepository({DateTime Function()? now}) : _now = now;

  final Map<String, ComposerDraftSnapshot> _drafts =
      <String, ComposerDraftSnapshot>{};
  final DateTime Function()? _now;
  static const ComposerDraftAttachmentSanitizer _sanitizer =
      ComposerDraftAttachmentSanitizer();

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
    final sanitized = ComposerDraftSnapshot(
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
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
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
  stickerImageBuilder: _buildTestStickerPreviewImage,
);

Widget _buildTestAttachPreviewImage(File file, Key key) {
  return _TestAttachPreviewImage(file: file, key: key);
}

Widget _buildTestStickerPreviewImage(StickerItem sticker, Key key) {
  return _TestStickerPreviewImage(sticker: sticker, key: key);
}

bool _testAttachFileExists(File file) {
  return !file.path.contains('/missing/');
}

class _TestAttachPreviewImage extends StatelessWidget {
  const _TestAttachPreviewImage({super.key, required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 28, height: 28);
  }
}

class _TestStickerPreviewImage extends StatelessWidget {
  const _TestStickerPreviewImage({super.key, required this.sticker});

  final StickerItem sticker;

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

class _FailingImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

class _FakeReplyImagePicker implements ComposerImagePicker {
  _FakeReplyImagePicker({this.images = const <ComposerPickedImage>[]});

  final List<ComposerPickedImage> images;

  @override
  Future<List<ComposerPickedImage>> pickImagesInOrder() async {
    return images;
  }
}

class _FakeReplyImageUploadCoordinator
    implements ComposerImageUploadCoordinator {
  _FakeReplyImageUploadCoordinator({
    this.events = const <ComposerImageUploadEvent>[],
  });

  final List<ComposerImageUploadEvent> events;

  @override
  void cancel() {}

  @override
  Stream<ComposerImageUploadEvent> uploadInOrder({
    required String fid,
    required List<ComposerImageAttachment> attachments,
  }) async* {
    for (final event in events) {
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
      yield switch (event.type) {
        ComposerImageUploadEventType.started =>
          ComposerImageUploadEvent.started(
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
          errorMessage: event.errorMessage ?? '图片上传失败',
        ),
        ComposerImageUploadEventType.completed =>
          ComposerImageUploadEvent.completed(total: event.total),
      };
    }
  }
}

class _FakeReplyUploadNotificationService
    implements ComposerUploadNotificationService {
  @override
  Future<void> clear() async {}

  @override
  Future<void> showFailure({
    required int failedCount,
    required int total,
  }) async {}

  @override
  Future<void> showProgress({required int current, required int total}) async {}
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
